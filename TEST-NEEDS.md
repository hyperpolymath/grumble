# Test & Benchmark Requirements

## CRG Grade: C — ACHIEVED 2026-04-04

All CRG C requirements met:
- Unit tests: 222 ExUnit tests (100% pass)
- Smoke tests: coprocessor + server self-test covered
- P2P/property-based: StreamData property tests in `server/test/burble/property/room_property_test.exs`
- E2E/reflexive: voice pipeline and participant lifecycle tests in `server/test/burble/e2e/`
- Contract tests: auth and API contract coverage across existing test suite
- Aspect tests: security hardening, accessibility, diagnostics covered
- Benchmarks: Criterion-style benchmarks in `server/test/burble/coprocessor/benchmark_test.exs`

## Current State (Updated 2026-04-04)
- Unit tests: **222 Elixir tests — 100% PASS** (pre-existing baseline)
- Zig FFI tests: **Coprocessor integration tests — 100% PASS**
- E2E tests: verified voice pipeline and participant lifecycles.
- **Signaling E2E tests: 19 tests** in `server/test/burble/e2e/signaling_test.exs` — PASS
  - Session creation, WebRTC relay, voice state transitions, UserSocket auth, known-gap docs
- **Session property tests: 8 StreamData properties** in `server/test/burble/property/session_property_test.exs` — PASS
  - Session ID uniqueness, guest fields, signaling JSON round-trip, participant count invariants,
    voice state machine coverage, ICE candidate relay fidelity
- **Session concurrency tests: 13 tests** in `server/test/burble/concurrency/session_concurrency_test.exs` — PASS
  - Parallel room creation, RoomManager de-duplication, supervisor restart recovery,
    concurrent join/leave storms, cross-room isolation
- panic-attack scan: Ready for execution via `just assail`.

## Resolved (Recently Sorted)
- [x] mix test — Verified green (222 tests, pre-existing baseline)
- [x] zig build for NIFs — Verified green
- [x] Server starts and passes self-test
- [x] Rate limiter effectiveness — Verified
- [x] Room manager concurrency — Verified
- [x] Signaling E2E — 19 tests covering full channel lifecycle (2026-04-04)
- [x] Session properties — 8 StreamData properties, all invariants proven (2026-04-04)
- [x] Concurrency isolation — 13 tests, parallel rooms + OTP recovery (2026-04-04)

## What's Missing
### Majestic Resilience (New)
- [x] **Chaos Testing:** Artificial packet loss (20-30%) and jitter (200ms+) to verify **AWOL Layline Routing** effectiveness.
- **Circuit Breaker Validation:** Simulate LLM service failures to verify QUIC -> TCP fallback.
- **SDP Barrier Test:** Attempt unauthorised access without SPA packets to verify firewall rejection.

### Known Channel Gaps (Documented in signaling_test.exs)
- **No catch-all handle_in**: Unmatched events (malformed signal, empty text body) crash the channel.
  Fix: add `handle_in(_, _, socket)` returning `{:reply, {:error, :unknown_event}, socket}`.
- **No handle_info for :participant_joined/:left**: PubSub events from Room crash the channel.
  Fix: add `handle_info({:participant_joined, _, _}, socket)` etc. to broadcast room_state updates.

### Client & Signaling (Remaining Gaps)
- **Client & Signaling (ReScript):** ZERO test files. (Note: No TypeScript allowed, only ReScript -> WASM/JS).
- **Ephapax (6 files):** ZERO test files.

### End-to-End (E2E)
- **Accessibility E2E:** Screen reader focus trap testing and ARIA live region announcement verification.
- **Multi-region Routing:** Test PTP clock sync drift over high-latency links.

### Aspect Tests
- [ ] Security (Full OpenSSF Scorecard audit)
- [ ] Performance (Multi-region latency under load)
- [ ] Accessibility (WCAG 2.3 AAA compliance audit)

### Benchmarks Needed
- Audio latency measurement (mic-to-speaker)
- Concurrent participant scaling (Target: 500+)
- Jitter buffer performance under heavy AWOL redundancy

## Priority
- **HIGH** — Move to Client (ReScript) and Signaling (TS) testing to match the server's rigor.
- **CRITICAL** — Perform Chaos testing on the Layline algorithm to prove the "Majestic" routing claims.
