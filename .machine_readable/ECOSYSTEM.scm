; SPDX-License-Identifier: PMPL-1.0-or-later
; Burble — Ecosystem Position (machine-readable)

(ecosystem
  (version "1.0")
  (name "burble")
  (type "application")
  (purpose "Voice-first communications platform with formal verification")

  (position-in-ecosystem
    (role "Consumer of VeriSimDB, proven, Avow, Vext. Provider of voice to IDApTIK, PanLL.")
    (maturity "alpha")
    (audience "Self-hosters, game developers, workspace tool builders"))

  (related-projects
    (dependency "verisimdb"
      (relationship "database")
      (type "runtime-dependency")
      (notes "Dogfooding — first VeriSimDB consumer"))

    (dependency "proven"
      (relationship "safety-library")
      (type "runtime-dependency")
      (notes "SafeCrypto, SafePassword, SafeUuid, SafeEmail, SafePath"))

    (dependency "avow-protocol"
      (relationship "consent-verification")
      (type "protocol-implementation")
      (notes "First real-world Avow deployment beyond email"))

    (dependency "vext-protocol"
      (relationship "feed-integrity")
      (type "protocol-implementation")
      (notes "First Vext deployment — text feed hash chains"))

    (consumer "idaptik"
      (relationship "voice-integration")
      (type "embedded-client")
      (notes "IDApTIKVoice extension, VoiceBridge, spatial audio"))

    (consumer "panll"
      (relationship "voice-integration")
      (type "embedded-client")
      (notes "PanLLVoice extension, BurbleEngine, PanelBus events"))

    (sibling "stapeln"
      (relationship "container-platform")
      (type "deployment-target")
      (notes "Containerfiles for Svalinn/Vordr/Selur-compose"))

    (sibling "axiom-jl"
      (relationship "architecture-inspiration")
      (type "pattern-source")
      (notes "Coprocessor backend pattern based on Axiom.jl"))

    (interop "mumble"
      (relationship "voice-bridge")
      (type "bidirectional-relay")
      (notes "Burble↔Mumble bridge, interop not migration"))))
