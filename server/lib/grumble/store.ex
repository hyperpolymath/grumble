# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Store — VeriSimDB-backed persistent store.
#
# Replaces Ecto/PostgreSQL with VeriSimDB octad entities. Each user account
# is stored as a VeriSimDB octad with document modality (structured fields)
# and provenance modality (login history, audit trail).
#
# The Store is a GenServer that holds the VeriSimClient connection and
# provides domain-specific CRUD operations. It starts as part of the
# OTP supervision tree before any module that needs persistence.
#
# Dogfooding: Burble is the first hyperpolymath project to run on VeriSimDB
# as its primary data store. Exercises the Elixir client SDK, REST API,
# and document modality in a real production workload.

defmodule Burble.Store do
  @moduledoc """
  VeriSimDB-backed persistent store for Burble.

  Provides user account CRUD, token storage, and audit logging via
  VeriSimDB octad entities. Each domain entity maps to an octad with
  appropriate modalities populated.

  ## Entity mapping

  | Domain entity | Octad name prefix | Modalities used                    |
  |---------------|-------------------|------------------------------------|
  | User account  | `user:<email>`    | document (fields), provenance (audit) |
  | Invite token  | `invite:<token>`  | document (fields), temporal (expiry)  |
  | Magic link    | `magic:<token>`   | document (fields), temporal (expiry)  |

  ## Configuration

  In `config.exs`:

      config :burble, Burble.Store,
        url: "http://localhost:8080",
        auth: :none,
        timeout: 30_000
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc "Start the Store GenServer, linking to the supervision tree."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new user account in VeriSimDB.

  Stores the user as an octad with document modality containing the
  structured fields and provenance modality recording the creation event.

  Returns `{:ok, user_map}` or `{:error, reason}`.
  """
  @spec create_user(map()) :: {:ok, map()} | {:error, term()}
  def create_user(attrs) do
    GenServer.call(__MODULE__, {:create_user, attrs})
  end

  @doc """
  Look up a user by email address.

  Uses VeriSimDB text search on the octad name (which encodes the email).
  Returns `{:ok, user_map}` or `{:error, :not_found}`.
  """
  @spec get_user_by_email(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_user_by_email(email) do
    GenServer.call(__MODULE__, {:get_user_by_email, email})
  end

  @doc """
  Look up a user by their VeriSimDB octad ID.

  Returns `{:ok, user_map}` or `{:error, :not_found}`.
  """
  @spec get_user(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_user(id) do
    GenServer.call(__MODULE__, {:get_user, id})
  end

  @doc """
  Update a user's fields (partial merge).

  Returns `{:ok, user_map}` or `{:error, reason}`.
  """
  @spec update_user(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_user(id, attrs) do
    GenServer.call(__MODULE__, {:update_user, id, attrs})
  end

  @doc """
  Record a provenance event against a user (login, password change, etc.).
  """
  @spec record_user_event(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def record_user_event(user_id, event_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_user_event, user_id, event_type, metadata})
  end

  @doc """
  Check if the VeriSimDB connection is healthy.
  """
  @spec health() :: {:ok, boolean()} | {:error, term()}
  def health do
    GenServer.call(__MODULE__, :health)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    config = Application.get_env(:burble, __MODULE__, [])
    url = Keyword.get(config, :url, "http://localhost:8080")
    auth = Keyword.get(config, :auth, :none)
    timeout = Keyword.get(config, :timeout, 30_000)

    case VeriSimClient.new(url, auth: auth, timeout: timeout) do
      {:ok, client} ->
        Logger.info("[Burble.Store] Connected to VeriSimDB at #{url}")
        {:ok, %{client: client}}

      {:error, reason} ->
        Logger.error("[Burble.Store] Failed to connect to VeriSimDB: #{inspect(reason)}")
        {:stop, {:verisimdb_connection_failed, reason}}
    end
  end

  @impl true
  def handle_call({:create_user, attrs}, _from, %{client: client} = state) do
    email = Map.get(attrs, :email) || Map.get(attrs, "email")
    display_name = Map.get(attrs, :display_name) || Map.get(attrs, "display_name")
    password_hash = Map.get(attrs, :password_hash) || Map.get(attrs, "password_hash")
    is_admin = Map.get(attrs, :is_admin, false)
    mfa_enabled = Map.get(attrs, :mfa_enabled, false)

    octad_input = %{
      name: "user:#{String.downcase(email)}",
      description: "Burble user account: #{display_name}",
      metadata: %{entity_type: "burble_user"},
      document: %{
        content: Jason.encode!(%{
          email: String.downcase(email),
          display_name: display_name,
          password_hash: password_hash,
          is_admin: is_admin,
          mfa_enabled: mfa_enabled,
          mfa_secret: nil,
          last_seen_at: nil
        }),
        content_type: "application/json",
        language: "en",
        metadata: %{schema_version: 1}
      },
      provenance: %{
        event_type: "account_created",
        agent: "burble_auth",
        description: "User account registered",
        metadata: %{ip: "unknown"}
      }
    }

    case VeriSimClient.Octad.create(client, octad_input) do
      {:ok, octad} ->
        user = octad_to_user(octad)
        {:reply, {:ok, user}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_user_by_email, email}, _from, %{client: client} = state) do
    # Search by octad name which encodes the email.
    normalised = String.downcase(email)
    search_name = "user:#{normalised}"

    case VeriSimClient.Search.text(client, search_name, limit: 1) do
      {:ok, results} when is_list(results) ->
        case Enum.find(results, fn r ->
          get_in(r, ["name"]) == search_name || get_in(r, [:name]) == search_name
        end) do
          nil -> {:reply, {:error, :not_found}, state}
          octad -> {:reply, {:ok, octad_to_user(octad)}, state}
        end

      {:ok, %{"data" => data}} when is_list(data) ->
        case Enum.find(data, fn r ->
          get_in(r, ["name"]) == search_name || get_in(r, [:name]) == search_name
        end) do
          nil -> {:reply, {:error, :not_found}, state}
          octad -> {:reply, {:ok, octad_to_user(octad)}, state}
        end

      {:ok, _} ->
        {:reply, {:error, :not_found}, state}

      {:error, reason} ->
        Logger.warning("[Burble.Store] User lookup failed: #{inspect(reason)}")
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_user, id}, _from, %{client: client} = state) do
    case VeriSimClient.Octad.get(client, id) do
      {:ok, octad} -> {:reply, {:ok, octad_to_user(octad)}, state}
      {:error, {:not_found, _}} -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_user, id, attrs}, _from, %{client: client} = state) do
    # Fetch current document content, merge, and update.
    case VeriSimClient.Octad.get(client, id) do
      {:ok, octad} ->
        current_doc = extract_document_fields(octad)
        merged = Map.merge(current_doc, stringify_keys(attrs))

        update_input = %{
          document: %{
            content: Jason.encode!(merged),
            content_type: "application/json",
            metadata: %{schema_version: 1}
          }
        }

        case VeriSimClient.Octad.update(client, id, update_input) do
          {:ok, updated} -> {:reply, {:ok, octad_to_user(updated)}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:health, _from, %{client: client} = state) do
    result = VeriSimClient.health(client)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:record_user_event, user_id, event_type, metadata}, %{client: client} = state) do
    update_input = %{
      provenance: %{
        event_type: event_type,
        agent: "burble_auth",
        description: "#{event_type} for user #{user_id}",
        metadata: metadata
      }
    }

    case VeriSimClient.Octad.update(client, user_id, update_input) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.warning("[Burble.Store] Failed to record event: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Extract user fields from a VeriSimDB octad response.
  # The document modality content is a JSON string containing the user fields.
  defp octad_to_user(octad) do
    fields = extract_document_fields(octad)
    id = get_in(octad, ["id"]) || get_in(octad, [:id])
    created_at = get_in(octad, ["created_at"]) || get_in(octad, [:created_at])
    modified_at = get_in(octad, ["modified_at"]) || get_in(octad, [:modified_at])

    %{
      id: id,
      email: fields["email"],
      display_name: fields["display_name"],
      password_hash: fields["password_hash"],
      is_admin: fields["is_admin"] || false,
      mfa_enabled: fields["mfa_enabled"] || false,
      mfa_secret: fields["mfa_secret"],
      last_seen_at: fields["last_seen_at"],
      inserted_at: created_at,
      updated_at: modified_at
    }
  end

  # Parse the document modality content (JSON string) into a map.
  defp extract_document_fields(octad) do
    doc = get_in(octad, ["document"]) || get_in(octad, [:document]) || %{}
    content = doc["content"] || doc[:content] || "{}"

    case content do
      c when is_binary(c) ->
        case Jason.decode(c) do
          {:ok, parsed} -> parsed
          {:error, _} -> %{}
        end

      c when is_map(c) ->
        # Already decoded by Req/Jason.
        c

      _ ->
        %{}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
