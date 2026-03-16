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
- [x] Backend behaviour (abstract kernel interface — Axiom.jl pattern)
- [x] ElixirBackend (pure Elixir reference implementation, all 5 kernels)
- [x] SmartBackend (per-operation dispatch to fastest backend)
- [x] ZigBackend (NIF stub with graceful fallback to Elixir)
- [x] Pipeline GenServer (per-peer outbound/inbound frame processing)
- [x] Audio kernel: PCM encode/decode, noise gate, NLMS echo cancellation
- [x] Crypto kernel: AES-256-GCM encrypt/decrypt, SHA-256 hash chains, HKDF
- [x] Neural kernel: spectral gating denoiser, noise classification
- [x] I/O kernel: jitter buffer, packet loss concealment, AIMD adaptive bitrate
- [x] DSP kernel: Cooley-Tukey FFT/IFFT, direct convolution, mixing matrix
- [x] Idris2 ABI definitions (Types.idr, Foreign.idr — dependent type proofs)
- [x] Zig FFI source (audio.zig, dsp.zig, neural.zig — SIMD implementations)
- [x] Wire NIF entry points in nif.zig (10 NIF functions, full term marshalling)
- [x] Compile Zig NIFs (76KB ReleaseFast, Zig 0.15.2)
- [x] Benchmark ElixirBackend vs ZigBackend (echo_cancel 62x, FFT 37x, convolve 28x)
- [x] Update SmartBackend dispatch table from real benchmarks
- [x] Wire Pipeline into Media.Engine (per-peer lifecycle on add/remove)
- [x] mix bench.coprocessor task
- [x] Compression kernel (LZ4 + zstd via zlib + FLAC-style audio archive)
- [x] Server-side recorder (per-peer lossless .barc archive format)
- [x] Audit log compressed export (JSONL + zstd, 12x ratio on JSON)
- [x] Zig NIF for LZ4 compress/decompress (3µs vs 83ms = 26,350x speedup)
- [ ] Wire dsp_mix NIF (complex list-of-lists marshalling)
- [x] panic-attack assail: fixed 3 unsafe pointer casts (serialization)
- [x] proven integration: crypto, password, UUID, email, path via verified bridge
- [x] Ephapax linear analysis: 3 opportunities documented (pipeline, E2EE keys, jitter buffer)
- [ ] RNNoise-style neural model (Phase 2 — replace spectral gating)
- [ ] Compile Zig NIFs in mix compile hook (auto-build on deps.get)
- [ ] Ephapax WASM pipeline module (Phase 2 — linear-typed frame processing)

### VeriSimDB integration (dogfooding)
- [x] Replace PostgreSQL/Ecto with VeriSimDB for user accounts
- [x] Burble.Store GenServer wrapping VeriSimClient
- [x] User validation without Ecto (pure struct + validation)
- [x] Provenance modality for auth audit trail
- [x] Store magic link tokens (temporal modality for expiry)
- [x] Store invite tokens in VeriSimDB (replace in-memory)
- [x] Delete old Ecto migration and Repo stub
- [ ] Audit log queries via VeriSimDB provenance chains
- [ ] Room config persistence (document modality)
- [ ] Server/guild config persistence

## Medium term

### Server hardening
- [ ] Replace HMAC with Ed25519 for Avow/Vext signatures
- [ ] Implement proper Guardian JWT auth (replace Phoenix.Token)
- [ ] Add magic link email sending (currently stub)
- [x] Server-side recording (operator-approved) — Recorder module + .barc format

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
