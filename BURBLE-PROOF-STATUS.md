<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
# Burble Proof Status

**Short version.** All six Idris2 ABI proof modules compile and type-check. See `PROOF-NEEDS.md` for the current proof inventory, and `STATE.a2ml` for any in-progress work.

## Current ABI proofs (all compile)

| Module | File |
|---|---|
| Types | `src/Burble/ABI/Types.idr` |
| Permissions | `src/Burble/ABI/Permissions.idr` |
| Avow (attestation chain non-circularity) | `src/Burble/ABI/Avow.idr` |
| Vext (hash chain + capability subsumption) | `src/Burble/ABI/Vext.idr` |
| MediaPipeline (linear buffer consumption) | `src/Burble/ABI/MediaPipeline.idr` |
| WebRTCSignaling (JSEP state machine) | `src/Burble/ABI/WebRTCSignaling.idr` |

## Dangerous-pattern debt

- 1 `postulate` in `MediaPipeline.idr` (`resampleFrame` — documented Zig FFI migration target to `burble_resample`)
- 0 `believe_me`, 0 `assert_total`

## Proof gaps (enforcement, not typecheck)

These modules **compile** but their *runtime enforcement* is incomplete — see `STATE.a2ml [blockers-and-issues]`:

- **Avow** — `server/lib/burble/verification/avow.ex` is data-type-only. No dependent-type verification at runtime. Phase 1 replaces with hash-chain audit log + property test.
- **LLM** — no `LLM.idr` proof of frame protocol well-formedness. Phase 2 target.
- **Timing** — no `Timing.idr` proof of best-source monotonicity. Phase 4 target.

## History

The older, longer version of this file described compilation issues (module name mismatches, master ABI module not building). All of those are resolved — `src/ABI.idr` compiles and re-exports the six modules above. The stale doc was collapsed 2026-04-16 as part of Phase 0 scrub-baseline.
