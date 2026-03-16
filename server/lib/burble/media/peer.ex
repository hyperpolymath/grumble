# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Media.Peer — Per-peer WebRTC PeerConnection manager.
#
# Each participant in a voice room gets their own Peer GenServer that
# owns an ExWebRTC.PeerConnection. The Peer:
#
#   1. Creates a recvonly audio transceiver (receives the peer's mic)
#   2. Creates sendonly audio transceivers (one per other peer in the room)
#   3. Forwards received RTP packets to all other peers' sendonly tracks
#   4. Manages SDP offer/answer negotiation (server is always the offerer)
#   5. Handles ICE candidate exchange
#
# Architecture:
#   Browser <-> RoomChannel <-> Peer GenServer <-> ExWebRTC.PeerConnection
#
# The server always initiates offers. When a new peer joins, ALL existing
# peers renegotiate (add a new sendonly track for the newcomer).

defmodule Burble.Media.Peer do
  @moduledoc """
  Per-peer WebRTC PeerConnection for audio SFU.

  Each peer gets one PeerConnection with:
  - 1 recvonly audio transceiver (their microphone)
  - N-1 sendonly audio transceivers (one per other peer in the room)

  RTP packets from each peer are forwarded to all other peers' sendonly tracks.
  """

  use GenServer
  require Logger

  alias ExWebRTC.{PeerConnection, MediaStreamTrack, RTPCodecParameters, SessionDescription, ICECandidate}

  @audio_codecs [
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]

  @ice_servers [%{urls: "stun:stun.l.google.com:19302"}]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc "Start a peer process for a participant."
  def start_link(opts) do
    peer_id = Keyword.fetch!(opts, :peer_id)
    GenServer.start_link(__MODULE__, opts, name: via(peer_id))
  end

  @doc "Apply an SDP answer from the client."
  def apply_sdp_answer(peer_id, answer_sdp) do
    GenServer.call(via(peer_id), {:sdp_answer, answer_sdp})
  end

  @doc "Add an ICE candidate from the client."
  def add_ice_candidate(peer_id, candidate_json) do
    GenServer.call(via(peer_id), {:ice_candidate, candidate_json})
  end

  @doc "Notify this peer that a new peer has joined the room."
  def peer_added(peer_id, new_peer_id) do
    GenServer.cast(via(peer_id), {:peer_added, new_peer_id})
  end

  @doc "Notify this peer that a peer has left the room."
  def peer_removed(peer_id, removed_peer_id) do
    GenServer.cast(via(peer_id), {:peer_removed, removed_peer_id})
  end

  @doc "Forward an RTP packet to this peer's sendonly track for a specific source peer."
  def forward_rtp(peer_id, from_peer_id, packet) do
    GenServer.cast(via(peer_id), {:forward_rtp, from_peer_id, packet})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    peer_id = Keyword.fetch!(opts, :peer_id)
    room_id = Keyword.fetch!(opts, :room_id)
    channel_pid = Keyword.fetch!(opts, :channel_pid)
    existing_peers = Keyword.get(opts, :existing_peers, [])

    ice_servers = Keyword.get(opts, :ice_servers, @ice_servers)

    # Create PeerConnection.
    {:ok, pc} = PeerConnection.start_link(
      ice_servers: ice_servers,
      audio_codecs: @audio_codecs,
      video_codecs: []
    )

    # Recvonly transceiver — receives this peer's microphone audio.
    {:ok, recv_tr} = PeerConnection.add_transceiver(pc, :audio, direction: :recvonly)

    # Sendonly transceivers — one per existing peer (to forward their audio to this peer).
    outbound_tracks =
      Map.new(existing_peers, fn existing_id ->
        {track, tr_id} = add_sendonly_track(pc)
        {existing_id, %{track_id: track.id, transceiver_id: tr_id}}
      end)

    state = %{
      peer_id: peer_id,
      room_id: room_id,
      channel_pid: channel_pid,
      pc: pc,
      recv_transceiver: recv_tr,
      recv_track_id: nil,
      outbound_tracks: outbound_tracks,
      pending_peers: [],
      negotiating: false
    }

    # Generate initial offer.
    send(self(), :send_offer)

    Logger.info("[Peer] Started for #{peer_id} in room #{room_id} (#{length(existing_peers)} existing peers)")
    {:ok, state}
  end

  @impl true
  def handle_info(:send_offer, state) do
    state = send_offer(state)
    {:noreply, state}
  end

  # ExWebRTC messages from the PeerConnection process.

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{pc: pc} = state) do
    # Forward ICE candidate to client via channel.
    json = candidate |> ICECandidate.to_json() |> Jason.encode!()
    send(state.channel_pid, {:peer_ice_candidate, json})
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, %{pc: pc} = state) do
    Logger.info("[Peer] #{state.peer_id} WebRTC connected")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, new_state}}, %{pc: pc} = state) do
    Logger.debug("[Peer] #{state.peer_id} connection state: #{new_state}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:track, track}}, %{pc: pc} = state) do
    # Remote track added — this is the peer's audio input.
    Logger.info("[Peer] #{state.peer_id} remote track: #{track.id}")
    {:noreply, %{state | recv_track_id: track.id}}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:rtp, track_id, _rid, packet}}, %{pc: pc} = state) do
    # Received RTP from this peer — forward to all other peers in the room.
    if track_id == state.recv_track_id do
      # Tell the Engine to distribute this packet.
      Burble.Media.Engine.distribute_rtp(state.room_id, state.peer_id, packet)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, _msg}, state) do
    # Catch-all for unhandled PeerConnection messages.
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # SDP answer from client
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call({:sdp_answer, answer_sdp}, _from, %{pc: pc} = state) do
    answer = %SessionDescription{type: :answer, sdp: answer_sdp}

    case PeerConnection.set_remote_description(pc, answer) do
      :ok ->
        # Process any peers that joined while we were negotiating.
        state = %{state | negotiating: false}
        state = process_pending_peers(state)
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("[Peer] #{state.peer_id} SDP answer failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # ICE candidate from client
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call({:ice_candidate, candidate_json}, _from, %{pc: pc} = state) do
    case Jason.decode(candidate_json) do
      {:ok, decoded} ->
        candidate = ICECandidate.from_json(decoded)

        case PeerConnection.add_ice_candidate(pc, candidate) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, _} ->
        {:reply, {:error, :invalid_json}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Peer added/removed
  # ---------------------------------------------------------------------------

  @impl true
  def handle_cast({:peer_added, new_peer_id}, state) do
    if state.negotiating do
      # Queue — can't renegotiate while waiting for SDP answer.
      {:noreply, %{state | pending_peers: state.pending_peers ++ [new_peer_id]}}
    else
      state = add_outbound_peer(state, new_peer_id)
      state = send_offer(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:peer_removed, removed_peer_id}, state) do
    state = remove_outbound_peer(state, removed_peer_id)

    unless state.negotiating do
      state = send_offer(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # RTP forwarding
  # ---------------------------------------------------------------------------

  @impl true
  def handle_cast({:forward_rtp, from_peer_id, packet}, %{pc: pc} = state) do
    case Map.get(state.outbound_tracks, from_peer_id) do
      %{track_id: track_id} ->
        PeerConnection.send_rtp(pc, track_id, packet)

      nil ->
        :ok
    end

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp via(peer_id) do
    {:via, Registry, {Burble.PeerRegistry, peer_id}}
  end

  defp add_sendonly_track(pc) do
    stream_id = MediaStreamTrack.generate_stream_id()
    track = MediaStreamTrack.new(:audio, [stream_id])
    {:ok, tr} = PeerConnection.add_transceiver(pc, track, direction: :sendonly)
    {track, tr.id}
  end

  defp add_outbound_peer(state, new_peer_id) do
    {track, tr_id} = add_sendonly_track(state.pc)
    outbound = Map.put(state.outbound_tracks, new_peer_id, %{track_id: track.id, transceiver_id: tr_id})
    %{state | outbound_tracks: outbound}
  end

  defp remove_outbound_peer(state, removed_peer_id) do
    case Map.pop(state.outbound_tracks, removed_peer_id) do
      {%{transceiver_id: tr_id}, remaining} ->
        PeerConnection.stop_transceiver(state.pc, tr_id)
        %{state | outbound_tracks: remaining}

      {nil, _} ->
        state
    end
  end

  defp send_offer(%{pc: pc} = state) do
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    # Send offer to client via channel.
    send(state.channel_pid, {:peer_sdp_offer, offer.sdp})

    %{state | negotiating: true}
  end

  defp process_pending_peers(%{pending_peers: []} = state), do: state
  defp process_pending_peers(%{pending_peers: [next | rest]} = state) do
    state = %{state | pending_peers: rest}
    state = add_outbound_peer(state, next)
    send_offer(state)
  end
end
