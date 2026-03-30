-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- Burble.ABI.Avow — Consent state machine with formal proofs.
--
-- Models the Avow consent lifecycle as a dependent type, proving:
--   1. Only valid state transitions can occur.
--   2. Consent cannot skip states (requested -> active is invalid).
--   3. Revocation is final — no transitions from Revoked.
--   4. Every reachable state is a valid consent state.
--
-- The consent state machine:
--
--   Requested ──confirm──> Confirmed ──activate──> Active ──revoke──> Revoked
--       │                                            │
--       └──────────────revoke─────────────────────────┘
--
-- This module is compiled to C headers for the Zig FFI layer, ensuring
-- that consent transitions in the Elixir control plane match the
-- formally verified specification.

module Burble.ABI.Avow

-- ---------------------------------------------------------------------------
-- Consent states
-- ---------------------------------------------------------------------------

||| The four states of an Avow consent lifecycle.
||| Each state represents a distinct legal/technical condition:
|||   - Requested: user has been asked for consent but hasn't responded
|||   - Confirmed: user has affirmed consent (e.g., clicked "I agree")
|||   - Active: consent is in effect (recording, processing, etc.)
|||   - Revoked: consent has been withdrawn (must stop all processing)
public export
data ConsentState = Requested | Confirmed | Active | Revoked

-- ---------------------------------------------------------------------------
-- Valid transitions (indexed by source and target states)
-- ---------------------------------------------------------------------------

||| A proof that a transition from state `from` to state `to` is valid.
||| Only the four transitions in the state diagram are constructible.
||| This is the core safety property: if you have a `ValidTransition`,
||| the transition is legal.
public export
data ValidTransition : ConsentState -> ConsentState -> Type where
  ||| Requested -> Confirmed: user has affirmed consent.
  Confirm  : ValidTransition Requested Confirmed
  ||| Confirmed -> Active: system activates the consent.
  Activate : ValidTransition Confirmed Active
  ||| Active -> Revoked: user or system withdraws consent.
  RevokeActive : ValidTransition Active Revoked
  ||| Requested -> Revoked: user rejects the consent request.
  RevokeRequested : ValidTransition Requested Revoked

-- ---------------------------------------------------------------------------
-- Impossibility proofs — no invalid transitions exist
-- ---------------------------------------------------------------------------

||| Proof that there is no valid transition from Revoked to any state.
||| Revocation is terminal — once consent is revoked, it cannot be reinstated.
||| This prevents the "zombie consent" bug where revoked consent is reactivated.
public export
revokedIsTerminal : ValidTransition Revoked to -> Void
revokedIsTerminal _ impossible

||| Proof that Requested -> Active is not a valid transition.
||| Consent must be Confirmed before it can be Activated — no shortcuts.
||| This prevents the "skip consent" vulnerability.
public export
noSkipToActive : ValidTransition Requested Active -> Void
noSkipToActive _ impossible

||| Proof that Confirmed -> Requested is not a valid transition.
||| Once confirmed, consent cannot regress to a pending state.
public export
noConfirmedToRequested : ValidTransition Confirmed Requested -> Void
noConfirmedToRequested _ impossible

||| Proof that Active -> Confirmed is not a valid transition.
||| Active consent goes to Revoked, never back to Confirmed.
public export
noActiveToConfirmed : ValidTransition Active Confirmed -> Void
noActiveToConfirmed _ impossible

||| Proof that Active -> Requested is not a valid transition.
public export
noActiveToRequested : ValidTransition Active Requested -> Void
noActiveToRequested _ impossible

||| Proof that Confirmed -> Revoked requires going through Active.
||| (Actually, we DO NOT allow Confirmed -> Revoked directly. If the user
||| wants to revoke after confirming but before activation, they must wait
||| for activation first. This is a design choice for auditability.)
public export
noConfirmedToRevoked : ValidTransition Confirmed Revoked -> Void
noConfirmedToRevoked _ impossible

-- ---------------------------------------------------------------------------
-- Consent chain: a sequence of valid transitions
-- ---------------------------------------------------------------------------

||| A chain of consent state transitions, each proven valid.
||| The chain tracks the full consent lifecycle from any starting state.
||| This is used to verify that an entire consent history is legal.
public export
data ConsentChain : ConsentState -> ConsentState -> Type where
  ||| Zero transitions — already at the target state.
  Here : ConsentChain s s
  ||| One valid transition followed by more transitions.
  Step : ValidTransition s mid -> ConsentChain mid t -> ConsentChain s t

||| The canonical "happy path": Requested -> Confirmed -> Active.
||| This is the most common consent lifecycle.
public export
happyPath : ConsentChain Requested Active
happyPath = Step Confirm (Step Activate Here)

||| Full lifecycle through to revocation: Requested -> Confirmed -> Active -> Revoked.
public export
fullLifecycle : ConsentChain Requested Revoked
fullLifecycle = Step Confirm (Step Activate (Step RevokeActive Here))

||| Early rejection: user declines the consent request.
public export
earlyRejection : ConsentChain Requested Revoked
earlyRejection = Step RevokeRequested Here

-- ---------------------------------------------------------------------------
-- Chain properties
-- ---------------------------------------------------------------------------

||| Proof that any chain ending in Revoked cannot be extended further.
||| This is the chain-level version of revokedIsTerminal.
public export
chainTerminatesAtRevoked : ConsentChain Revoked next -> next = Revoked
chainTerminatesAtRevoked Here = Refl
chainTerminatesAtRevoked (Step t _) = absurd (revokedIsTerminal t)

-- ---------------------------------------------------------------------------
-- Decision procedure for transition validity
-- ---------------------------------------------------------------------------

||| Decidable equality on ConsentState, needed for runtime validation.
public export
Eq ConsentState where
  Requested == Requested = True
  Confirmed == Confirmed = True
  Active    == Active    = True
  Revoked   == Revoked   = True
  _         == _         = False

||| Attempt to construct a valid transition at runtime.
||| Returns `Just` the proof if the transition is valid, `Nothing` if not.
||| Used by the Zig FFI to validate transitions from the Elixir side.
public export
tryTransition : (from : ConsentState) -> (to : ConsentState)
             -> Maybe (ValidTransition from to)
tryTransition Requested Confirmed = Just Confirm
tryTransition Confirmed Active    = Just Activate
tryTransition Active    Revoked   = Just RevokeActive
tryTransition Requested Revoked   = Just RevokeRequested
tryTransition _         _         = Nothing

-- ---------------------------------------------------------------------------
-- C-compatible integer mapping for FFI
-- ---------------------------------------------------------------------------

||| Map consent states to C-compatible integers for the Zig FFI layer.
public export
consentStateToInt : ConsentState -> Int
consentStateToInt Requested = 0
consentStateToInt Confirmed = 1
consentStateToInt Active    = 2
consentStateToInt Revoked   = 3
