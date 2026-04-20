# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule Burble.LLM.Supervisor do
  @moduledoc """
  LLM service supervisor.
  
  Manages the LLM transport listeners and worker pools.
  """
  
  use Supervisor
  
  @transport_workers 10
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    children = [
      # Start transport manager/GenServer
      {Burble.LLM.Transport, opts},
      
      # Worker pool for LLM processing (using NimblePool)
      {NimblePool, [
        worker: {Burble.LLM.Worker, []},
        pool_size: @transport_workers,
        name: :llm_worker_pool
      ]}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Get available transport.
  """
  def get_transport do
    case Supervisor.which_children(__MODULE__) do
      children when is_list(children) ->
        Enum.find_value(children, {:error, :transport_not_running}, fn
          {Burble.LLM.Transport, pid, :worker, _modules} when is_pid(pid) ->
            {:ok, pid}
          _ -> nil
        end)
      _ ->
        {:error, :transport_not_running}
    end
  end
end
