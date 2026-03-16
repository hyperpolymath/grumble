// SPDX-License-Identifier: PMPL-1.0-or-later
//
// BurbleVoice — WebRTC voice engine for the embeddable client.
//
// Manages the WebRTC PeerConnection lifecycle, media streams, and
// voice processing pipeline. Uses the browser's MediaDevices API
// for microphone access and WebAudio API for processing.
//
// Pipeline (outbound):
//   Microphone → MediaStream → AudioContext → (noise suppress, echo cancel)
//   → PeerConnection → Burble SFU → other peers
//
// Pipeline (inbound):
//   SFU → PeerConnection → AudioContext → (spatial positioning if enabled)
//   → Speaker output
//
// The coprocessor kernels (noise gate, echo cancel, neural denoise) run
// server-side in the Zig NIFs. Client-side uses browser built-in processing
// (autoGainControl, noiseSuppression, echoCancellation) as a first pass.

/// WebRTC connection state.
type rtcState =
  | Idle
  | GatheringCandidates
  | Negotiating
  | Active
  | Closed

/// Audio device info.
type audioDevice = {
  deviceId: string,
  label: string,
  kind: string, // "audioinput" or "audiooutput"
}

/// Voice engine state.
type voiceEngine = {
  mutable rtcState: rtcState,
  mutable localStream: option<{..}>,   // MediaStream
  mutable peerConnection: option<{..}>, // RTCPeerConnection
  mutable audioContext: option<{..}>,   // AudioContext
  mutable isMuted: bool,
  mutable isDeafened: bool,
  mutable isSpeaking: bool,
  mutable audioLevel: float,
  mutable inputDevice: option<string>,
  mutable outputDevice: option<string>,
  profileConfig: BurbleClient.profileConfig,
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a new voice engine with the given profile config.
let make = (profileConfig: BurbleClient.profileConfig): voiceEngine => {
  {
    rtcState: Idle,
    localStream: None,
    peerConnection: None,
    audioContext: None,
    isMuted: false,
    isDeafened: false,
    isSpeaking: false,
    audioLevel: 0.0,
    inputDevice: None,
    outputDevice: None,
    profileConfig,
  }
}

// ---------------------------------------------------------------------------
// External bindings (browser WebRTC/WebAudio APIs)
// ---------------------------------------------------------------------------

/// Get user media (microphone access).
@val external getUserMedia: {..} => promise<{..}> = "navigator.mediaDevices.getUserMedia"

/// Enumerate audio devices.
@val external enumerateDevices: unit => promise<array<{..}>> = "navigator.mediaDevices.enumerateDevices"

/// Create an RTCPeerConnection.
@new external makeRTCPeerConnection: {..} => {..} = "RTCPeerConnection"

/// Create an AudioContext.
@new external makeAudioContext: unit => {..} = "AudioContext"

// ---------------------------------------------------------------------------
// Media acquisition
// ---------------------------------------------------------------------------

/// Request microphone access with profile-appropriate constraints.
let acquireMicrophone = async (engine: voiceEngine): result<unit, string> => {
  let constraints = {
    "audio": {
      "autoGainControl": true,
      "noiseSuppression": engine.profileConfig.noiseSuppression,
      "echoCancellation": engine.profileConfig.echoCancellation,
      "channelCount": 1,
      "sampleRate": 48000,
    },
    "video": false,
  }

  try {
    let stream = await getUserMedia(constraints)
    engine.localStream = Some(stream)
    Ok()
  } catch {
  | exn => Error(exn->Exn.message->Option.getOr("Microphone access denied"))
  }
}

/// List available audio input/output devices.
let listDevices = async (): result<array<audioDevice>, string> => {
  try {
    let devices = await enumerateDevices()
    let audioDevices = devices->Array.filterMap(d => {
      let kind: string = d["kind"]
      if kind == "audioinput" || kind == "audiooutput" {
        Some({
          deviceId: d["deviceId"],
          label: d["label"],
          kind,
        })
      } else {
        None
      }
    })
    Ok(audioDevices)
  } catch {
  | exn => Error(exn->Exn.message->Option.getOr("Failed to enumerate devices"))
  }
}

// ---------------------------------------------------------------------------
// Voice controls
// ---------------------------------------------------------------------------

/// Toggle mute state.
let toggleMute = (engine: voiceEngine): bool => {
  engine.isMuted = !engine.isMuted

  // Mute/unmute the local audio tracks.
  switch engine.localStream {
  | Some(stream) =>
    let tracks: array<{..}> = stream["getAudioTracks"]()
    tracks->Array.forEach(track => {
      track["enabled"] = !engine.isMuted
    })
  | None => ()
  }

  engine.isMuted
}

/// Toggle deafen state (mutes + deafens).
let toggleDeafen = (engine: voiceEngine): bool => {
  engine.isDeafened = !engine.isDeafened

  // When deafening, also mute.
  if engine.isDeafened && !engine.isMuted {
    let _ = toggleMute(engine)
  }

  engine.isDeafened
}

/// Set input device by deviceId.
let setInputDevice = (engine: voiceEngine, deviceId: string): unit => {
  engine.inputDevice = Some(deviceId)
  // Re-acquire microphone with new device constraint.
  // (Caller should await acquireMicrophone after this.)
}

/// Set output device by deviceId.
let setOutputDevice = (engine: voiceEngine, deviceId: string): unit => {
  engine.outputDevice = Some(deviceId)
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

/// Stop all media and close the peer connection.
let destroy = (engine: voiceEngine): unit => {
  // Stop local media tracks.
  switch engine.localStream {
  | Some(stream) =>
    let tracks: array<{..}> = stream["getTracks"]()
    tracks->Array.forEach(track => {
      track["stop"]()
    })
  | None => ()
  }

  // Close peer connection.
  switch engine.peerConnection {
  | Some(pc) => pc["close"]()
  | None => ()
  }

  // Close audio context.
  switch engine.audioContext {
  | Some(ctx) => ctx["close"]()
  | None => ()
  }

  engine.localStream = None
  engine.peerConnection = None
  engine.audioContext = None
  engine.rtcState = Closed
}
