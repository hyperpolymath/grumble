<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
# Burble — Outstanding Work

## Immediate (next session)

### Deepen the voice demo
- [ ] Replace peer-to-peer mesh with Membrane SFU (server-side forwarding)
- [ ] Implement actual E2EE via Insertable Streams (WebRTC Encoded Transform)
- [ ] Set up embedded TURN server (ex_turn) for TURN-only default
- [ ] Add push-to-talk support in the web client

### ReScript web client
- [ ] Replace MVP HTML with full cadre-router SPA (client/web/)
- [ ] Wire VoiceEngine.res to actual WebRTC PeerConnection
- [ ] Build room list sidebar component
- [ ] Build voice controls bar component
- [ ] Build text chat component (with NNTPS threading)

### Coprocessor backends
- [ ] Audio kernel: Opus encode/decode, noise suppression, echo cancellation
- [ ] Crypto kernel: E2EE frame encryption (AES-GCM), Avow hash chains
- [ ] Neural kernel: AI noise suppression (keyboard/fan/dog removal)
- [ ] I/O kernel: jitter buffer, packet loss concealment, adaptive bitrate
- [ ] Math/DSP kernel: FFT, convolution, mixing matrix
- [ ] Idris2 ABI definitions for coprocessor interfaces
- [ ] Zig FFI NIFs for BEAM integration (hot path)

### VeriSimDB integration (dogfooding)
- [x] Replace PostgreSQL/Ecto with VeriSimDB for user accounts
- [x] Burble.Store GenServer wrapping VeriSimClient
- [x] User validation without Ecto (pure struct + validation)
- [x] Provenance modality for auth audit trail
- [ ] Store magic link tokens (temporal modality for expiry)
- [ ] Store invite tokens in VeriSimDB (replace in-memory)
- [ ] Audit log queries via VeriSimDB provenance chains
- [ ] Room config persistence (document modality)
- [ ] Server/guild config persistence
- [ ] Delete old Ecto migration and Repo stub after verification

## Medium term

### Server hardening
- [ ] Replace HMAC with Ed25519 for Avow/Vext signatures
- [ ] Implement proper Guardian JWT auth (replace Phoenix.Token)
- [ ] Add magic link email sending (currently stub)
- [ ] Server-side recording (operator-approved)

### Integration
- [ ] Embeddable client library (client/lib/) for IDApTIK and PanLL
- [ ] IDApTIK: wire Burble into multiplayer for Jessica↔Q voice
- [ ] PanLL: wire Burble as workspace voice layer
- [ ] Spatial/positional audio (Physics coprocessor) for IDApTIK

### Desktop & mobile
- [ ] Tauri 2 desktop wrapper (client/desktop/)
- [ ] Responsive mobile web baseline
- [ ] Native mobile if needed

### Formal verification
- [ ] Idris2 proofs for Avow consent lifecycle
- [ ] Idris2 proofs for Vext hash chain integrity
- [ ] Idris2 proofs for permission hierarchy safety
- [ ] Zig FFI bridge from BEAM to Idris2 ABI

### Deployment
- [ ] Containerfile for web client (nginx + static)
- [ ] Containerfile for server (Elixir OTP release)
- [ ] Containerfile for VeriSimDB (Rust core)
- [ ] podman-compose for one-command deployment (server + verisimdb)
- [ ] Production multi-node reference deployment docs

## Long term

- [ ] Stage/broadcast rooms
- [ ] Soundboard/clip injection (moderation-controlled)
- [ ] SSO / enterprise auth
- [ ] Webhooks and bot framework
- [ ] Multi-server discovery
- [ ] Optional federation
- [ ] Plugin ecosystem
- [ ] Game presence APIs
- [ ] WebTransport upgrade (Layer 3)
- [ ] Media over QUIC migration (Layer 4)

## Notes

- VeriSimDB replaces PostgreSQL — run VeriSimDB on port 8080 before starting Burble
- Dev user: dev@burble.local / burble_dev_123
- Contractiles: 23/23 must checks passing
- Run with: `cd server && mix phx.server` → http://localhost:4000/
- VeriSimDB: `cd nextgen-databases/verisimdb && cargo run` → http://localhost:8080/
- Old Repo stub kept in lib/grumble/repo.ex — delete after full verification
