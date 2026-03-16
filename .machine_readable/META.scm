; SPDX-License-Identifier: PMPL-1.0-or-later
; Burble — Meta Information (machine-readable)

(meta
  (project "burble")
  (license "PMPL-1.0-or-later")
  (license-fallback "MPL-2.0")
  (author "Jonathan D.A. Jewell" "j.d.a.jewell@open.ac.uk")
  (git-author "Jonathan D.A. Jewell" "6759885+hyperpolymath@users.noreply.github.com")

  (architecture-decisions
    (adr-001
      (title "VeriSimDB replaces PostgreSQL")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Dogfooding VeriSimDB. User store is simple (1 table). Exercises Elixir client SDK."))

    (adr-002
      (title "Coprocessor kernel pattern from Axiom.jl")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Abstract backend → dispatch → Zig NIF hot path. Proven pattern with benchmarks."))

    (adr-003
      (title "Guardian JWT replaces Phoenix.Token")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Cross-server verification needed for oligarchic/distributed topologies."))

    (adr-004
      (title "Extension API: core/profiles/extensions")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Burble is commodity substrate for handoff. Real value in bespoke integrations."))

    (adr-005
      (title "Mumble bridge: interop not migration")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Bidirectional relay helps Mumble community. No feature cloning."))

    (adr-006
      (title "Four topology modes")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Monarchic→oligarchic→distributed→serverless progression."))

    (adr-007
      (title "Vext hash chains for text feed integrity")
      (status "accepted")
      (date "2026-03-16")
      (rationale "Mathematical proof of feed integrity. First Vext deployment.")))

  (development-practices
    (container-policy "Chainguard base images, Containerfile not Dockerfile, Podman not Docker")
    (testing "ExUnit, mix test --no-start for unit tests without VeriSimDB")
    (benchmarking "mix bench.coprocessor for kernel performance comparison")
    (security "panic-attack assail, proven SafeCrypto bridge, BLAKE2B→SHA256 migration")
    (pre-commit "panic-attack assail on Zig code")))
