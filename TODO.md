<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
# Burble — Outstanding Work

## Status: MUST and SHOULD complete (2026-03-22)

All MUST and SHOULD features are implemented. See ROADMAP below for COULD items.

---

## Completed (2026-03-22 session)

### Voice Pipeline (MUST — all done)
- [x] Replace P2P with SFU (Burble.Media.Peer + ExWebRTC PeerConnection)
- [x] TURN server config (BURBLE_TURN_URL/USER/PASS env vars)
- [x] WebRTC voice engine wired (VoiceEngine.res — PeerConnection, signaling, getUserMedia)
- [x] Push-to-talk client UI (configurable key, TX indicator)
- [x] VAD/PTT mode switching at runtime
- [x] Per-peer volume control (0-200%)
- [x] Reconnection with exponential backoff (5 attempts, max 30s)
- [x] E2EE via WebRTC Insertable Streams (X25519 + AES-256-GCM + ratcheting)
- [x] Mute/deafen with server sync

### Signal Science (coprocessor — all done)
- [x] Audio kernel: PCM, noise gate, NLMS echo cancellation (62x Zig)
- [x] DSP kernel: Cooley-Tukey FFT/IFFT (37x Zig), convolution (28x), mixing
- [x] Neural kernel: spectral gating denoiser, noise classification
- [x] Crypto kernel: AES-256-GCM, SHA-256 chains, HKDF
- [x] I/O kernel: jitter buffer, PLC, AIMD adaptive bitrate
- [x] Compression kernel: LZ4/zstd, FLAC-style, .barc recorder
- [x] AGC (automatic gain control with soft clipping)
- [x] Comfort noise generation (spectrally shaped)
- [x] Spectral VAD (FFT-based voice activity detection)
- [x] Perceptual weighting (A-weighting curve)
- [x] Voice masks (6 presets + custom — pitch shift, formant manipulation, roboticness)

### Client (MUST/SHOULD — all done)
- [x] Voice controls bar (mute/deafen/PTT/VAD/level meter/self-test/settings/leave)
- [x] Room list sidebar (API fetch, participants, click-to-join, auto-refresh)
- [x] Text chat component (NNTPS threading, markdown, Phoenix channel real-time)
- [x] Screen share (getDisplayMedia, SFU relay, one-per-room, moderator takeover)
- [x] E2EE client (Web Crypto API, Encoded Transform, key rotation listener)
- [x] Mobile responsive CSS (breakpoints, safe-area, touch targets, drawer nav)

### Server (MUST/SHOULD — all done)
- [x] Auth: register, login, guest, magic link, JWT (access/refresh/guest tokens)
- [x] Rooms: create, join, leave, participants, permissions
- [x] Channel routing: broadcast all / group / private whisper / priority speaker
- [x] Instant connect: link/QR/code (8-char, mutual confirmation, group invites)
- [x] Moderation: kick, ban, mute, move, timeout (permission-checked, audit-logged)
- [x] Kaomoji status indicators (22 animated statuses, 4 categories, F-key shortcuts)
- [x] Self-test diagnostics (quick/voice/full, HTTP endpoint)
- [x] Magic link email (Swoosh SMTP, rate limiting, HTML template)
- [x] VeriSimDB integration (replaces PostgreSQL entirely)
- [x] Verification layers: NNTPS, Vext, Avow

### Deployment (MUST — done)
- [x] Containerfile.server (multi-stage Chainguard, OTP release, non-root)
- [x] Containerfile.web (nginx SPA)
- [x] selur-compose.toml (server + web + verisimdb)
- [x] Port 4020 (all configs updated)

### Transport (SHOULD — done)
- [x] QUIC module (0-RTT, multiplexed streams, connection migration)
- [x] RTSP module (broadcast rooms, IDApTIK CCTV feeds)
- [x] Bebop wire protocol schemas

### Integration (SHOULD — done)
- [x] IDApTIK BurbleAdapter + VoiceBridge (gaming profile, spatial audio)
- [x] PanLL BurbleEngine + BurbleModel + BurbleCmd (workspace huddles)
- [x] Gossamer desktop client (tray, global hotkeys, PipeWire routing)
- [x] Extension API (core/profiles/extensions three-tier)
- [x] IDApTIKVoice extension (spatial, auto-mute cutscenes, stealth whisper)
- [x] PanLLVoice extension (workspace huddles, PanelBus events)
- [x] BurbleSpatial extension (3D positional audio)

