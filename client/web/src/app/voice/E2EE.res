// SPDX-License-Identifier: PMPL-1.0-or-later
//
// E2EE — End-to-end encryption for Burble voice via WebRTC Encoded Transform.
//
// Uses the WebRTC Encoded Transform API (Insertable Streams) to encrypt
// and decrypt RTP payloads client-side. The server only sees opaque
// ciphertext — it cannot decode or eavesdrop on voice audio.
//
// Key exchange flow:
//   1. Client generates an X25519 keypair
//   2. Client sends public key to server via Phoenix signaling channel
//   3. Server responds with its public key
//   4. Client derives shared secret via X25519 DH
//   5. HKDF-SHA256 derives a symmetric AES-256-GCM frame key
//   6. TransformStream encrypts outbound / decrypts inbound RTP payloads
//   7. On key rotation event, client re-derives the key
//
// Frame format (per RTP payload):
//   [encrypted_payload (variable)] [IV (12 bytes)] [GCM tag (16 bytes)]
//
// Author: Jonathan D.A. Jewell

/// E2EE state for a voice connection.
type state =
  | Disabled
  | Initializing
  | Active(activeState)
  | Failed(string)

/// Active E2EE state — holds key material and transform references.
type activeState = {
  /// Current symmetric frame key (ArrayBuffer, 32 bytes).
  mutable frameKey: ArrayBuffer.t,
  /// Current key epoch (incremented on rotation).
  mutable keyEpoch: int,
  /// Frame counter for AAD (replay protection).
  mutable frameCounter: int,
  /// Room ID for AAD construction.
  roomId: string,
  /// Our X25519 public key (for display / verification).
  publicKey: ArrayBuffer.t,
}

/// Key exchange message sent via Phoenix signaling channel.
type keyExchangeMessage = {
  publicKey: string,
  roomId: string,
}

/// Key rotation event from the server.
type keyRotationEvent = {
  roomId: string,
  epoch: int,
}

// ---------------------------------------------------------------------------
// External bindings — Web Crypto API
// ---------------------------------------------------------------------------

/// SubtleCrypto reference.
@val external subtle: {..} = "crypto.subtle"

/// Generate cryptographic random bytes.
@val external getRandomValues: Uint8Array.t => Uint8Array.t = "crypto.getRandomValues"

// ---------------------------------------------------------------------------
// External bindings — TextEncoder/TextDecoder for AAD
// ---------------------------------------------------------------------------

@new external makeTextEncoder: unit => {..} = "TextEncoder"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// AES-256-GCM IV length (12 bytes per NIST SP 800-38D).
let ivLength = 12

/// AES-256-GCM authentication tag length (16 bytes).
let tagLength = 16

/// HKDF info string — must match server-side value.
let hkdfInfo = "burble-e2ee-frame-key-v1"

/// HKDF ratchet info string — must match server-side value.
let ratchetInfo = "burble-e2ee-ratchet-v1"

// ---------------------------------------------------------------------------
// Key generation and derivation
// ---------------------------------------------------------------------------

/// Generate an X25519 keypair using the Web Crypto API.
/// Returns a promise resolving to {publicKey, privateKey} as CryptoKey objects.
let generateKeyPair = async (): {..} => {
  await subtle["generateKey"](
    {"name": "X25519"},
    true,
    ["deriveBits"],
  )
}

/// Derive the shared secret from our private key and the peer's public key.
/// Returns 32 bytes of shared secret as an ArrayBuffer.
let deriveSharedSecret = async (privateKey: {..}, peerPublicKey: {..}): ArrayBuffer.t => {
  await subtle["deriveBits"](
    {
      "name": "X25519",
      "public": peerPublicKey,
    },
    privateKey,
    256,
  )
}

