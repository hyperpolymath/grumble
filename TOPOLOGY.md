<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# TOPOLOGY.md — Burble

## Purpose

Burble is a self-hostable voice communications platform delivering sub-10ms latency WebRTC audio with IEEE 1588 PTP precision timing. It targets privacy-conscious teams and individuals who need Mumble-quality audio with browser-based joining and zero-friction setup. The platform is built on an Elixir/Phoenix control plane with Zig SIMD NIFs for the media hot-path, E2EE optional, no telemetry.

## Module Map

```
burble/
├── server/                        # Elixir/Phoenix control plane
│   └── lib/
│       ├── burble/
│       │   ├── application.ex     # OTP application entry
│       │   ├── rooms/             # Room lifecycle (room.ex, room_manager.ex, participant.ex, instant_connect.ex)
│       │   ├── media/             # Media engine (engine.ex, peer.ex, e2ee.ex, pipewire.ex, lmdb_playout.ex)
│       │   ├── transport/         # Transport layer (multipath.ex, quic.ex, rtsp.ex)
│       │   ├── auth/              # Authentication and sessions
│       │   ├── permissions/       # Room and user permissions
│       │   ├── groove/            # Groove IPC protocol integration
│       │   ├── network/           # Network topology and routing
│       │   ├── timing/            # IEEE 1588 PTP precision timing
│       │   ├── coprocessor/       # Axiom/VeriSimDB coprocessors
│       │   ├── store/             # Persistent state (store.ex)
│       │   ├── topology/          # Room topology management
│       │   ├── security/          # Security hardening
│       │   ├── moderation/        # Content moderation
│       │   ├── bebop/             # Bebop binary serialization
│       │   ├── llm/               # LLM integration (llm.ex)
│       │   └── bridges/           # External bridge adapters
│       └── burble_web/
│           ├── router.ex          # Phoenix router
│           ├── channels/          # WebSocket channels
│           ├── controllers/       # HTTP controllers
│           └── plugs/             # Request plugs
├── signaling/                     # WebRTC signaling relay (JS + ReScript)
│   ├── relay.js                   # Signaling relay server
│   └── Relay.res                  # ReScript relay bindings
├── src/                           # Idris2 ABI definitions
│   ├── ABI.idr                    # Top-level ABI
│   ├── core/                      # Core type definitions
│   ├── bridges/                   # Bridge ABI contracts
│   └── aspects/                   # Cross-cutting ABI aspects
├── ffi/zig/                       # Zig FFI (SIMD audio, LMDB NIFs)
├── api/                           # REST API (v-lang connectors)
├── client/                        # Browser/native client SDK
├── admin/                         # Admin dashboard
├── container/                     # Containerfile and compose
└── verification/                  # Formal verification proofs
```

## Data Flow

```
[Browser/Client]
      │  WebRTC + WebSocket
      ▼
[signaling/relay.js] ──► [burble_web/channels/] ──► [rooms/room_manager.ex]
                                                              │
                    ┌─────────────────────────────────────────┘
                    │
                    ▼
          [media/engine.ex] ──► [ffi/zig SIMD NIFs] ──► [transport/multipath.ex]
                    │                                           │
                    ▼                                           ▼
          [media/lmdb_playout.ex]                   [transport/quic.ex]
          (LMDB ring buffer)                         (QUIC + RTSP egress)
                    │
                    ▼
          [timing/] (IEEE 1588 PTP)
                    │
                    ▼
          [store/store.ex] ──► [VeriSimDB coprocessor]
```
