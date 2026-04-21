# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule BurbleWeb.API.LLMController do
  @moduledoc """
  REST endpoint for server-side LLM queries.

  Either side of the P2P bridge can POST a prompt and get a Claude response
  back. Requires authentication (JWT) in production; dev mode accepts any
  request so the bridge can call it without token setup.

  ## Endpoints

    POST /api/v1/llm/query   — synchronous, returns full response
    POST /api/v1/llm/stream  — synchronous (buffered SSE), returns full response
    GET  /api/v1/llm/status  — provider availability check
  """

  use Phoenix.Controller, formats: [:json]
  require Logger

  @max_prompt_length 32_000

  @doc "Synchronous LLM query — returns `{response: text}` or `{error: reason}`."
  def query(conn, %{"prompt" => prompt}) when byte_size(prompt) <= @max_prompt_length do
    user_id = get_user_id(conn)

    case Burble.LLM.process_query(user_id, prompt) do
      {:ok, text} ->
        json(conn, %{ok: true, response: text})

      {:error, :no_provider_configured} ->
        conn |> put_status(503) |> json(%{ok: false, error: "llm_not_configured"})

      {:error, :api_key_not_configured} ->
        conn |> put_status(503) |> json(%{ok: false, error: "api_key_not_set"})

      {:error, {:api_error, status}} ->
        conn |> put_status(502) |> json(%{ok: false, error: "upstream_error", status: status})

      {:error, reason} ->
        Logger.warning("[LLMController] Query failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{ok: false, error: "internal_error"})
    end
  end

  def query(conn, %{"prompt" => _prompt}) do
    conn |> put_status(413) |> json(%{ok: false, error: "prompt_too_long", max: @max_prompt_length})
  end

  def query(conn, _params) do
    conn |> put_status(400) |> json(%{ok: false, error: "missing_prompt"})
  end

  @doc "Streaming LLM query — buffers chunks and returns full concatenated response."
  def stream(conn, %{"prompt" => prompt}) when byte_size(prompt) <= @max_prompt_length do
    user_id = get_user_id(conn)
    chunks = :ets.new(:llm_chunks, [:ordered_set, :private])
    counter = :counters.new(1, [:atomics])

    result = Burble.LLM.stream_query(user_id, prompt, fn chunk ->
      idx = :counters.add(counter, 1, 1)
      :ets.insert(chunks, {idx, chunk})
    end)

    case result do
      :ok ->
        full_text = :ets.tab2list(chunks) |> Enum.map_join(fn {_k, v} -> v end)
        :ets.delete(chunks)
        json(conn, %{ok: true, response: full_text, streamed: true})

      {:error, reason} ->
        :ets.delete(chunks)
        conn |> put_status(502) |> json(%{ok: false, error: inspect(reason)})
    end
  end

  def stream(conn, params), do: query(conn, params)

  @doc "Check LLM provider status."
  def status(conn, _params) do
    provider = :persistent_term.get({Burble.LLM, :provider}, nil)

    json(conn, %{
      available: provider != nil,
      provider: if(provider, do: inspect(provider), else: nil),
      api_key_set: System.get_env("ANTHROPIC_API_KEY") != nil
    })
  end

  defp get_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> "anonymous"
    end
  end
end
