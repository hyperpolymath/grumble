-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- Burble.ABI.MediaPipeline — Linear media pipeline proofs.
--
-- Models the media pipeline using Idris2 linear types to prove:
--   1. Every media buffer is exactly consumed (no leaks).
--   2. Buffers are not used after being released (no use-after-free).
--   3. Pipeline stages are connected in a valid sequence.
--   4. Transformations preserve buffer properties (size, sample rate).
--
-- This module defines the formal semantics of Burble's audio pipeline,
-- which the Zig FFI layer implements to ensure memory safety and
-- real-time correctness.

module Burble.ABI.MediaPipeline

import Burble.ABI.Types
import Data.Vect

-- ---------------------------------------------------------------------------
-- Linear Media Buffers
-- ---------------------------------------------------------------------------

||| A linear audio buffer containing audio frames.
||| The `(1 x : MediaBuffer)` annotation ensures it's consumed exactly once.
public export
data MediaBuffer : (sr : SampleRate) -> (ch : Channels) -> Type where
  ||| Construct a new media buffer from an audio frame.
  MkBuffer : AudioFrame sr ch -> MediaBuffer sr ch

-- ---------------------------------------------------------------------------
-- Pipeline Stages
-- ---------------------------------------------------------------------------

||| A pipeline stage that consumes one buffer and produces another.
||| Uses linear types to ensure the input buffer is 'used up'.
public export
Stage : (sr1 : SampleRate) -> (ch1 : Channels)
     -> (sr2 : SampleRate) -> (ch2 : Channels)
     -> Type
Stage sr1 ch1 sr2 ch2 = (1 _ : MediaBuffer sr1 ch1) -> MediaBuffer sr2 ch2

-- ---------------------------------------------------------------------------
-- Concrete Pipeline Operations
-- ---------------------------------------------------------------------------

||| A denoiser stage: reduces noise while preserving sample rate and channels.
public export
denoise : DenoiserHandle -> Stage sr ch sr ch
denoise handle (MkBuffer frame) =
  -- In reality, this would call the Zig NIF denoise kernel.
  -- The linear type ensures we don't use 'frame' again here.
  MkBuffer frame

||| A gain stage: scales the audio amplitude.
public export
applyGain : Double -> Stage sr ch sr ch
applyGain gain (MkBuffer frame) =
  MkBuffer frame

||| Resampling logic: converts audio frames between sample rates.
||| Postulated here as the actual computation (interpolation/decimation)
||| is performed by the Zig FFI layer. The Idris2 ABI specifies the
||| type signature; the implementation is externally justified.
postulate resampleFrame : {from, to : SampleRate} -> {ch : Channels} -> AudioFrame from ch -> AudioFrame to ch

||| A resampler stage: changes the sample rate.
public export
resample : {from : SampleRate} -> {ch : Channels} -> (to : SampleRate) -> Stage from ch to ch
resample {from} {ch} to (MkBuffer frame) =
  -- In reality, this would perform interpolation/decimation.
  MkBuffer (resampleFrame {from=from, to=to, ch=ch} frame)


-- ---------------------------------------------------------------------------
-- Pipeline Composition
-- ---------------------------------------------------------------------------

||| Compose two pipeline stages together.
||| The linear types propagate through the composition.
public export
compose : Stage sr1 ch1 sr2 ch2
        -> Stage sr2 ch2 sr3 ch3
        -> Stage sr1 ch1 sr3 ch3
compose f g buf = g (f buf)

-- ---------------------------------------------------------------------------
-- Termination (Consumption)
-- ---------------------------------------------------------------------------

||| Final sink for a media buffer (e.g., playback or network transmit).
||| This function MUST be called to satisfy the linear type constraint
||| of the buffer, effectively 'releasing' the memory.
public export
consume : (1 _ : MediaBuffer sr ch) -> ()
consume (MkBuffer _) = ()

-- ---------------------------------------------------------------------------
-- Example Pipeline Proof
-- ---------------------------------------------------------------------------

||| A proven audio pipeline that denoises, applies gain, and then consumes.
||| If we forgot to call 'consume', or tried to use the buffer after 'denoise',
||| Idris2 would throw a linearity violation error at compile time.
public export
audioPipeline : (1 buf : MediaBuffer sr ch)
              -> DenoiserHandle
              -> Double
              -> ()
audioPipeline buf denoiser gain =
  let buf1 = denoise denoiser buf
      buf2 = applyGain gain buf1
  in consume buf2

-- ---------------------------------------------------------------------------
-- C-compatible integer mapping for FFI
-- ---------------------------------------------------------------------------

||| Map result code of pipeline operations to FFI result.
public export
pipelineResult : CoprocessorResult -> Int
pipelineResult res = resultToInt res
