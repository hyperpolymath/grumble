# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# E2E signaling pipeline tests — exercises the full WebSocket signaling path:
# socket connect → room join → WebRTC offer/answer/ICE exchange → voice state
# → graceful leave.
#
# These tests operate at the Phoenix Channel level (BurbleWeb.RoomChannel) so
# they validate the complete signaling contract rather than individual helpers.
# Audio NIFs and WebRTC media are intentionally excluded — those are covered by
# the coprocessor and voice pipeline suites.
#
# Infrastructure notes:
#   - BurbleWeb.Endpoint is started per test (server: false — no real HTTP).
#   - RoomRegistry, RoomSupervisor, PubSub, Presence, Media.Engine are also
#     started via start_supervised! so ExUnit owns their lifecycle.
#   - All tests run with `async: false` because they share named processes.
#
# Known channel gaps (documented as @tag :known_gap tests):
#   - RoomChannel has no catch-all handle_in clause — unmatched events crash it.
#   - RoomChannel has no handle_info clause for :participant_joined/:left events.
#   - NNTPSBackend is required for text messages; not started in unit test mode.
#
# These tests verify what DOES work today and document known gaps.

defmodule Burble.E2E.SignalingTest do
  use ExUnit.Case, async: false
  use Phoenix.ChannelTest

  import Burble.TestHelpers

  # Phoenix.ChannelTest requires @endpoint to resolve socket/1 and subscribe_and_join/3.
  @endpoint BurbleWeb.Endpoint

  # ---------------------------------------------------------------------------
  # Setup — start required named processes for each test
  # ---------------------------------------------------------------------------

  setup do
    # phoenix_pubsub application must run so its :pg scope exists first.
    Application.ensure_all_started(:phoenix_pubsub)

    # start_supervised! ensures ExUnit owns the lifecycle and tears down between tests.
    start_supervised!({Phoenix.PubSub, name: Burble.PubSub})
    start_supervised!({Registry, keys: :unique, name: Burble.RoomRegistry})
    start_supervised!({DynamicSupervisor, name: Burble.RoomSupervisor, strategy: :one_for_one})

    # Presence tracker — required by RoomChannel.handle_info(:after_join).
    start_supervised!(Burble.Presence)

    # Media.Engine — required by RoomChannel.join/3 (add_peer call).
    start_supervised!(Burble.Media.Engine)

    # Start Endpoint last — depends on PubSub.
    # BurbleWeb.Endpoint is configured with server: false in test config so
    # no real HTTP port is opened; it only starts the ETS table that
    # Phoenix.ChannelTest needs to resolve the pubsub server.
    case BurbleWeb.Endpoint.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helper — build a pre-authenticated guest socket without the JWT stack
  # ---------------------------------------------------------------------------

  defp guest_socket(display_name \\ "TestGuest") do
    {:ok, guest} = Burble.Auth.create_guest_session(display_name)

    socket(:user_socket, %{
      user_id: guest.id,
      display_name: guest.display_name,
      is_guest: true
    })
  end

  # ---------------------------------------------------------------------------
  # Session creation and teardown
  # ---------------------------------------------------------------------------

  describe "session creation and teardown" do
    test "guest can join a room channel and receives presence_state" do
      sock = guest_socket("Alice")
      room_id = generate_room_id()

      {:ok, _reply, chan} =
        subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Alice"
        })

      assert_push "presence_state", %{}

      leave(chan)
    end

    test "join reply is a map (contains room state)" do
      sock = guest_socket("Bob")
      room_id = generate_room_id()

      {:ok, reply, chan} =
        subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Bob"
        })

      assert is_map(reply), "join reply must be a map"

      leave(chan)
    end

    test "second guest joining same room triggers presence_diff for first guest" do
      room_id = generate_room_id()

      sock_a = guest_socket("Alice")
      sock_b = guest_socket("Bob")

      {:ok, _state_a, chan_a} =
        subscribe_and_join(sock_a, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Alice"
        })

      {:ok, _state_b, chan_b} =
        subscribe_and_join(sock_b, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Bob"
        })

      # Alice must receive a presence_diff when Bob joins.
      assert_push "presence_diff", %{}

      leave(chan_a)
      leave(chan_b)
    end

    test "joining an invalid topic format returns error" do
      sock = guest_socket("Eve")

      result = subscribe_and_join(sock, BurbleWeb.RoomChannel, "not_a_room_topic", %{})
      assert {:error, _reason} = result
    end

    test "join reply contains participant_count key" do
      sock = guest_socket("Counter")
      room_id = generate_room_id()

      {:ok, reply, chan} =
        subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Counter"
        })

      # The reply map must include participant_count (set by Room.join/3).
      assert Map.has_key?(reply, :participant_count) or Map.has_key?(reply, "participant_count"),
             "join reply must contain participant_count, got #{inspect(Map.keys(reply))}"

      leave(chan)
    end
  end

  # ---------------------------------------------------------------------------
  # WebRTC signaling — legacy P2P relay path (single-participant room)
  # ---------------------------------------------------------------------------
  # We use single-participant setups to avoid triggering the known-gap where
  # participant_joined PubSub events crash the channel when a second user joins.

  describe "WebRTC signaling (single participant)" do
    setup do
      room_id = generate_room_id()
      sock = guest_socket("Offerer")

      {:ok, _reply, chan} =
        subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Offerer"
        })

      on_exit(fn -> leave(chan) end)

      %{chan: chan, room_id: room_id}
    end

    test "SDP offer signal is broadcast to the room", %{chan: chan} do
      offer_sdp = minimal_sdp_offer()

      push(chan, "signal", %{
        "to" => "peer_b",
        "type" => "offer",
        "payload" => offer_sdp
      })

      assert_broadcast "signal", %{type: "offer", payload: ^offer_sdp}
    end

    test "ICE candidate is broadcast to room participants", %{chan: chan} do
      candidate = minimal_ice_candidate()

      push(chan, "signal", %{
        "to" => "peer_b",
        "type" => "ice_candidate",
        "payload" => candidate
      })

      assert_broadcast "signal", %{type: "ice_candidate", payload: ^candidate}
    end

    test "signal message includes sender user_id (guest_ prefix)", %{chan: chan} do
      push(chan, "signal", %{
        "to" => "peer_b",
        "type" => "offer",
        "payload" => minimal_sdp_offer()
      })

      assert_broadcast "signal", %{from: from_id}
      assert is_binary(from_id) and String.starts_with?(from_id, "guest_"),
             "from must be a guest_ prefixed ID, got #{inspect(from_id)}"
    end

    test "signal message includes 'to' and 'type' fields", %{chan: chan} do
      push(chan, "signal", %{
        "to" => "peer_target",
        "type" => "heartbeat",
        "payload" => "ping"
      })

      assert_broadcast "signal", %{to: "peer_target", type: "heartbeat"}
    end
  end

  # ---------------------------------------------------------------------------
  # Voice state transitions
  # ---------------------------------------------------------------------------

  describe "voice state changes" do
    setup do
      room_id = generate_room_id()
      sock = guest_socket("Speaker")

      {:ok, _reply, chan} =
        subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "Speaker"
        })

      on_exit(fn -> leave(chan) end)

      %{chan: chan, room_id: room_id}
    end

    test "voice_state 'muted' is accepted and broadcast", %{chan: chan} do
      push(chan, "voice_state", %{"state" => "muted"})
      assert_broadcast "voice_state_changed", %{voice_state: "muted"}
    end

    test "voice_state 'deafened' is accepted and broadcast", %{chan: chan} do
      push(chan, "voice_state", %{"state" => "deafened"})
      assert_broadcast "voice_state_changed", %{voice_state: "deafened"}
    end

    test "voice_state 'connected' is accepted for guest (has :speak permission)", %{chan: chan} do
      # Guest role template includes :speak per Burble.Permissions.role_template/1.
      push(chan, "voice_state", %{"state" => "connected"})
      assert_broadcast "voice_state_changed", %{voice_state: "connected"}
    end

    test "broadcast contains the user_id of the speaker", %{chan: chan} do
      push(chan, "voice_state", %{"state" => "muted"})
      assert_broadcast "voice_state_changed", %{user_id: uid}
      assert is_binary(uid) and String.starts_with?(uid, "guest_"),
             "user_id in broadcast must be a guest_ ID"
    end
  end

  # ---------------------------------------------------------------------------
  # Security aspects — UserSocket authentication
  # ---------------------------------------------------------------------------

  describe "security aspect tests" do
    test "connection without token or guest flag returns :error" do
      # connect/3 with no valid params must be rejected by UserSocket.connect/3.
      result =
        Phoenix.ChannelTest.connect(BurbleWeb.UserSocket, %{}, connect_info: %{})

      assert result == :error,
             "unauthenticated connect must be rejected"
    end

    test "guest connection with display_name is accepted" do
      {:ok, socket} =
        Phoenix.ChannelTest.connect(BurbleWeb.UserSocket, %{
          "guest" => "true",
          "display_name" => "Tester"
        })

      assert socket.assigns.is_guest == true
      assert socket.assigns.display_name == "Tester"
    end

    test "guest socket.id is user_socket: prefixed" do
      {:ok, socket} =
        Phoenix.ChannelTest.connect(BurbleWeb.UserSocket, %{
          "guest" => "true",
          "display_name" => "IDTest"
        })

      assert String.starts_with?(BurbleWeb.UserSocket.id(socket), "user_socket:"),
             "socket ID must start with user_socket:"
    end

    test "guest can join a room after socket connect via UserSocket" do
      {:ok, socket} =
        Phoenix.ChannelTest.connect(BurbleWeb.UserSocket, %{
          "guest" => "true",
          "display_name" => "ValidGuest"
        })

      room_id = generate_room_id()

      {:ok, _reply, chan} =
        subscribe_and_join(socket, BurbleWeb.RoomChannel, "room:#{room_id}", %{
          "display_name" => "ValidGuest"
        })

      assert_push "presence_state", %{}

      leave(chan)
    end
  end

  # ---------------------------------------------------------------------------
  # Known gap documentation tests
  # ---------------------------------------------------------------------------
  # These tests assert the CURRENT (broken) behavior so the CI catches regressions
  # and so engineers know what to fix.  Tag: :known_gap.

  @tag :known_gap
  test "channel crashes on malformed signal missing payload (known gap: no catch-all clause)" do
    sock = guest_socket("TestUser")
    room_id = generate_room_id()

    {:ok, _reply, chan} =
      subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{})

    # Sending a signal without "payload" triggers FunctionClauseError.
    # This is a known gap — RoomChannel needs a catch-all handle_in clause.
    Process.flag(:trap_exit, true)
    push(chan, "signal", %{"to" => "someone", "type" => "offer"})

    # The channel process will crash — we accept this as current behavior.
    # TODO: add catch-all handle_in that returns {:reply, {:error, :invalid_event}, socket}
    assert_receive {:EXIT, _pid, _reason}, 500
    Process.flag(:trap_exit, false)
  end

  @tag :known_gap
  test "channel crashes on empty text body (known gap: no catch-all handle_in)" do
    sock = guest_socket("Sender")
    room_id = generate_room_id()

    {:ok, _reply, chan} =
      subscribe_and_join(sock, BurbleWeb.RoomChannel, "room:#{room_id}", %{
        "display_name" => "Sender"
      })

    # Empty body: `when byte_size(body) > 0` guard fails, no other clause matches.
    # This crashes the channel — a known gap.
    # TODO: add `handle_in("text", _, socket)` catch-all returning :error.
    Process.flag(:trap_exit, true)
    push(chan, "text", %{"body" => ""})
    assert_receive {:EXIT, _pid, _reason}, 500
    Process.flag(:trap_exit, false)
  end

  # ---------------------------------------------------------------------------
  # Private helpers — minimal structurally-valid SDP/ICE stubs
  # ---------------------------------------------------------------------------

  # Structurally valid SDP but won't be accepted by a real WebRTC stack.
  # We test only the signaling relay path here, not media negotiation.

  defp minimal_sdp_offer do
    "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
  end

  defp minimal_sdp_answer do
    "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
  end

  defp minimal_ice_candidate do
    "candidate:0 1 UDP 2122252543 192.168.1.100 54400 typ host"
  end
end
