# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule Burble.LLM.AnthropicProvider do
  @moduledoc """
  Anthropic Claude API provider for Burble's LLM service.

  Calls the Claude Messages API via Erlang's built-in :httpc (no extra deps).
  Reads ANTHROPIC_API_KEY from environment. Falls back gracefully when unconfigured.

  Includes a circuit breaker: after `@failure_threshold` consecutive failures the
  circuit opens for `@open_duration_ms`, rejecting calls immediately. A single
  probe is allowed after the open period (half-open); success closes the circuit.
  """

  require Logger

  @api_url ~c"https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @default_model "claude-sonnet-4-6"
  @default_max_tokens 4096
  @request_timeout 60_000

  # Circuit breaker config
  @failure_threshold 5
  @open_duration_ms 30_000
  @cb_table :burble_llm_circuit_breaker

  defp ensure_httpc do
    :inets.start()
    :ssl.start()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Circuit breaker (ETS-based, no GenServer needed)
  # ---------------------------------------------------------------------------

  defp ensure_cb_table do
    case :ets.info(@cb_table) do
      :undefined -> :ets.new(@cb_table, [:set, :public, :named_table]); :ok
      _ -> :ok
    end
  end

  defp circuit_state do
    ensure_cb_table()
    failures = case :ets.lookup(@cb_table, :failures) do
      [{_, n}] -> n
      [] -> 0
    end
    opened_at = case :ets.lookup(@cb_table, :opened_at) do
      [{_, t}] -> t
      [] -> nil
    end
    {failures, opened_at}
  end

  defp record_success do
    ensure_cb_table()
    :ets.insert(@cb_table, {:failures, 0})
    :ets.delete(@cb_table, :opened_at)
  end

  defp record_failure do
    ensure_cb_table()
    new_count = case :ets.lookup(@cb_table, :failures) do
      [{_, n}] -> n + 1
      [] -> 1
    end
    :ets.insert(@cb_table, {:failures, new_count})
    if new_count >= @failure_threshold do
      :ets.insert(@cb_table, {:opened_at, System.monotonic_time(:millisecond)})
      Logger.error("[LLM/CB] Circuit OPEN after #{new_count} consecutive failures")
    end
  end

  defp check_circuit do
    case circuit_state() do
      {failures, nil} when failures < @failure_threshold -> :closed
      {_, opened_at} when is_integer(opened_at) ->
        elapsed = System.monotonic_time(:millisecond) - opened_at
        if elapsed >= @open_duration_ms, do: :half_open, else: :open
      _ -> :closed
    end
  end

  defp with_circuit_breaker(fun) do
    case check_circuit() do
      :open ->
        {:error, :circuit_open}
      state when state in [:closed, :half_open] ->
        case fun.() do
          {:ok, _} = ok ->
            record_success()
            ok
          :ok ->
            record_success()
            :ok
          {:error, _} = err ->
            record_failure()
            err
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def process_query(user_id, prompt) do
    ensure_httpc()

    case api_key() do
      nil -> {:error, :api_key_not_configured}
      key -> with_circuit_breaker(fn -> do_query(user_id, prompt, key) end)
    end
  end

  def stream_query(user_id, prompt, callback) do
    ensure_httpc()

    case api_key() do
      nil -> {:error, :api_key_not_configured}
      key -> with_circuit_breaker(fn -> do_stream(user_id, prompt, callback, key) end)
    end
  end

  @doc "Current circuit breaker state: `:closed`, `:half_open`, or `:open`."
  def circuit_breaker_status, do: check_circuit()

  @doc "Manually reset the circuit breaker (e.g. after fixing an outage)."
  def reset_circuit_breaker, do: record_success()

  # ---------------------------------------------------------------------------
  # HTTP calls
  # ---------------------------------------------------------------------------

  defp do_query(user_id, prompt, key) do
    body = Jason.encode!(%{
      model: model(),
      max_tokens: max_tokens(),
      messages: [%{role: "user", content: prompt}],
      system: system_prompt(user_id)
    })

    request = {@api_url, auth_headers(key), ~c"application/json", String.to_charlist(body)}

    case :httpc.request(:post, request, [timeout: @request_timeout, ssl: ssl_opts()], []) do
      {:ok, {{_, 200, _}, _resp_headers, resp_body}} ->
        parse_response(List.to_string(resp_body))

      {:ok, {{_, status, _}, _resp_headers, resp_body}} ->
        Logger.warning("[LLM/Anthropic] API returned #{status}: #{List.to_string(resp_body)}")
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("[LLM/Anthropic] HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp do_stream(user_id, prompt, callback, key) do
    body = Jason.encode!(%{
      model: model(),
      max_tokens: max_tokens(),
      stream: true,
      messages: [%{role: "user", content: prompt}],
      system: system_prompt(user_id)
    })

    request = {@api_url, auth_headers(key), ~c"application/json", String.to_charlist(body)}

    case :httpc.request(:post, request, [timeout: @request_timeout, ssl: ssl_opts()], []) do
      {:ok, {{_, 200, _}, _resp_headers, resp_body}} ->
        parse_sse_stream(List.to_string(resp_body), callback)

      {:ok, {{_, status, _}, _resp_headers, resp_body}} ->
        Logger.warning("[LLM/Anthropic] Stream API returned #{status}")
        {:error, {:api_error, status, List.to_string(resp_body)}}

      {:error, reason} ->
        Logger.error("[LLM/Anthropic] Stream HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp auth_headers(key) do
    [
      {~c"content-type", ~c"application/json"},
      {~c"x-api-key", String.to_charlist(key)},
      {~c"anthropic-version", String.to_charlist(@api_version)}
    ]
  end

  # ---------------------------------------------------------------------------
  # Response parsing
  # ---------------------------------------------------------------------------

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"content" => [%{"text" => text} | _]}} ->
        {:ok, text}

      {:ok, %{"error" => %{"message" => msg}}} ->
        {:error, {:api_error, msg}}

      {:ok, other} ->
        Logger.warning("[LLM/Anthropic] Unexpected response shape: #{inspect(other)}")
        {:error, :unexpected_response}

      {:error, _} ->
        {:error, :json_decode_error}
    end
  end

  defp parse_sse_stream(body, callback) do
    body
    |> String.split("\n")
    |> Enum.each(fn line ->
      case line do
        "data: " <> json_str ->
          case Jason.decode(json_str) do
            {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
              callback.(text)
            _ ->
              :ok
          end
        _ ->
          :ok
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Config helpers
  # ---------------------------------------------------------------------------

  defp api_key, do: System.get_env("ANTHROPIC_API_KEY")
  defp model, do: System.get_env("ANTHROPIC_MODEL") || @default_model

  defp max_tokens do
    case System.get_env("ANTHROPIC_MAX_TOKENS") do
      nil -> @default_max_tokens
      val -> String.to_integer(val)
    end
  end

  defp system_prompt(user_id) do
    "You are a helpful AI assistant integrated into Burble, a P2P voice and collaboration platform. " <>
    "You are responding to user #{user_id}. Be concise, technical when appropriate, and helpful. " <>
    "If the user asks about Burble features, you can mention voice chat, AI bridge, E2EE, and WebRTC."
  end

  defp ssl_opts do
    [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3]
  end
end
