# SPDX-License-Identifier: PMPL-1.0-or-later
#
# BurbleWeb.API.MessageController — REST API for room text messages.
#
# Provides HTTP endpoints for fetching and posting text messages in
# Burble rooms. Messages are persisted via the NNTPS backend (threaded,
# archivable, verifiable). Real-time delivery uses the Phoenix channel;
# this controller handles initial load and scrollback.
#
# Author: Jonathan D.A. Jewell

defmodule BurbleWeb.API.MessageController do
  @moduledoc """
  REST API controller for room text messages.

  ## Endpoints

  - `GET /api/v1/rooms/:id/messages` — Fetch recent messages
  - `POST /api/v1/rooms/:id/messages` — Post a new message

  Messages are stored via `Burble.Text.NNTPSBackend` and include
  NNTPS threading (References headers) and Vext verification hashes.
  """

  use Phoenix.Controller, formats: [:json]

  alias Burble.Text.NNTPSBackend
  alias Burble.Permissions

  @doc """
  Fetch recent messages for a room.

  ## Query parameters

    * `limit` — Max messages to return (default 50, max 200)
    * `before` — Message ID cursor for pagination (fetch older messages)

  ## Response

  ```json
  {
    "messages": [
      {
        "message_id": "<abc123@burble.local>",
        "body": "Hello world",
        "display_name": "Alice",
        "user_id": "user_123",
        "sent_at": "2026-03-22T14:30:00Z",
        "references": [],
        "is_pinned": false
      }
    ]
  }
  ```
  """
  def index(conn, %{"id" => room_id} = params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> String.to_integer()
      |> min(200)
      |> max(1)

    case NNTPSBackend.fetch_recent(room_id, limit) do
      {:ok, articles} ->
        messages = Enum.map(articles, &format_article/1)
        json(conn, %{messages: messages})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  Post a new message to a room.

  ## Request body

  ```json
  {
    "body": "Hello world",
    "reply_to": "<optional_message_id>"  // optional, for threading
  }
  ```

  ## Response

  Returns the created message (same format as index).
  """
  def create(conn, %{"id" => room_id} = params) do
    user_id = conn.assigns[:user_id]
    display_name = conn.assigns[:display_name] || "Unknown"

    body = Map.get(params, "body", "")
    reply_to = Map.get(params, "reply_to")

    # Validate message body.
    cond do
      byte_size(body) == 0 ->
        conn
        |> put_status(400)
        |> json(%{error: "Message body cannot be empty"})

      byte_size(body) > 2000 ->
        conn
        |> put_status(400)
        |> json(%{error: "Message body exceeds 2000 byte limit"})

      true ->
        # Build options for NNTPS post.
        opts =
          if reply_to do
            [reply_to: reply_to]
          else
            []
          end

        case NNTPSBackend.post_message(room_id, user_id, display_name, body, opts) do
          {:ok, article} ->
            conn
            |> put_status(201)
            |> json(format_article(article))

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: inspect(reason)})
        end
    end
  end

  # ── Private helpers ──

  # Format an NNTPS article into a JSON-friendly message map.
  @doc false
  defp format_article(article) do
    # Extract display name from "Name <user_id@burble.local>" format.
    {display_name, user_id} = parse_from_header(article.from)

    %{
      message_id: article.message_id,
      body: article.body,
      display_name: display_name,
      user_id: user_id,
      sent_at: DateTime.to_iso8601(article.date),
      references: article.references || [],
      is_pinned: Map.get(article, :pinned, false)
    }
  end

  # Parse "Display Name <user_id@burble.local>" into {display_name, user_id}.
  @doc false
  defp parse_from_header(from) do
    case Regex.run(~r/^(.+?)\s*<(.+?)@/, from) do
      [_, name, uid] -> {String.trim(name), uid}
      _ -> {from, "unknown"}
    end
  end
end
