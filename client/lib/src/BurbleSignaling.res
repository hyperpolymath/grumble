// SPDX-License-Identifier: PMPL-1.0-or-later
//
// BurbleSignaling — Phoenix WebSocket signaling for BurbleClient.
//
// Handles the signaling plane: connects to the Burble server via
// Phoenix Channels, manages room channel subscriptions, and relays
// WebRTC signaling messages (SDP offers/answers, ICE candidates).
//
// Both IDApTIK and PanLL already have PhoenixSocket implementations.
// This module provides a STANDALONE signaling layer so consumers
// don't need to share their Phoenix socket — Burble gets its own
// connection on the /voice path.
//
// Protocol:
//   Client → Server: join "room:<id>", voice_state, signal, text
//   Server → Client: presence_state, voice_state_changed, signal, text

/// Signaling event types received from the server.
type serverEvent =
  | PresenceState(Dict.t<string, {..}>)
  | PresenceDiff({joins: Dict.t<string, {..}>, leaves: Dict.t<string, {..}>})
  | VoiceStateChanged({userId: string, voiceState: string})
  | Signal({from: string, toSelf: string, signalType: string, payload: {..}})
  | TextMessage({userId: string, displayName: string, body: string, sentAt: string})
  | RoomState({..})
  | Error(string)

/// Signaling callbacks.
type callbacks = {
  onEvent: serverEvent => unit,
  onJoined: {..} => unit,
  onError: string => unit,
}

/// Signaling connection state.
type signalingState = {
  mutable socket: option<{..}>,
  mutable channel: option<{..}>,
  mutable connected: bool,
  mutable roomId: option<string>,
  serverUrl: string,
  callbacks: callbacks,
}

// ---------------------------------------------------------------------------
// External: Phoenix JS client bindings
// ---------------------------------------------------------------------------

/// Phoenix Socket constructor.
@new @module("phoenix") external makeSocket: (string, {..}) => {..} = "Socket"

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a signaling connection.
let make = (serverUrl: string, callbacks: callbacks): signalingState => {
  {
    socket: None,
    channel: None,
    connected: false,
    roomId: None,
    serverUrl,
    callbacks,
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

/// Connect to the Burble server's voice WebSocket endpoint.
let connect = (state: signalingState, token: string): unit => {
  let socket = makeSocket(state.serverUrl, {"params": {"token": token}})
  socket["connect"]()
  state.socket = Some(socket)
  state.connected = true
}

/// Connect as a guest (no auth token).
let connectGuest = (state: signalingState, displayName: string): unit => {
  let socket = makeSocket(state.serverUrl, {
    "params": {"guest": "true", "display_name": displayName},
  })
  socket["connect"]()
  state.socket = Some(socket)
  state.connected = true
}

/// Disconnect from the server.
let disconnect = (state: signalingState): unit => {
  switch state.channel {
  | Some(ch) => ch["leave"]()
  | None => ()
  }

  switch state.socket {
  | Some(s) => s["disconnect"]()
  | None => ()
  }

  state.socket = None
  state.channel = None
  state.connected = false
  state.roomId = None
}

// ---------------------------------------------------------------------------
// Room channel
// ---------------------------------------------------------------------------

/// Join a room channel. Sets up event handlers for voice signaling.
let joinRoom = (state: signalingState, roomId: string, displayName: string): unit => {
  switch state.socket {
  | None => state.callbacks.onError("Not connected")
  | Some(socket) =>
    let topic = "room:" ++ roomId
    let channel = socket["channel"](topic, {"display_name": displayName})

    // Wire server event handlers.
    channel["on"]("presence_state", (payload: {..}) => {
      state.callbacks.onEvent(PresenceState(Obj.magic(payload)))
    })

    channel["on"]("voice_state_changed", (payload: {..}) => {
      state.callbacks.onEvent(VoiceStateChanged({
        userId: payload["user_id"],
        voiceState: payload["voice_state"],
      }))
    })

    channel["on"]("signal", (payload: {..}) => {
      state.callbacks.onEvent(Signal({
        from: payload["from"],
        toSelf: payload["to"],
        signalType: payload["type"],
        payload: payload["payload"],
      }))
    })

    channel["on"]("text", (payload: {..}) => {
      state.callbacks.onEvent(TextMessage({
        userId: payload["user_id"],
        displayName: payload["display_name"],
        body: payload["body"],
        sentAt: payload["sent_at"],
      }))
    })

    // Join the channel.
    let joinPush = channel["join"]()
    joinPush["receive"]("ok", (resp: {..}) => {
      state.roomId = Some(roomId)
      state.callbacks.onJoined(resp)
    })
    joinPush["receive"]("error", (resp: {..}) => {
      state.callbacks.onError("Join failed: " ++ Obj.magic(resp))
    })

    state.channel = Some(channel)
  }
}

/// Leave the current room channel.
let leaveRoom = (state: signalingState): unit => {
  switch state.channel {
  | Some(ch) => ch["leave"]()
  | None => ()
  }
  state.channel = None
  state.roomId = None
}

// ---------------------------------------------------------------------------
// Sending events
// ---------------------------------------------------------------------------

/// Send a voice state update.
let sendVoiceState = (state: signalingState, voiceState: string): unit => {
  switch state.channel {
  | Some(ch) => ch["push"]("voice_state", {"state": voiceState})
  | None => ()
  }
}

/// Send a WebRTC signaling message (SDP offer/answer, ICE candidate).
let sendSignal = (state: signalingState, to: string, signalType: string, payload: {..}): unit => {
  switch state.channel {
  | Some(ch) =>
    ch["push"]("signal", {"to": to, "type": signalType, "payload": payload})
  | None => ()
  }
}

/// Send a text message in the room.
let sendText = (state: signalingState, body: string): unit => {
  switch state.channel {
  | Some(ch) => ch["push"]("text", {"body": body})
  | None => ()
  }
}

/// Send a whisper (directed audio) request.
let sendWhisper = (state: signalingState, to: string): unit => {
  switch state.channel {
  | Some(ch) => ch["push"]("whisper", {"to": to})
  | None => ()
  }
}