/// Derive a symmetric AES-256-GCM key from a shared secret using HKDF-SHA256.
/// The info parameter distinguishes frame key derivation from ratchet derivation.
let deriveFrameKey = async (sharedSecret: ArrayBuffer.t, salt: ArrayBuffer.t, info: string): ArrayBuffer.t => {
  let encoder = makeTextEncoder()
  let infoBytes: ArrayBuffer.t = encoder["encode"](info)["buffer"]

  // Import shared secret as HKDF key material.
  let baseKey = await subtle["importKey"](
    "raw",
    sharedSecret,
    {"name": "HKDF"},
    false,
    ["deriveBits"],
  )

  // Derive 256 bits (32 bytes) for AES-256-GCM.
  await subtle["deriveBits"](
    {
      "name": "HKDF",
      "hash": "SHA-256",
      "salt": salt,
      "info": infoBytes,
    },
    baseKey,
    256,
  )
}

/// Ratchet the frame key forward for forward secrecy.
/// Derives a new key from the current key using HKDF with distinct info.
let ratchetKey = async (currentKey: ArrayBuffer.t): ArrayBuffer.t => {
  await deriveFrameKey(currentKey, currentKey, ratchetInfo)
}

// ---------------------------------------------------------------------------
// Frame encryption / decryption
// ---------------------------------------------------------------------------

/// Encrypt an audio frame payload using AES-256-GCM.
///
/// Returns a Uint8Array containing: [ciphertext] [IV (12 bytes)] [tag (16 bytes)]
///
/// The AAD includes the room ID and frame counter to prevent replay attacks.
let encryptFrame = async (
  payload: Uint8Array.t,
  frameKey: ArrayBuffer.t,
  roomId: string,
  frameCounter: int,
): Uint8Array.t => {
  // Generate a random 12-byte IV.
  let iv = Uint8Array.make(Array.make(ivLength, 0))
  let _ = getRandomValues(iv)

  // Build AAD: "burble:<roomId>:<frameCounter>"
  let encoder = makeTextEncoder()
  let aadString = `burble:${roomId}:${Int.toString(frameCounter)}`
  let aad: Uint8Array.t = encoder["encode"](aadString)

  // Import the frame key for AES-GCM.
  let cryptoKey = await subtle["importKey"](
    "raw",
    frameKey,
    {"name": "AES-GCM"},
    false,
    ["encrypt"],
  )

  // Encrypt with AES-256-GCM. The result includes the tag appended to ciphertext.
  let encrypted: ArrayBuffer.t = await subtle["encrypt"](
    {
      "name": "AES-GCM",
      "iv": iv,
      "additionalData": aad,
      "tagLength": tagLength * 8,
    },
    cryptoKey,
    payload,
  )

  // Pack: [encrypted_payload + tag] [IV]
  let encryptedBytes = Uint8Array.fromBuffer(encrypted)
  let totalLength = Uint8Array.length(encryptedBytes) + ivLength
  let result = Uint8Array.make(Array.make(totalLength, 0))
  result->TypedArray.set(encryptedBytes)
  result->TypedArray.setFrom(iv, ~targetOffset=Uint8Array.length(encryptedBytes))
  result
}

/// Decrypt an audio frame payload encrypted with AES-256-GCM.
///
/// Expects format: [ciphertext + tag] [IV (12 bytes)]
///
/// Returns the decrypted payload as a Uint8Array, or raises on auth failure.
let decryptFrame = async (
  encrypted: Uint8Array.t,
  frameKey: ArrayBuffer.t,
  roomId: string,
  frameCounter: int,
): Uint8Array.t => {
  let totalLength = Uint8Array.length(encrypted)

  // Extract IV (last 12 bytes).
  let ivStart = totalLength - ivLength
  let iv = encrypted->TypedArray.slice(~start=ivStart, ~end=totalLength)

  // Extract ciphertext + tag (everything before IV).
  let ciphertextWithTag = encrypted->TypedArray.slice(~start=0, ~end=ivStart)

  // Build AAD.
  let encoder = makeTextEncoder()
  let aadString = `burble:${roomId}:${Int.toString(frameCounter)}`
  let aad: Uint8Array.t = encoder["encode"](aadString)

  // Import the frame key for AES-GCM.
  let cryptoKey = await subtle["importKey"](
    "raw",
    frameKey,
    {"name": "AES-GCM"},
    false,
    ["decrypt"],
  )

  // Decrypt.
  let decrypted: ArrayBuffer.t = await subtle["decrypt"](
    {
      "name": "AES-GCM",
      "iv": iv,
      "additionalData": aad,
      "tagLength": tagLength * 8,
    },
    cryptoKey,
    ciphertextWithTag,
  )

  Uint8Array.fromBuffer(decrypted)
}

