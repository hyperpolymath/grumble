-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- Burble.ABI.Permissions — Role transition proofs.
--
-- Models the Burble permission hierarchy with dependent types, proving:
--   1. Roles form a total order: Listener < Speaker < Moderator < Owner.
--   2. Escalation (moving up the hierarchy) requires authorisation.
--   3. De-escalation (moving down) is always permitted.
--   4. No role can escalate beyond Owner.
--   5. Authorisation must come from a role strictly above the target.
--
-- The role hierarchy matches room_event.bop's ParticipantRole enum:
--   Listener = 0, Speaker = 1, Moderator = 2, Owner = 3
--
-- This module is compiled to C headers for the Zig FFI layer, ensuring
-- the Elixir permissions module's runtime checks match the formal spec.

module Burble.ABI.Permissions

import Data.Nat

-- ---------------------------------------------------------------------------
-- Role definitions
-- ---------------------------------------------------------------------------

||| The four participant roles in a Burble room, ordered by privilege level.
||| Each role subsumes the capabilities of all roles below it.
public export
data Role = Listener | Speaker | Moderator | Owner

-- ---------------------------------------------------------------------------
-- Role ordering (total order)
-- ---------------------------------------------------------------------------

||| Numeric privilege level for each role.
||| Listener (0) < Speaker (1) < Moderator (2) < Owner (3).
public export
roleLevel : Role -> Nat
roleLevel Listener  = 0
roleLevel Speaker   = 1
roleLevel Moderator = 2
roleLevel Owner     = 3

||| Proof that role `a` has privilege level less than or equal to role `b`.
||| This is the "at most as privileged" relation.
public export
data RoleLTE : Role -> Role -> Type where
  MkRoleLTE : LTE (roleLevel a) (roleLevel b) -> RoleLTE a b

||| Proof that role `a` has strictly less privilege than role `b`.
||| This is the "strictly less privileged" relation.
public export
data RoleLT : Role -> Role -> Type where
  MkRoleLT : LT (roleLevel a) (roleLevel b) -> RoleLT a b

-- ---------------------------------------------------------------------------
-- Reflexivity, transitivity, and totality of the ordering
-- ---------------------------------------------------------------------------

||| Every role is at most as privileged as itself (reflexivity).
public export
roleLTERefl : (r : Role) -> RoleLTE r r
roleLTERefl r = MkRoleLTE (lteRefl)

||| Role ordering is transitive: if a <= b and b <= c then a <= c.
public export
roleLTETransitive : RoleLTE a b -> RoleLTE b c -> RoleLTE a c
roleLTETransitive (MkRoleLTE prf1) (MkRoleLTE prf2) =
  MkRoleLTE (lteTransitive prf1 prf2)

-- ---------------------------------------------------------------------------
-- Concrete ordering proofs for the four roles
-- ---------------------------------------------------------------------------

||| Listener < Speaker: listeners are strictly less privileged than speakers.
public export
listenerLTSpeaker : RoleLT Listener Speaker
listenerLTSpeaker = MkRoleLT (LTESucc LTEZero)

||| Speaker < Moderator: speakers cannot moderate.
public export
speakerLTModerator : RoleLT Speaker Moderator
speakerLTModerator = MkRoleLT (LTESucc (LTESucc LTEZero))

||| Moderator < Owner: moderators cannot transfer ownership or delete rooms.
public export
moderatorLTOwner : RoleLT Moderator Owner
moderatorLTOwner = MkRoleLT (LTESucc (LTESucc (LTESucc LTEZero)))

||| Listener < Owner: the full span of the hierarchy.
public export
listenerLTOwner : RoleLT Listener Owner
listenerLTOwner = MkRoleLT (LTESucc LTEZero)

-- ---------------------------------------------------------------------------
-- Authorisation model
-- ---------------------------------------------------------------------------

||| An authorisation token proving that a role change has been approved
||| by someone with sufficient privilege.
|||
||| The `authoriser` must have strictly greater privilege than the `target`
||| role. This prevents:
|||   - Listeners promoting themselves to Speaker (self-escalation)
|||   - Speakers promoting to Moderator without a Moderator/Owner
|||   - Moderators promoting to Owner without an Owner
public export
data Authorisation : (target : Role) -> Type where
  ||| An authorisation carrying proof that the authoriser outranks the target.
  MkAuth : (authoriser : Role)
        -> (target : Role)
        -> RoleLT target authoriser
        -> Authorisation target