### Security (P1 — done)
- [x] E2EE via Insertable Streams (E2EE.res — X25519, AES-256-GCM, frame ratcheting)
- [x] Key rotation scheduler (KeyRotation GenServer — 20s interval, PubSub lifecycle)
- [x] mTLS for server-to-server (mTLS module — certificate generation, peer verification)
- [x] Rate limiting on auth endpoints (RateLimiter plug — ETS token bucket, 3 tiers)
- [x] Media Engine signal dispatch (routes SDP/ICE to Peer GenServers)

### Setup & Diagnostics (P0 — done)
- [x] Self-test: 16 tests, 3 modes (quick/voice/full), HTTP API
- [x] SelfTestPanel.res: card grid, mode selector, latency colours, progress spinner
- [x] SetupWizard.res: 7-step wizard (permissions, devices, mic test, speaker test, network test)
- [x] Mic test: getUserMedia + AnalyserNode + level meter with colour coding
- [x] Speaker test: 440Hz oscillator with auto-stop
- [x] Network test: self-test API fetch with latency measurement

---

## COULD — Roadmap (future sessions)

### Privacy
- [ ] WebRTC anonymisation (TURN-only mode, mDNS candidates)
- [ ] IP/MAC obfuscation (hashed logging, Tor-compatible mode)
- [ ] Chaff traffic (constant bitrate, fake packets during silence)
- [ ] Panic key (instant disconnect + clear state + close)
- [ ] Ghost mode (leave without notification)
- [ ] Per-user blocking (server-enforced, persisted)

### Accessibility
- [ ] BSL sign language avatar (speech-to-sign via Gossamer webview)
- [ ] Live captions (speech-to-text)
- [ ] Translated captions

### Advanced Audio
- [ ] RNNoise-style neural model (replace spectral gating)
- [ ] Wiener filtering (non-stationary noise)
- [ ] De-reverberation (room echo removal)
- [ ] Spectral PLC (frequency-domain packet loss concealment)
- [ ] Per-user VAD learning (adaptive thresholds)
- [ ] LMDB playout buffer (crash-resilient timing)
- [ ] Precision timing (PTP-inspired clock sync)

### Transport & Protocol
- [ ] QUIC client wiring (quicer dependency)
- [ ] Multipath redundancy (3-port striping)
- [ ] Media over QUIC (MoQ IETF standard)
- [ ] WebTransport upgrade
- [ ] Bebop codegen (Elixir + ReScript)

### Interop
- [ ] Mumble bridge (protobuf, open spec)
- [ ] Discord bridge (bot API)
- [ ] SIP/PBX gateway
- [ ] Matrix/Element bridge

### Platform
- [ ] Gossamer desktop Zig FFI wiring
- [ ] PipeWire direct audio routing
- [ ] Tauri 2 desktop wrapper (fallback)
- [ ] Native mobile (if needed)
- [ ] Ephapax WASM pipeline module

### Community
- [ ] Stage/broadcast rooms
- [ ] Soundboard/clip injection
- [ ] SSO / enterprise auth
- [ ] Webhooks and bot framework
- [ ] Multi-server discovery
- [ ] Federation
- [ ] Plugin ecosystem
- [ ] Game presence APIs

### Formal Verification
- [ ] Idris2 proofs: Avow consent lifecycle
- [ ] Idris2 proofs: Vext hash chain integrity
- [ ] Idris2 proofs: permission hierarchy safety
- [ ] Zig FFI bridge from BEAM to Idris2 ABI

---

## Development

```bash
# Start server (dev)
cd server && PROVEN_LIB_DIR=/var$REPOS_DIR/proven/ffi/zig/zig-out/lib mix phx.server
# → http://localhost:6473

# VeriSimDB (required for persistence)
cd nextgen-databases/verisimdb && cargo run
# → http://localhost:8080

# Zig NIFs (optional — falls back to Elixir)
cd ffi/zig && zig build -Doptimize=ReleaseFast
# Copy to server/priv/

# Container deployment
cd containers && podman-compose -f selur-compose.toml up

# Self-test
curl http://localhost:6473/api/v1/diagnostics/self-test/full | jq .

# Run tests
cd server && mix test
```