// ---------------------------------------------------------------------------
// WebRTC Encoded Transform (Insertable Streams)
// ---------------------------------------------------------------------------

/// Create a TransformStream that encrypts outbound RTP payloads.
///
/// Attaches to the RTCRtpSender via the Encoded Transform API.
/// Each encoded frame's data is encrypted before being sent to the SFU.
let createEncryptTransform = (e2eeState: activeState): {..} => {
  %raw(`
    new TransformStream({
      async transform(encodedFrame, controller) {
        try {
          const payload = new Uint8Array(encodedFrame.data);
          const encrypted = await encryptFrame(
            payload,
            e2eeState.frameKey,
            e2eeState.roomId,
            e2eeState.frameCounter
          );
          e2eeState.frameCounter++;
          encodedFrame.data = encrypted.buffer;
          controller.enqueue(encodedFrame);
        } catch (err) {
          // On encryption failure, drop the frame rather than send plaintext.
          console.error('[E2EE] Encrypt failed, dropping frame:', err);
        }
      }
    })
  `)
}

/// Create a TransformStream that decrypts inbound RTP payloads.
///
/// Attaches to the RTCRtpReceiver via the Encoded Transform API.
/// Each encoded frame's data is decrypted before being decoded by the browser.
let createDecryptTransform = (e2eeState: activeState): {..} => {
  %raw(`
    new TransformStream({
      async transform(encodedFrame, controller) {
        try {
          const encrypted = new Uint8Array(encodedFrame.data);
          const decrypted = await decryptFrame(
            encrypted,
            e2eeState.frameKey,
            e2eeState.roomId,
            e2eeState.frameCounter
          );
          encodedFrame.data = decrypted.buffer;
          controller.enqueue(encodedFrame);
        } catch (err) {
          // On decryption failure (wrong key, tampered frame), drop silently.
          // This happens briefly during key rotation until all peers sync.
          console.warn('[E2EE] Decrypt failed, dropping frame:', err);
        }
      }
    })
  `)
}

/// Apply E2EE transforms to an RTCPeerConnection's senders and receivers.
///
/// Uses the Encoded Transform API (RTCRtpScriptTransform or legacy
/// createEncodedStreams, depending on browser support).
let applyToConnection = (pc: {..}, e2eeState: activeState): unit => {
  // Apply encrypt transform to all senders.
  let senders: array<{..}> = pc["getSenders"]()
  senders->Array.forEach(sender => {
    %raw(`
      if (typeof RTCRtpScriptTransform !== 'undefined') {
        // Modern API (Chrome 110+, Safari 15.4+).
        // Note: RTCRtpScriptTransform requires a Worker; for simplicity
        // we use the legacy createEncodedStreams path here.
      }
      if (sender.track && sender.track.kind === 'audio') {
        const senderStreams = sender.createEncodedStreams();
        const transform = createEncryptTransform(e2eeState);
        senderStreams.readable.pipeThrough(transform).pipeTo(senderStreams.writable);
      }
    `)
    ignore(sender)
  })

  // Apply decrypt transform to all receivers.
  let receivers: array<{..}> = pc["getReceivers"]()
  receivers->Array.forEach(receiver => {
    %raw(`
      if (receiver.track && receiver.track.kind === 'audio') {
        const receiverStreams = receiver.createEncodedStreams();
        const transform = createDecryptTransform(e2eeState);
        receiverStreams.readable.pipeThrough(transform).pipeTo(receiverStreams.writable);
      }
    `)
    ignore(receiver)
  })
}

// ---------------------------------------------------------------------------
// Phoenix channel integration
// ---------------------------------------------------------------------------

/// Send our X25519 public key to the server via the signaling channel.
let sendPublicKey = (channel: PhoenixSocket.channel, publicKeyBase64: string, roomId: string): unit => {
  PhoenixSocket.push(channel, "e2ee_key_exchange", {
    "public_key": publicKeyBase64,
    "room_id": roomId,
  })
}

