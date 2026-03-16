# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Media.Engine — Membrane-based SFU media engine.
#
# The media plane is isolated from the control plane. This module
# orchestrates Membrane RTC Engine instances — one per active voice room.
#
# Architecture:
#   Control plane (rooms, auth, permissions) runs in the main OTP app.
#   Media plane (audio routing, mixing, recording) runs here.
#   They communicate via PubSub events, not direct calls.
#
# Privacy layers (applied in order):
#   Layer 0: SFU — peers never connect directly, only to server
#   Layer 1: TURN-only — no ICE host/srflx candidates, IP hidden
#   Layer 2: E2EE — Insertable Streams, server forwards opaque frames
#   Layer 3: WebTransport — QUIC upgrade when supported (future)
#   Layer 4: MoQ — Media over QUIC migration (future, when spec stabilises)
#
# Codec: Opus (mandatory), 48kHz, mono for voice, stereo for music mode.
# Bitrate: 24-64 kbps adaptive (voice), 96-128 kbps (music mode).

defmodule Burble.Media.Engine do
  @moduledoc """
  Membrane-based Selective Forwarding Unit (SFU) for Burble.

  Manages one RTC Engine instance per active voice room.
  All audio is forwarded (not mixed) to preserve E2EE capability.

  ## SFU vs MCU

  We use SFU (Selective Forwarding Unit), not MCU (Multipoint Control Unit):
  - SFU forwards encrypted packets without decoding — enables E2EE
  - MCU would need to decode, mix, re-encode — breaks E2EE
  - SFU scales better (no server-side transcoding)
  - Trade-off: clients do N-1 decodes instead of 1, but modern devices handle this easily for voice
  """

  use GenServer

  require Logger

  # ── Types ──

  @type room_id :: String.t()
  @type peer_id :: String.t()

  @type media_config :: %{
          codec: :opus,
          sample_rate: 48_000,
          channels: 1 | 2,
          bitrate_kbps: 24..128,
          dtx: boolean(),
          fec: boolean()
        }

  @type privacy_mode :: :standard | :turn_only | :e2ee | :maximum

  # ── Client API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a media session for a room.

  Starts a Membrane RTC Engine instance that handles WebRTC
  connections for all participants in the room.
  """
  def create_room_session(room_id, opts \\ []) do
    GenServer.call(__MODULE__, {:create_session, room_id, opts})
  end

  @doc """
  Destroy a media session when a room closes.
  """
  def destroy_room_session(room_id) do
    GenServer.call(__MODULE__, {:destroy_session, room_id})
  end

  @doc """
  Add a peer to a room's media session.

  Returns WebRTC signaling data (SDP offer) for the client.
  The offer is privacy-hardened based on the room's privacy mode.
  """
  def add_peer(room_id, peer_id, opts \\ []) do
    GenServer.call(__MODULE__, {:add_peer, room_id, peer_id, opts})
  end

  @doc """
  Remove a peer from a room's media session.
  """
  def remove_peer(room_id, peer_id) do
    GenServer.call(__MODULE__, {:remove_peer, room_id, peer_id})
  end

  @doc """
  Handle an incoming WebRTC signaling message (SDP answer, ICE candidate).
  """
  def handle_signal(room_id, peer_id, signal) do
    GenServer.call(__MODULE__, {:signal, room_id, peer_id, signal})
  end

  @doc """
  Set per-peer audio properties (mute relay, volume scaling).
  """
  def set_peer_audio(room_id, peer_id, audio_opts) do
    GenServer.call(__MODULE__, {:set_audio, room_id, peer_id, audio_opts})
  end

  @doc """
  Get media health metrics for a room.
  """
  def get_room_health(room_id) do
    GenServer.call(__MODULE__, {:health, room_id})
  end

  # ── Server Callbacks ──

  @impl true
  def init(_opts) do
    state = %{
      # room_id => %{engine_pid, peers, config, privacy_mode}
      sessions: %{},
      # Global media config defaults
      default_config: default_media_config(),
      # Privacy mode (can be overridden per room)
      default_privacy: :turn_only
    }

    Logger.info("[Burble.Media.Engine] Started — SFU mode, TURN-only default")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, room_id, opts}, _from, state) do
    if Map.has_key?(state.sessions, room_id) do
      {:reply, {:error, :session_exists}, state}
    else
      privacy_mode = Keyword.get(opts, :privacy, state.default_privacy)
      config = Keyword.get(opts, :config, state.default_config)

      session = %{
        room_id: room_id,
        peers: %{},
        config: config,
        privacy_mode: privacy_mode,
        created_at: DateTime.utc_now(),
        # Membrane RTC Engine PID would go here in production
        engine_pid: nil
      }

      new_sessions = Map.put(state.sessions, room_id, session)
      Logger.info("[Media] Session created: #{room_id} (privacy: #{privacy_mode})")

      {:reply, {:ok, room_id}, %{state | sessions: new_sessions}}
    end
  end

  @impl true
  def handle_call({:destroy_session, room_id}, _from, state) do
    case Map.pop(state.sessions, room_id) do
      {nil, _} ->
        {:reply, {:error, :no_session}, state}

      {session, remaining} ->
        # Terminate Membrane engine
        if session.engine_pid, do: GenServer.stop(session.engine_pid, :normal)
        Logger.info("[Media] Session destroyed: #{room_id}")
        {:reply, :ok, %{state | sessions: remaining}}
    end
  end

  @impl true
  def handle_call({:add_peer, room_id, peer_id, opts}, _from, state) do
    case Map.get(state.sessions, room_id) do
      nil ->
        {:reply, {:error, :no_session}, state}

      session ->
        e2ee_enabled = session.privacy_mode in [:e2ee, :maximum]
        e2ee_key = if e2ee_enabled, do: Keyword.get(opts, :e2ee_key), else: nil

        peer = %{
          id: peer_id,
          joined_at: DateTime.utc_now(),
          muted: Keyword.get(opts, :muted, false),
          e2ee_enabled: e2ee_enabled
        }

        # Start a coprocessor pipeline for this peer.
        pipeline_opts = [
          peer_id: peer_id,
          e2ee_key: e2ee_key,
          config: %{
            sample_rate: session.config.sample_rate,
            channels: session.config.channels,
            bitrate: session.config.bitrate_kbps * 1000,
            noise_gate_db: -40.0,
            echo_cancel_taps: 128,
            e2ee_enabled: e2ee_enabled,
            neural_denoise: true
          }
        ]

        case DynamicSupervisor.start_child(
               Burble.CoprocessorSupervisor,
               {Burble.Coprocessor.Pipeline, pipeline_opts}
             ) do
          {:ok, _pid} ->
            Logger.info("[Media] Pipeline started for peer #{peer_id}")

          {:error, reason} ->
            Logger.warning("[Media] Pipeline failed for peer #{peer_id}: #{inspect(reason)}")
        end

        updated_session = %{session | peers: Map.put(session.peers, peer_id, peer)}
        new_sessions = Map.put(state.sessions, room_id, updated_session)

        # Generate privacy-hardened SDP offer
        offer = generate_offer(session.privacy_mode, session.config)

        Logger.info("[Media] Peer added: #{peer_id} → #{room_id}")
        {:reply, {:ok, offer}, %{state | sessions: new_sessions}}
    end
  end

  @impl true
  def handle_call({:remove_peer, room_id, peer_id}, _from, state) do
    case Map.get(state.sessions, room_id) do
      nil ->
        {:reply, {:error, :no_session}, state}

      session ->
        # Stop the coprocessor pipeline for this peer.
        case Registry.lookup(Burble.CoprocessorRegistry, peer_id) do
          [{pid, _}] -> Burble.Coprocessor.Pipeline.stop(pid)
          _ -> :ok
        end

        updated_session = %{session | peers: Map.delete(session.peers, peer_id)}
        new_sessions = Map.put(state.sessions, room_id, updated_session)
        Logger.info("[Media] Peer removed: #{peer_id} ← #{room_id}")
        {:reply, :ok, %{state | sessions: new_sessions}}
    end
  end

  @impl true
  def handle_call({:signal, _room_id, _peer_id, _signal}, _from, state) do
    # TODO: Forward to Membrane RTC Engine for WebRTC negotiation
    {:reply, {:ok, :forwarded}, state}
  end

  @impl true
  def handle_call({:set_audio, room_id, peer_id, audio_opts}, _from, state) do
    case get_in(state, [:sessions, room_id, :peers, peer_id]) do
      nil ->
        {:reply, {:error, :peer_not_found}, state}

      peer ->
        updated_peer = Map.merge(peer, Map.new(audio_opts))

        new_state =
          put_in(state, [:sessions, room_id, :peers, peer_id], updated_peer)

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:health, room_id}, _from, state) do
    case Map.get(state.sessions, room_id) do
      nil ->
        {:reply, {:error, :no_session}, state}

      session ->
        health = %{
          room_id: room_id,
          peer_count: map_size(session.peers),
          privacy_mode: session.privacy_mode,
          uptime_seconds: DateTime.diff(DateTime.utc_now(), session.created_at),
          codec: session.config.codec,
          bitrate: session.config.bitrate_kbps
        }

        {:reply, {:ok, health}, state}
    end
  end

  # ── Private ──

  defp default_media_config do
    %{
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      bitrate_kbps: 32,
      dtx: true,
      fec: true
    }
  end

  @doc false
  def generate_offer(privacy_mode, config) do
    # In production, this creates a real SDP offer via Membrane/ex_webrtc.
    # Privacy hardening is applied based on mode:
    %{
      type: "offer",
      privacy_mode: privacy_mode,
      codec: config.codec,
      ice_policy: ice_policy(privacy_mode),
      e2ee: privacy_mode in [:e2ee, :maximum],
      # Placeholder — real SDP generated by Membrane
      sdp: nil
    }
  end

  defp ice_policy(:standard), do: :all
  defp ice_policy(:turn_only), do: :relay
  defp ice_policy(:e2ee), do: :relay
  defp ice_policy(:maximum), do: :relay
end
