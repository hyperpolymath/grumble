; SPDX-License-Identifier: PMPL-1.0-or-later
; Burble — Project State (machine-readable)
; Updated: 2026-03-16

(state
  (metadata
    (project "burble")
    (version "0.1.0")
    (status "alpha")
    (last-updated "2026-03-16"))

  (project-context
    (description "Voice-first communications platform. Self-hostable, E2EE-capable, formally verified.")
    (primary-language "elixir")
    (secondary-languages ("rescript" "zig" "idris2"))
    (framework "phoenix")
    (database "verisimdb")
    (license "PMPL-1.0-or-later"))

  (current-position
    (phase "alpha")
    (completion-percentage 70)
    (blocking-items
      ("WebRTC Membrane SFU integration — engine_pid is nil, no real audio"
       "TURN server setup — privacy modes defined but not functional"
       "Web client WebRTC PeerConnection — simulated"
       "Ed25519 signatures — HMAC placeholder in Avow/Vext"))
    (recently-completed
      ("VeriSimDB replaces PostgreSQL"
       "Coprocessor kernel system (6 domains, 24 ops, Zig NIFs)"
       "Guardian JWT auth with refresh rotation"
       "Vext hash chain integrity wired into NNTPSBackend"
       "Avow consent attestations wired into RoomChannel"
       "Permissions enforced in RoomChannel"
       "Embeddable client library with extension API"
       "IDApTIK + PanLL integration modules"
       "Mumble bidirectional bridge"
       "Server-side recording with lossless compression"
       "49 tests passing")))

  (route-to-mvp
    (milestone "v1.0-alpha"
      (items
        ("Wire Membrane SFU into Media.Engine"
         "Wire ex_webrtc for real WebRTC negotiation"
         "TURN server (ex_turn or coturn)"
         "Client-side WebRTC PeerConnection"
         "Ed25519 for Avow/Vext"
         "Containerfiles + podman-compose"
         "README.adoc with setup instructions")))
    (milestone "v1.0-beta"
      (items
        ("End-to-end voice test (2 browsers)"
         "Load test (10+ peers)"
         "Security audit"
         "Production deployment guide")))
    (milestone "v1.0"
      (items
        ("Hex.pm package"
         "JSR/deno.land package for client lib"
         "GitHub release with binaries"))))

  (critical-next-actions
    ("Membrane SFU integration is THE blocker — everything else is ready"
     "Run panic-attack on Elixir code (only Zig was scanned)"
     "Build proven NIF for test environment")))
