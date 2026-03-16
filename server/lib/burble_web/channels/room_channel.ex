# SPDX-License-Identifier: PMPL-1.0-or-later
#
# BurbleWeb.RoomChannel — WebSocket channel for voice room signaling.
#
# Handles:
#   - Room join/leave lifecycle (with Avow consent attestation)
#   - Voice state changes (mute, deafen, priority)
#   - WebRTC signaling (offer/answer/ICE candidate exchange)
#   - Presence tracking (who's in the room)
#   - Text messages (stored via NNTPSBackend)
#   - Permission enforcement via Burble.Permissions
#
# This is the signaling plane — actual audio flows via WebRTC peer
# connections negotiated through this channel.

defmodule BurbleWeb.RoomChannel do
  @moduledoc """
  Phoenix Channel for voice room signaling.

  ## Topics

  Clients join `"room:<room_id>"` to participate in a voice room.

  ## Incoming events

  - `"voice_state"` — update own voice state (mute/deafen/etc.)
  - `"signal"` — WebRTC signaling (offer, answer, ice_candidate)
  - `"text"` — send a text message in the room
  - `"whisper"` — direct audio to a specific user

  ## Outgoing events

  - `"presence_state"` — initial presence snapshot
  - `"presence_diff"` — presence changes (join/leave)
  - `"voice_state_changed"` — another user's voice state changed
  - `"signal"` — WebRTC signaling from another peer
  - `"text"` — text message from another user
  - `"room_state"` — full room state update
  """

  use Phoenix.Channel

  alias Burble.Presence
  alias Burble.Rooms.RoomManager
  alias Burble.Permissions
  alias Burble.Verification.Avow
  alias Burble.Audit

  @impl true
  def join("room:" <> room_id, params, socket) do
    user_id = socket.assigns[:user_id]
    display_name = Map.get(params, "display_name", socket.assigns[:display_name] || "Guest")

    # Check join permission.
    role_perms = get_user_permissions(socket)

    if not Permissions.has_permission?(role_perms, :join_room) do
      {:error, %{reason: "insufficient_permissions"}}
    else
      case RoomManager.join(room_id, user_id, %{display_name: display_name}) do
        {:ok, room_state} ->
          # Avow consent attestation for the join.
          Avow.attest_join(user_id, room_id, :direct_join)

          # Start WebRTC peer via Media.Engine (passes self() as channel_pid
          # so the Peer GenServer can send SDP offers and ICE candidates back).
          Burble.Media.Engine.add_peer(room_id, user_id, channel_pid: self())

          # Audit log.
          Audit.log(:room_join, user_id, %{room_id: room_id})

          send(self(), :after_join)

          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:display_name, display_name)

          {:ok, room_state, socket}

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end
  end

  # Messages from the Peer GenServer — relay to client.
  @impl true
  def handle_info({:peer_sdp_offer, sdp}, socket) do
    push(socket, "sdp_offer", %{body: sdp})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:peer_ice_candidate, candidate_json}, socket) do
    push(socket, "ice_candidate", %{body: candidate_json})
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track presence with voice state metadata.
    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        display_name: socket.assigns.display_name,
        voice_state: "connected",
        joined_at: System.system_time(:second)
      })

    # Push current presence state to the joining user.
    push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  # ── Voice state ──

  @impl true
  def handle_in("voice_state", %{"state" => state}, socket)
      when state in ["connected", "muted", "deafened"] do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id

    # Check speak permission for unmuting.
    role_perms = get_user_permissions(socket)

    if state == "connected" and not Permissions.has_permission?(role_perms, :speak) do
      {:reply, {:error, %{reason: "no_speak_permission"}}, socket}
    else
      state_atom = String.to_existing_atom(state)
      Burble.Rooms.Room.set_voice_state(room_id, user_id, state_atom)

      # Update presence metadata.
      Presence.update(socket, user_id, fn meta ->
        Map.put(meta, :voice_state, state)
      end)

      broadcast!(socket, "voice_state_changed", %{
        user_id: user_id,
        voice_state: state
      })

      {:noreply, socket}
    end
  end

  # ── WebRTC signaling (server-mediated SFU) ──

  @impl true
  def handle_in("sdp_answer", %{"body" => body}, socket) do
    # Client sends SDP answer in response to server's offer.
    peer_id = socket.assigns.user_id
    Burble.Media.Peer.apply_sdp_answer(peer_id, body)
    {:noreply, socket}
  end

  @impl true
  def handle_in("ice_candidate", %{"body" => body}, socket) do
    # Client sends ICE candidate.
    peer_id = socket.assigns.user_id
    Burble.Media.Peer.add_ice_candidate(peer_id, body)
    {:noreply, socket}
  end

  # Legacy P2P signaling (kept for fallback/serverless mode).
  @impl true
  def handle_in("signal", %{"to" => target_id, "type" => type, "payload" => payload}, socket) do
    broadcast!(socket, "signal", %{
      from: socket.assigns.user_id,
      to: target_id,
      type: type,
      payload: payload
    })

    {:noreply, socket}
  end

  # ── Text messages (stored via NNTPSBackend) ──

  @impl true
  def handle_in("text", %{"body" => body}, socket)
      when byte_size(body) > 0 and byte_size(body) <= 2000 do
    user_id = socket.assigns.user_id
    room_id = socket.assigns.room_id
    display_name = socket.assigns.display_name

    # Check text permission.
    role_perms = get_user_permissions(socket)

    if Permissions.has_permission?(role_perms, :text) do
      # Store in NNTPSBackend for persistence and threading.
      Burble.Text.NNTPSBackend.post_message(
        room_id, user_id, display_name, body, %{}
      )

      broadcast!(socket, "text", %{
        user_id: user_id,
        display_name: display_name,
        body: body,
        sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

      {:noreply, socket}
    else
      {:reply, {:error, %{reason: "no_text_permission"}}, socket}
    end
  end

  # ── Whisper (directed audio) ──

  @impl true
  def handle_in("whisper", %{"to" => target_id}, socket) do
    role_perms = get_user_permissions(socket)

    if Permissions.has_permission?(role_perms, :whisper) do
      broadcast!(socket, "whisper", %{
        from: socket.assigns.user_id,
        to: target_id
      })

      {:noreply, socket}
    else
      {:reply, {:error, %{reason: "no_whisper_permission"}}, socket}
    end
  end

  # ── Cleanup ──

  @impl true
  def terminate(_reason, socket) do
    room_id = socket.assigns[:room_id]
    user_id = socket.assigns[:user_id]

    if room_id && user_id do
      # Avow consent attestation for the leave.
      Avow.attest_leave(user_id, room_id, :voluntary)

      # Audit log.
      Audit.log(:room_leave, user_id, %{room_id: room_id})

      Burble.Rooms.Room.leave(room_id, user_id)
    end

    :ok
  end

  # ── Private helpers ──

  # Get the user's effective permissions based on their role.
  # For now, assign based on is_guest flag. Full role-based permissions
  # will use server config stored in VeriSimDB.
  defp get_user_permissions(socket) do
    if socket.assigns[:is_guest] do
      Permissions.role_template(:guest)
    else
      Permissions.role_template(:member)
    end
  end
end