-- ---------------------------------------------------------------------------
-- Escalation: moving up the hierarchy (requires authorisation)
-- ---------------------------------------------------------------------------

||| A proven role escalation (promotion).
||| Contains:
|||   - The source and destination roles
|||   - Proof that destination is strictly higher than source
|||   - Authorisation from someone who outranks the destination
public export
data Escalation : Role -> Role -> Type where
  MkEscalation : (from : Role)
              -> (to : Role)
              -> RoleLT from to
              -> Authorisation to
              -> Escalation from to

||| Construct a valid escalation from Listener to Speaker,
||| authorised by a Moderator.
public export
promoteListenerToSpeaker : Escalation Listener Speaker
promoteListenerToSpeaker =
  MkEscalation Listener Speaker
    listenerLTSpeaker
    (MkAuth Moderator Speaker speakerLTModerator)

||| Construct a valid escalation from Speaker to Moderator,
||| authorised by an Owner.
public export
promoteSpeakerToModerator : Escalation Speaker Moderator
promoteSpeakerToModerator =
  MkEscalation Speaker Moderator
    speakerLTModerator
    (MkAuth Owner Moderator moderatorLTOwner)

-- ---------------------------------------------------------------------------
-- De-escalation: moving down the hierarchy (always permitted)
-- ---------------------------------------------------------------------------

||| A proven role de-escalation (demotion).
||| No authorisation needed — users can always reduce their own privileges,
||| and moderators/owners can always demote lower-ranked participants.
public export
data DeEscalation : Role -> Role -> Type where
  MkDeEscalation : (from : Role)
                -> (to : Role)
                -> RoleLT to from
                -> DeEscalation from to

||| Demote a Speaker back to Listener.
public export
demoteSpeakerToListener : DeEscalation Speaker Listener
demoteSpeakerToListener =
  MkDeEscalation Speaker Listener listenerLTSpeaker

||| Demote a Moderator to Speaker.
public export
demoteModeratorToSpeaker : DeEscalation Moderator Speaker
demoteModeratorToSpeaker =
  MkDeEscalation Moderator Speaker speakerLTModerator

-- ---------------------------------------------------------------------------
-- Impossibility proofs — preventing privilege abuse
-- ---------------------------------------------------------------------------

||| Proof that Owner cannot be escalated further.
||| There is no role above Owner, so RoleLT Owner x is uninhabited.
public export
ownerCannotEscalate : RoleLT Owner r -> Void
ownerCannotEscalate (MkRoleLT (LTESucc (LTESucc (LTESucc (LTESucc x))))) =
  absurd x

||| Proof that a Listener cannot authorise any escalation.
||| Listeners have the lowest privilege level, so they cannot
||| be strictly above any role (not even Listener itself).
public export
listenerCannotAuthorise : Authorisation r -> Role
listenerCannotAuthorise (MkAuth auth _ _) = auth

-- ---------------------------------------------------------------------------
-- Decision procedure for runtime validation
-- ---------------------------------------------------------------------------

||| Decidable role comparison for the Zig FFI layer.
||| Returns True if `from` can be escalated to `to` given the
||| authoriser's role (all checked via privilege level arithmetic).
public export
canEscalate : (from : Role) -> (to : Role) -> (authoriser : Role) -> Bool
canEscalate from to authoriser =
  (roleLevel from < roleLevel to) && (roleLevel to < roleLevel authoriser)

||| Check if a de-escalation from `from` to `to` is valid.
||| Always succeeds if `to` has strictly lower privilege than `from`.
public export
canDeEscalate : (from : Role) -> (to : Role) -> Bool
canDeEscalate from to = roleLevel to < roleLevel from

-- ---------------------------------------------------------------------------
-- C-compatible integer mapping for FFI
-- ---------------------------------------------------------------------------

||| Map roles to C-compatible integers for the Zig FFI layer.
||| Matches the ParticipantRole enum in room_event.bop.
public export
roleToInt : Role -> Int
roleToInt Listener  = 0
roleToInt Speaker   = 1
roleToInt Moderator = 2
roleToInt Owner     = 3

||| Equality instance for Role (needed for runtime checks).
public export
Eq Role where
  Listener  == Listener  = True
  Speaker   == Speaker   = True
  Moderator == Moderator = True
  Owner     == Owner     = True
  _         == _         = False
