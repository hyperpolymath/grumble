# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Coprocessor.SmartBackend — Per-operation dispatch to fastest backend.
#
# Follows Axiom.jl's SmartBackend pattern: each kernel operation is routed to
# whichever backend is fastest for that specific operation. The dispatch table
# is based on benchmarks (same approach as Axiom.jl's matmul→Julia, gelu→Zig).
#
# Current dispatch table (to be updated with real benchmarks):
#
#   Audio encode/decode    → Zig (codec operations are CPU-bound, SIMD helps)
#   Audio noise gate       → Elixir (simple threshold, no benefit from SIMD at typical frame sizes)
#   Audio echo cancel      → Zig (NLMS adaptive filter is compute-intensive)
#   Crypto encrypt/decrypt → Elixir (delegates to Erlang :crypto which uses OpenSSL/BoringSSL)
#   Crypto hash chain      → Elixir (same — Erlang :crypto is already native)
#   Crypto derive key      → Elixir (same)
#   I/O jitter buffer      → Elixir (data structure operations, not compute-bound)
#   I/O conceal loss       → Elixir (simple operations)
#   I/O adaptive bitrate   → Elixir (trivial arithmetic)
#   DSP FFT/IFFT           → Zig (classic SIMD workload)
#   DSP convolve           → Zig (O(n*m) multiply-accumulate)
#   DSP mix                → Zig (matrix multiply)
#   Neural denoise         → Zig (ML inference is the canonical Zig use case)
#   Neural classify        → Elixir (simple heuristic, no ML model yet)

defmodule Burble.Coprocessor.SmartBackend do
  @moduledoc """
  Smart dispatcher that routes each kernel operation to the fastest backend.

  If the Zig backend is not available, all operations fall back to Elixir.
  When Zig is available, operations are dispatched per the benchmark table.
  """

  @behaviour Burble.Coprocessor.Backend

  alias Burble.Coprocessor.ElixirBackend
  alias Burble.Coprocessor.ZigBackend

  # ---------------------------------------------------------------------------
  # Backend metadata
  # ---------------------------------------------------------------------------

  @impl true
  def backend_type, do: :smart

  @impl true
  def available?, do: true

  # ---------------------------------------------------------------------------
  # Dispatch helpers
  # ---------------------------------------------------------------------------

  # Route to Zig if available, otherwise Elixir.
  defp zig_or_elixir do
    if ZigBackend.available?(), do: ZigBackend, else: ElixirBackend
  end

  # Always use Elixir (operation is fast enough or delegates to Erlang :crypto).
  defp always_elixir, do: ElixirBackend

  # ---------------------------------------------------------------------------
  # Audio kernel — dispatch
  # ---------------------------------------------------------------------------

  @impl true
  def audio_encode(pcm, sample_rate, channels, bitrate) do
    zig_or_elixir().audio_encode(pcm, sample_rate, channels, bitrate)
  end

  @impl true
  def audio_decode(opus_frame, sample_rate, channels) do
    zig_or_elixir().audio_decode(opus_frame, sample_rate, channels)
  end

  @impl true
  def audio_noise_gate(pcm, threshold_db) do
    # Simple threshold — Elixir is fine.
    always_elixir().audio_noise_gate(pcm, threshold_db)
  end

  @impl true
  def audio_echo_cancel(capture, reference, filter_length) do
    zig_or_elixir().audio_echo_cancel(capture, reference, filter_length)
  end

  # ---------------------------------------------------------------------------
  # Crypto kernel — dispatch (Erlang :crypto is already native C)
  # ---------------------------------------------------------------------------

  @impl true
  def crypto_encrypt_frame(plaintext, key, aad) do
    always_elixir().crypto_encrypt_frame(plaintext, key, aad)
  end

  @impl true
  def crypto_decrypt_frame(ciphertext, key, iv, tag, aad) do
    always_elixir().crypto_decrypt_frame(ciphertext, key, iv, tag, aad)
  end

  @impl true
  def crypto_hash_chain(prev_hash, payload) do
    always_elixir().crypto_hash_chain(prev_hash, payload)
  end

  @impl true
  def crypto_derive_frame_key(shared_secret, salt, info) do
    always_elixir().crypto_derive_frame_key(shared_secret, salt, info)
  end

  # ---------------------------------------------------------------------------
  # I/O kernel — dispatch (data structure ops, not compute-bound)
  # ---------------------------------------------------------------------------

  @impl true
  def io_jitter_buffer_push(buffer_state, packet, sequence, timestamp) do
    always_elixir().io_jitter_buffer_push(buffer_state, packet, sequence, timestamp)
  end

  @impl true
  def io_conceal_loss(prev_frames, frame_size) do
    always_elixir().io_conceal_loss(prev_frames, frame_size)
  end

  @impl true
  def io_adaptive_bitrate(loss_ratio, rtt_ms, current_bitrate) do
    always_elixir().io_adaptive_bitrate(loss_ratio, rtt_ms, current_bitrate)
  end

  # ---------------------------------------------------------------------------
  # DSP kernel — dispatch (SIMD-friendly workloads → Zig)
  # ---------------------------------------------------------------------------

  @impl true
  def dsp_fft(signal, size) do
    zig_or_elixir().dsp_fft(signal, size)
  end

  @impl true
  def dsp_ifft(spectrum, size) do
    zig_or_elixir().dsp_ifft(spectrum, size)
  end

  @impl true
  def dsp_convolve(a, b) do
    zig_or_elixir().dsp_convolve(a, b)
  end

  @impl true
  def dsp_mix(streams, matrix) do
    zig_or_elixir().dsp_mix(streams, matrix)
  end

  # ---------------------------------------------------------------------------
  # Neural kernel — dispatch
  # ---------------------------------------------------------------------------

  @impl true
  def neural_init_model(sample_rate) do
    zig_or_elixir().neural_init_model(sample_rate)
  end

  @impl true
  def neural_denoise(pcm, sample_rate, model_state) do
    zig_or_elixir().neural_denoise(pcm, sample_rate, model_state)
  end

  @impl true
  def neural_classify_noise(pcm, sample_rate) do
    # Simple heuristic — Elixir is fine until we have a real ML model.
    always_elixir().neural_classify_noise(pcm, sample_rate)
  end
end
