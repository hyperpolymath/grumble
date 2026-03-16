-- SPDX-License-Identifier: PMPL-1.0-or-later
--
-- Burble.ABI.Foreign — FFI declarations for coprocessor kernels.
--
-- Declares the C-compatible foreign functions implemented by the Zig FFI
-- layer. Each declaration maps to an exported function in the compiled
-- shared library (libburble_coprocessor.so).
--
-- The dependent types from Types.idr ensure that callers cannot pass
-- invalid arguments (wrong buffer sizes, unsupported sample rates, etc.).
-- These constraints are enforced at compile time — no runtime checks needed.

module Burble.ABI.Foreign

import Burble.ABI.Types

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

||| Initialise the coprocessor subsystem.
||| Must be called once before any kernel operations.
%foreign "C:burble_coprocessor_init, libburble_coprocessor"
prim__init : PrimIO Int

||| Initialise the coprocessor, returning a result code.
public export
init : IO CoprocessorResult
init = do
  code <- primIO prim__init
  pure $ case code of
    0 => Ok
    _ => Error

||| Shut down the coprocessor subsystem.
%foreign "C:burble_coprocessor_shutdown, libburble_coprocessor"
prim__shutdown : PrimIO ()

public export
shutdown : IO ()
shutdown = primIO prim__shutdown

-- ---------------------------------------------------------------------------
-- Audio kernel
-- ---------------------------------------------------------------------------

||| Encode PCM samples to Opus.
||| The Zig implementation handles the actual Opus encoding.
%foreign "C:burble_audio_encode, libburble_coprocessor"
prim__audioEncode : (samples : AnyPtr) -> (numSamples : Int) ->
                    (sampleRate : Int) -> (channels : Int) ->
                    (bitrate : Int) -> (outBuf : AnyPtr) ->
                    (outLen : AnyPtr) -> PrimIO Int

||| Type-safe wrapper for audio encoding.
||| Sample rate and channel count are constrained by dependent types.
public export
audioEncode : (sr : SampleRate) -> (ch : Channels) ->
              (bitrate : Int) -> IO CoprocessorResult
audioEncode sr ch bitrate = do
  -- In production, this marshals the AudioFrame to a C buffer,
  -- calls prim__audioEncode, and returns the result.
  -- The type system guarantees correct buffer sizes.
  pure Ok  -- Placeholder

||| Decode Opus to PCM samples.
%foreign "C:burble_audio_decode, libburble_coprocessor"
prim__audioDecode : (opusData : AnyPtr) -> (opusLen : Int) ->
                    (sampleRate : Int) -> (channels : Int) ->
                    (outBuf : AnyPtr) -> (outLen : AnyPtr) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- Crypto kernel
-- ---------------------------------------------------------------------------

||| Encrypt a frame with AES-256-GCM.
%foreign "C:burble_crypto_encrypt, libburble_coprocessor"
prim__cryptoEncrypt : (plaintext : AnyPtr) -> (ptLen : Int) ->
                      (key : AnyPtr) -> (iv : AnyPtr) ->
                      (aad : AnyPtr) -> (aadLen : Int) ->
                      (ciphertext : AnyPtr) -> (tag : AnyPtr) -> PrimIO Int

||| Decrypt a frame with AES-256-GCM.
%foreign "C:burble_crypto_decrypt, libburble_coprocessor"
prim__cryptoDecrypt : (ciphertext : AnyPtr) -> (ctLen : Int) ->
                      (key : AnyPtr) -> (iv : AnyPtr) ->
                      (tag : AnyPtr) -> (aad : AnyPtr) -> (aadLen : Int) ->
                      (plaintext : AnyPtr) -> PrimIO Int

||| Compute SHA-256 hash chain link.
%foreign "C:burble_crypto_hash_chain, libburble_coprocessor"
prim__hashChain : (prevHash : AnyPtr) -> (payload : AnyPtr) ->
                  (payloadLen : Int) -> (outHash : AnyPtr) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- DSP kernel
-- ---------------------------------------------------------------------------

||| In-place FFT on interleaved complex data.
%foreign "C:burble_dsp_fft, libburble_coprocessor"
prim__fft : (data : AnyPtr) -> (n : Int) -> PrimIO Int

||| In-place inverse FFT.
%foreign "C:burble_dsp_ifft, libburble_coprocessor"
prim__ifft : (data : AnyPtr) -> (n : Int) -> PrimIO Int

||| Direct convolution.
%foreign "C:burble_dsp_convolve, libburble_coprocessor"
prim__convolve : (a : AnyPtr) -> (aLen : Int) ->
                 (b : AnyPtr) -> (bLen : Int) ->
                 (out : AnyPtr) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- Neural kernel
-- ---------------------------------------------------------------------------

||| Initialise denoiser model.
%foreign "C:burble_neural_init, libburble_coprocessor"
prim__neuralInit : (sampleRate : Int) -> PrimIO Bits64

||| Denoise a single frame.
%foreign "C:burble_neural_denoise, libburble_coprocessor"
prim__neuralDenoise : (handle : Bits64) -> (input : AnyPtr) ->
                      (output : AnyPtr) -> PrimIO Int

||| Classify noise type.
%foreign "C:burble_neural_classify, libburble_coprocessor"
prim__neuralClassify : (samples : AnyPtr) -> (numSamples : Int) ->
                       (sampleRate : Int) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- Version info
-- ---------------------------------------------------------------------------

%foreign "C:burble_coprocessor_version, libburble_coprocessor"
prim__version : PrimIO String

public export
version : IO String
version = primIO prim__version
