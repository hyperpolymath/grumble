# Test & Benchmark Requirements

## Current State
- Unit tests: 17 Elixir test files + 2 Zig integration tests — count unknown (cannot run mix test)
- Integration tests: partial (Zig FFI tests, some Elixir integration tests)
- E2E tests: 1 (voice_pipeline_test.exs)
- Benchmarks: 15 benchmark files exist
- panic-attack scan: NEVER RUN (feature dir exists but no report)

## What's Missing
### Point-to-Point (P2P)
#### Server (Elixir — 84 source files, 17 test files)
Tested:
- auth/user_test.exs
- coprocessor/elixir_backend_test.exs
- coprocessor/signal_science_test.exs
- permissions_test.exs
- verification/vext_test.exs
- topology_test.exs
- diagnostics/self_test_test.exs
- groove_test.exs
- rooms/participant_test.exs, room_manager_test.exs, room_test.exs
- security_hardening_test.exs
- bebop/voice_signal_test.exs, room_event_test.exs
- plugs/input_sanitizer_test.exs, rate_limiter_test.exs

UNTESTED (84 source files minus ~17 tested = ~67 untested):
- WebRTC signaling modules
- LMDB buffer management
- PTP (Precision Time Protocol) modules
- Multipath audio routing
- SIP integration
- Admin dashboard modules
- Client connection management
- Channel/topic subscription logic
- Media transcoding pipeline
- Conference management
- Recording/playback

#### Client (ReScript — 43 files)
- ZERO test files

#### Signaling (TypeScript — 55 files)
- ZERO test files

#### FFI (Zig — 14 files)
- 2 integration test files (template-level)

#### Ephapax (6 files)
- ZERO test files

### End-to-End (E2E)
- Full voice call: connect -> join room -> audio -> leave
- Multi-participant conference
- Coprocessor signal processing pipeline
- WebRTC offer/answer/ICE negotiation
- Auth flow: register -> login -> join room -> permissions check
- Admin panel: create room -> configure -> monitor -> close
- Client reconnection and state recovery
- Recording: start -> capture -> stop -> download
- Groove integration: service discovery -> capability exchange

### Aspect Tests
- [ ] Security (WebRTC SRTP enforcement, auth bypass, CSRF, rate limiting effectiveness, SSRF via signaling)
- [ ] Performance (audio latency, concurrent participants, jitter buffer effectiveness)
- [ ] Concurrency (race conditions in room join/leave, participant state synchronization)
- [ ] Error handling (network partition recovery, codec negotiation failure, TURN relay fallback)
- [ ] Accessibility (client UI accessibility — screen reader, keyboard nav for controls)

### Build & Execution
- [ ] mix compile — not verified (version mismatch)
- [ ] mix test — not verified
- [ ] zig build for NIFs — not verified
- [ ] ReScript build for client — not verified
- [ ] Server starts and passes self-test — not verified
- [ ] Self-diagnostic (self_test module exists — verify coverage)

### Benchmarks Needed
- Audio latency measurement (mic-to-speaker)
- Concurrent participant scaling (10, 50, 100, 500)
- Jitter buffer performance under packet loss
- Coprocessor signal processing throughput
- WebRTC ICE candidate gathering time
- LMDB buffer read/write performance
- Verify 15 existing benchmark files actually run

### Self-Tests
- [ ] panic-attack assail on own repo
- [ ] self_test module coverage verification
- [ ] WebRTC connectivity self-check

## Priority
- **HIGH** — Voice communication platform (84 Elixir + 43 ReScript + 55 TypeScript + 14 Zig + 6 Ephapax files) with tests only in the Elixir server layer (~17 test files for 84 source files). The client (43 ReScript files) and signaling (55 TypeScript files) have ZERO tests. For a real-time communication system, the lack of latency testing, reconnection testing, and security testing is especially concerning.

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
