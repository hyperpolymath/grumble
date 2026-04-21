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

      # In-memory chat message store (ETS-backed, per-room, ephemeral)
      Burble.Chat.MessageStore,

      # Text channels (NNTPS-backed persistent threaded messages)
      Burble.Text.NNTPSBackend,

      # Media plane — Membrane SFU (WebRTC audio routing)
      Burble.Media.Engine,

      # Telemetry
      Burble.Telemetry,

      # E2EE key rotation scheduler (rotates per-room keys for forward secrecy)
      Burble.Security.KeyRotation,

      # PTP precision timing (clock synchronisation for multi-node playout)
      Burble.Timing.PTP,

      # RTP↔wall-clock correlator — receives sync points from every inbound RTP
      # packet, maintains a 64-point sliding window, and provides rtp_to_wall /
      # wall_to_rtp conversion + PPM drift estimation for Phase 4 playout alignment.
      {Burble.Timing.ClockCorrelator, [name: Burble.Timing.ClockCorrelator, clock_rate: 48_000]},

      # Groove discovery endpoint (message queue for Gossamer/PanLL/etc.)
      # Serves GET /.well-known/groove with Burble capability manifest.
      # Groove connectors verified via Idris2 dependent types (Groove.idr).
      Burble.Groove,

      # Groove health mesh — probes peers every 30s, builds mesh status view.
      # Serves GET /.well-known/groove/mesh for inter-service health monitoring.
      Burble.Groove.HealthMesh,

      # Groove feedback store — receives feedback routed via the groove mesh.
      # Serves POST /.well-known/groove/feedback for feedback-o-tron integration.
      Burble.Groove.Feedback,

      # Blockchain anchoring bridge for Vext chains.
      Burble.Verification.Anchor,

      # LLM service — QUIC+TLS on 8503, TCP+TLS fallback on 8085
      # Provides real-time LLM query processing with streaming responses
      {Burble.LLM.Supervisor, [port: 8503, fallback_port: 8085]},

      # LMDB playout buffer registry (individual buffers started per-room via DynamicSupervisor)
      # Note: LMDBPlayout instances are started dynamically per room, not here.
      # The RoomSupervisor above handles their lifecycle.

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

  @doc """
  Health check for container HEALTHCHECK and monitoring.

  Verifies the supervision tree is running and VeriSimDB is reachable.
  Called via `bin/burble rpc "Burble.Application.health_check()"` from
  the Containerfile HEALTHCHECK directive.

  Returns `:ok` if healthy, raises on failure (non-zero exit for container).
  """
  @spec health_check() :: :ok
  def health_check do
    # Check that the supervision tree is alive.
    case Process.whereis(Burble.Supervisor) do
      nil -> raise "Burble.Supervisor is not running"
      _pid -> :ok
    end

    # Check VeriSimDB connectivity.
    case Burble.Store.health() do
      {:ok, true} -> :ok
      {:ok, false} -> raise "VeriSimDB reports unhealthy"
      {:error, reason} -> raise "VeriSimDB health check failed: #{inspect(reason)}"
    end
  end
end
