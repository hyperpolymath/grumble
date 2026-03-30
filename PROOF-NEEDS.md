# Proof Requirements

## Current state
- `src/abi/Types.idr` (155 lines) — Core voice/media types
- `src/abi/Foreign.idr` (140 lines) — FFI declarations
- `src/abi/Avow.idr` (174 lines) — Attestation/trust types
- `src/abi/Vext.idr` (173 lines) — Extension types
- `src/abi/Permissions.idr` (232 lines) — Permission model
- `src/interface/abi/Foreign.idr` — References `believe_me` in comments (documenting why it is NOT used)
- No actual `believe_me` usage in production code

## What needs proving
- **Permission model completeness**: Prove `Permissions.idr` capability checks are decidable and that the permission lattice is well-founded
- **Audio buffer linearity**: Prove audio buffers are consumed exactly once (no double-free, no use-after-free in the media pipeline)
- **WebRTC session safety**: Prove session setup/teardown is deadlock-free and resources are released on all termination paths
- **Attestation chain integrity**: Prove `Avow.idr` trust assertions form a valid chain (no circular trust, no trust escalation without evidence)
- **Extension sandboxing**: Prove `Vext.idr` extensions cannot escape their capability boundary
- **Codec negotiation termination**: Prove codec/format negotiation always terminates with a valid selection or explicit rejection

## Recommended prover
- **Idris2** — Already used for ABI; dependent types suit the permission lattice and linear resource proofs

## Priority
- **HIGH** — Burble is a voice platform handling real-time audio streams and user permissions. Buffer safety and permission correctness are critical for both reliability and privacy.
