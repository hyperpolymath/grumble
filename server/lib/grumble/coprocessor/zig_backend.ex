# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Coprocessor.ZigBackend — Zig NIF backend for hot-path operations.
#
# Loads compiled Zig shared library as Erlang NIFs for SIMD-accelerated
# audio processing. Falls back to ElixirBackend if the NIF is not compiled.
#
# The Zig source lives in ffi/zig/src/coprocessor/ and is compiled with:
#   cd ffi/zig && zig build -Doptimize=ReleaseFast
#
# NIF loading:
#   The compiled .so/.dylib is loaded at module init via :erlang.load_nif/2.
#   Each NIF function has a matching Elixir function that raises if the NIF
#   isn't loaded (standard NIF pattern).
#
# Operations that benefit from Zig SIMD:
#   - Audio encode/decode (PCM↔Opus codec operations)
#   - Audio echo cancellation (NLMS adaptive filter: multiply-accumulate)
#   - DSP FFT/IFFT (butterfly operations, classic SIMD workload)
#   - DSP convolution (O(n*m) multiply-accumulate)
#   - DSP mixing matrix (matrix multiplication)
#   - Neural denoising (inference over spectral features)

defmodule Burble.Coprocessor.ZigBackend do
  @moduledoc """
  Zig NIF backend for SIMD-accelerated coprocessor operations.

  Currently a stub — all operations delegate to `ElixirBackend`.
  When the Zig NIFs are compiled (`ffi/zig/`), this module loads them
  and provides native implementations.

  ## Building the NIFs

      cd ffi/zig && zig build -Doptimize=ReleaseFast
      # Produces priv/burble_coprocessor.so (or .dylib on macOS)

  ## Checking availability

      Burble.Coprocessor.ZigBackend.available?()
      #=> true  (if NIF loaded)
      #=> false (fallback to Elixir)
  """

  @behaviour Burble.Coprocessor.Backend

  alias Burble.Coprocessor.ElixirBackend

  @nif_path "priv/burble_coprocessor"

  # Attempt NIF load at module init. Failure is non-fatal — available?() returns false.
  @on_load :load_nif

  @doc false
  def load_nif do
    nif_file = Application.app_dir(:burble, @nif_path)

    case :erlang.load_nif(String.to_charlist(nif_file), 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  rescue
    # App not started yet during compilation — skip.
    _ -> :ok
  end

  # ---------------------------------------------------------------------------
  # Backend metadata
  # ---------------------------------------------------------------------------

  @impl true
  def backend_type, do: :zig

  @impl true
  def available? do
    # Check if any NIF function is loaded by testing a known function.
    try do
      nif_available()
    rescue
      _ -> false
    end
  end

  # NIF stub — replaced by Zig implementation when loaded.
  def nif_available, do: false

  # ---------------------------------------------------------------------------
  # Audio kernel — NIF stubs (fallback to Elixir)
  # ---------------------------------------------------------------------------

  @impl true
  def audio_encode(pcm, sample_rate, channels, bitrate) do
    if available?() do
      nif_audio_encode(pcm, sample_rate, channels, bitrate)
    else
      ElixirBackend.audio_encode(pcm, sample_rate, channels, bitrate)
    end
  end

  @impl true
  def audio_decode(opus_frame, sample_rate, channels) do
    if available?() do
      nif_audio_decode(opus_frame, sample_rate, channels)
    else
      ElixirBackend.audio_decode(opus_frame, sample_rate, channels)
    end
  end

  @impl true
  def audio_noise_gate(pcm, threshold_db) do
    ElixirBackend.audio_noise_gate(pcm, threshold_db)
  end

  @impl true
  def audio_echo_cancel(capture, reference, filter_length) do
    if available?() do
      nif_audio_echo_cancel(capture, reference, filter_length)
    else
      ElixirBackend.audio_echo_cancel(capture, reference, filter_length)
    end
  end

  # ---------------------------------------------------------------------------
  # Crypto kernel — always Elixir (Erlang :crypto is native C already)
  # ---------------------------------------------------------------------------

  @impl true
  def crypto_encrypt_frame(plaintext, key, aad),
    do: ElixirBackend.crypto_encrypt_frame(plaintext, key, aad)

  @impl true
  def crypto_decrypt_frame(ciphertext, key, iv, tag, aad),
    do: ElixirBackend.crypto_decrypt_frame(ciphertext, key, iv, tag, aad)

  @impl true
  def crypto_hash_chain(prev_hash, payload),
    do: ElixirBackend.crypto_hash_chain(prev_hash, payload)

  @impl true
  def crypto_derive_frame_key(shared_secret, salt, info),
    do: ElixirBackend.crypto_derive_frame_key(shared_secret, salt, info)

  # ---------------------------------------------------------------------------
  # I/O kernel — always Elixir (data structure operations)
  # ---------------------------------------------------------------------------

  @impl true
  def io_jitter_buffer_push(buffer_state, packet, sequence, timestamp),
    do: ElixirBackend.io_jitter_buffer_push(buffer_state, packet, sequence, timestamp)

  @impl true
  def io_conceal_loss(prev_frames, frame_size),
    do: ElixirBackend.io_conceal_loss(prev_frames, frame_size)

  @impl true
  def io_adaptive_bitrate(loss_ratio, rtt_ms, current_bitrate),
    do: ElixirBackend.io_adaptive_bitrate(loss_ratio, rtt_ms, current_bitrate)

  # ---------------------------------------------------------------------------
  # DSP kernel — NIF stubs (fallback to Elixir)
  # ---------------------------------------------------------------------------

  @impl true
  def dsp_fft(signal, size) do
    if available?() do
      nif_dsp_fft(signal, size)
    else
      ElixirBackend.dsp_fft(signal, size)
    end
  end

  @impl true
  def dsp_ifft(spectrum, size) do
    if available?() do
      nif_dsp_ifft(spectrum, size)
    else
      ElixirBackend.dsp_ifft(spectrum, size)
    end
  end

  @impl true
  def dsp_convolve(a, b) do
    if available?() do
      nif_dsp_convolve(a, b)
    else
      ElixirBackend.dsp_convolve(a, b)
    end
  end

  @impl true
  def dsp_mix(streams, matrix) do
    if available?() do
      nif_dsp_mix(streams, matrix)
    else
      ElixirBackend.dsp_mix(streams, matrix)
    end
  end

  # ---------------------------------------------------------------------------
  # Neural kernel — NIF stubs (fallback to Elixir)
  # ---------------------------------------------------------------------------

  @impl true
  def neural_init_model(sample_rate) do
    if available?() do
      nif_neural_init_model(sample_rate)
    else
      ElixirBackend.neural_init_model(sample_rate)
    end
  end

  @impl true
  def neural_denoise(pcm, sample_rate, model_state) do
    if available?() do
      nif_neural_denoise(pcm, sample_rate, model_state)
    else
      ElixirBackend.neural_denoise(pcm, sample_rate, model_state)
    end
  end

  @impl true
  def neural_classify_noise(pcm, sample_rate),
    do: ElixirBackend.neural_classify_noise(pcm, sample_rate)

  # ---------------------------------------------------------------------------
  # NIF function stubs — replaced when .so is loaded
  # ---------------------------------------------------------------------------

  def nif_audio_encode(_pcm, _sr, _ch, _br), do: :erlang.nif_error(:nif_not_loaded)
  def nif_audio_decode(_frame, _sr, _ch), do: :erlang.nif_error(:nif_not_loaded)
  def nif_audio_echo_cancel(_cap, _ref, _fl), do: :erlang.nif_error(:nif_not_loaded)
  def nif_dsp_fft(_signal, _size), do: :erlang.nif_error(:nif_not_loaded)
  def nif_dsp_ifft(_spectrum, _size), do: :erlang.nif_error(:nif_not_loaded)
  def nif_dsp_convolve(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def nif_dsp_mix(_streams, _matrix), do: :erlang.nif_error(:nif_not_loaded)
  def nif_neural_init_model(_sr), do: :erlang.nif_error(:nif_not_loaded)
  def nif_neural_denoise(_pcm, _sr, _state), do: :erlang.nif_error(:nif_not_loaded)
end
