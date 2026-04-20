# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule Burble.LLM do
  @moduledoc """
  Core LLM processing service for Burble.
  """

  require Logger

  @doc """
  Process a synchronous LLM query.
  """
  def process_query(user_id, prompt) do
    Logger.debug("[LLM] Processing query for #{user_id}: #{prompt}")
    # In reality, this would route to a worker pool or remote API.
    if String.contains?(prompt, "trigger_error") do
      {:error, :simulated_error}
    else
      {:ok, "This is a simulated response to: #{prompt}"}
    end
  end

  @doc """
  Stream an LLM query response.
  """
  def stream_query(user_id, prompt, callback) do
    Logger.debug("[LLM] Streaming query for #{user_id}: #{prompt}")
    # Simulate streaming
    callback.("Simulated ")
    callback.("stream ")
    callback.("response.")
    :ok
  end
end

defmodule Burble.LLM.Registry do
  @moduledoc """
  Registry for LLM connections.
  """

  def register_connection(user_id, pid) do
    :persistent_term.put({__MODULE__, user_id}, pid)
    :ok
  end

  def lookup_connection(user_id) do
    case :persistent_term.get({__MODULE__, user_id}, nil) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end
end
