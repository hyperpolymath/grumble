# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Application — OTP supervision tree root.
#
# Starts the core services in dependency order:
#   1. Persistent store (VeriSimDB via Burble.Store)
#   2. PubSub (Phoenix.PubSub for room events)
#   3. Presence tracker (who's in which room)
#   4. Room registry (named process per active room)
#   5. Telemetry supervisor (metrics + periodic polling)
#   6. Web endpoint (Phoenix, WebSocket signaling)

defmodule Burble.Application do
  @moduledoc """
  OTP Application for Burble voice server.

  The supervision tree is structured so that:
  - VeriSimDB store failures don't crash the web endpoint
  - Room processes are isolated (one room crash doesn't affect others)
  - Telemetry is always running for observability
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Persistent store (VeriSimDB)
      Burble.Store,

      # PubSub for real-time events (room join/leave, voice state changes)
      {Phoenix.PubSub, name: Burble.PubSub},

      # Presence tracking (who's in which room, voice state)
      Burble.Presence,

      # Room supervisor — DynamicSupervisor for room processes
      {DynamicSupervisor, name: Burble.RoomSupervisor, strategy: :one_for_one},

      # Room registry — maps room IDs to PIDs
      {Registry, keys: :unique, name: Burble.RoomRegistry},

      # WebRTC peer registry — maps peer IDs to Peer GenServer PIDs
      {Registry, keys: :unique, name: Burble.PeerRegistry},

      # WebRTC peer supervisor — one Peer GenServer per active participant
      {DynamicSupervisor, name: Burble.PeerSupervisor, strategy: :one_for_one},

      # Coprocessor pipeline registry — maps peer IDs to pipeline PIDs
      {Registry, keys: :unique, name: Burble.CoprocessorRegistry},

      # Coprocessor pipeline supervisor — one pipeline per active peer
      {DynamicSupervisor, name: Burble.CoprocessorSupervisor, strategy: :one_for_one},

      # Text channels (NNTPS-backed persistent threaded messages)
      Burble.Text.NNTPSBackend,

      # Media plane — Membrane SFU (WebRTC audio routing)
      Burble.Media.Engine,

      # Telemetry
      Burble.Telemetry,

      # Web endpoint (must be last — depends on PubSub and Presence)
      BurbleWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Burble.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BurbleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