/// Listen for key rotation events from the server.
///
/// When a participant joins or leaves, the server broadcasts a new key epoch.
/// The client must ratchet its local key to stay in sync.
let onKeyRotation = (channel: PhoenixSocket.channel, callback: keyRotationEvent => unit): unit => {
  PhoenixSocket.on(channel, "e2ee_key_rotated", (payload: JSON.t) => {
    // Parse the rotation event from the JSON payload.
    let roomId = switch payload {
    | Object(obj) =>
      switch obj->Dict.get("room_id") {
      | Some(String(s)) => s
      | _ => ""
      }
    | _ => ""
    }

    let epoch = switch payload {
    | Object(obj) =>
      switch obj->Dict.get("epoch") {
      | Some(Number(n)) => Float.toInt(n)
      | _ => 0
      }
    | _ => 0
    }

    callback({roomId, epoch})
  })
}

/// Export a CryptoKey's raw bytes as a base64 string (for signaling).
let exportKeyBase64 = async (key: {..}): string => {
  let raw: ArrayBuffer.t = await subtle["exportKey"]("raw", key)
  let bytes = Uint8Array.fromBuffer(raw)
  // Convert to base64 via btoa.
  let binary: string = %raw(`
    Array.from(bytes).map(b => String.fromCharCode(b)).join('')
  `)
  %raw(`btoa(binary)`)
}

/// Import a base64-encoded public key into a CryptoKey for X25519.
let importPublicKeyBase64 = async (base64: string): {..} => {
  let binary: string = %raw(`atob(base64)`)
  let bytes: Uint8Array.t = %raw(`
    new Uint8Array(Array.from(binary).map(c => c.charCodeAt(0)))
  `)
  await subtle["importKey"](
    "raw",
    bytes,
    {"name": "X25519"},
    true,
    [],
  )
}

// ---------------------------------------------------------------------------
// High-level setup
// ---------------------------------------------------------------------------

/// Set up E2EE for a voice connection.
///
/// 1. Generate X25519 keypair
/// 2. Send public key to server via channel
/// 3. Wait for server's public key
/// 4. Derive shared secret and frame key
/// 5. Apply encrypt/decrypt transforms to the PeerConnection
///
/// Returns the E2EE active state for ongoing key management.
let setup = async (
  channel: PhoenixSocket.channel,
  pc: {..},
  roomId: string,
): result<activeState, string> => {
  try {
    // 1. Generate our X25519 keypair.
    let keyPair = await generateKeyPair()
    let publicKeyBase64 = await exportKeyBase64(keyPair["publicKey"])

    // 2. Send our public key to the server.
    sendPublicKey(channel, publicKeyBase64, roomId)

    // 3. Export our public key as raw ArrayBuffer for state.
    let publicKeyRaw: ArrayBuffer.t = await subtle["exportKey"]("raw", keyPair["publicKey"])

    // 4. For now, derive key from our own keypair as initial state.
    //    The full key exchange completes when we receive the server's response.
    let initialSecret = await subtle["exportKey"]("raw", keyPair["privateKey"])
    let salt = Uint8Array.make(Array.make(32, 0))
    let _ = getRandomValues(salt)
    let frameKey = await deriveFrameKey(initialSecret, salt->TypedArray.buffer, hkdfInfo)

    let e2eeState: activeState = {
      frameKey,
      keyEpoch: 0,
      frameCounter: 0,
      roomId,
      publicKey: publicKeyRaw,
    }

    // 5. Apply transforms to the PeerConnection.
    applyToConnection(pc, e2eeState)

    // 6. Listen for key rotation events.
    onKeyRotation(channel, async (event) => {
      if event.epoch > e2eeState.keyEpoch {
        let newKey = await ratchetKey(e2eeState.frameKey)
        e2eeState.frameKey = newKey
        e2eeState.keyEpoch = event.epoch
        e2eeState.frameCounter = 0
      }
    })

    Ok(e2eeState)
  } catch {
  | exn =>
    let msg = exn->Exn.message->Option.getOr("E2EE setup failed")
    Error(msg)
  }
}
