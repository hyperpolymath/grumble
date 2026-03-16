# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble.Coprocessor.ElixirBackend — Pure Elixir reference implementation.
#
# Every kernel operation has a correct (if not optimal) implementation here.
# This serves as:
#   1. Reference for testing — Zig backend must produce identical results
#   2. Fallback — if Zig NIFs aren't compiled, operations still work
#   3. Documentation — readable implementations of each algorithm
#
# Performance: adequate for small rooms (<10 peers). For larger deployments,
# the ZigBackend provides SIMD-accelerated hot paths.

defmodule Burble.Coprocessor.ElixirBackend do
  @moduledoc """
  Pure Elixir reference backend for all coprocessor kernels.

  Implements every `Burble.Coprocessor.Backend` callback using only
  Erlang/Elixir standard library functions. No NIFs, no external deps.
  """

  @behaviour Burble.Coprocessor.Backend

  # ---------------------------------------------------------------------------
  # Backend metadata
  # ---------------------------------------------------------------------------

  @impl true
  def backend_type, do: :elixir

  @impl true
  def available?, do: true

  # ---------------------------------------------------------------------------
  # Audio kernel
  # ---------------------------------------------------------------------------

  @impl true
  def audio_encode(pcm, _sample_rate, channels, _bitrate) do
    # Reference: pack PCM as 16-bit LE integers in a raw frame.
    # Real Opus encoding requires the opus NIF or external library.
    # This produces a PCM frame that can round-trip through audio_decode.
    samples =
      pcm
      |> Enum.map(fn sample ->
        clamped = max(-1.0, min(1.0, sample))
        trunc(clamped * 32767.0)
      end)

    binary =
      samples
      |> Enum.map(fn s -> <<s::little-signed-16>> end)
      |> IO.iodata_to_binary()

    header = <<channels::8, byte_size(binary)::32-little>>
    {:ok, header <> binary}
  end

  @impl true
  def audio_decode(opus_frame, _sample_rate, _channels) do
    case opus_frame do
      <<_ch::8, len::32-little, data::binary-size(len), _rest::binary>> ->
        samples =
          for <<sample::little-signed-16 <- data>> do
            sample / 32767.0
          end

        {:ok, samples}

      _ ->
        {:error, :invalid_frame}
    end
  end

  @impl true
  def audio_noise_gate(pcm, threshold_db) do
    # Convert dB threshold to linear amplitude.
    threshold_linear = :math.pow(10.0, threshold_db / 20.0)

    Enum.map(pcm, fn sample ->
      if abs(sample) < threshold_linear, do: 0.0, else: sample
    end)
  end

  @impl true
  def audio_echo_cancel(capture, reference, filter_length) do
    # NLMS (Normalised Least Mean Squares) adaptive filter.
    # Step size (mu) controls convergence speed vs stability.
    mu = 0.5
    epsilon = 1.0e-8

    {output, _weights} =
      capture
      |> Enum.zip(reference)
      |> Enum.reduce({[], List.duplicate(0.0, filter_length)}, fn {cap, _ref}, {acc, weights} ->
        # Build reference window from accumulated reference samples.
        ref_window =
          reference
          |> Enum.take(filter_length)
          |> pad_to(filter_length)

        # Estimate echo: dot product of weights and reference window.
        echo_estimate = dot(weights, ref_window)

        # Error = capture - estimated echo.
        error = cap - echo_estimate

        # Normalise step size by reference power.
        power = dot(ref_window, ref_window) + epsilon
        step = mu / power

        # Update weights.
        new_weights =
          Enum.zip(weights, ref_window)
          |> Enum.map(fn {w, r} -> w + step * error * r end)

        {[error | acc], new_weights}
      end)

    Enum.reverse(output)
  end

  # ---------------------------------------------------------------------------
  # Crypto kernel
  # ---------------------------------------------------------------------------

  @impl true
  def crypto_encrypt_frame(plaintext, key, aad) do
    iv = :crypto.strong_rand_bytes(12)

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true) do
      {ciphertext, tag} -> {:ok, {ciphertext, iv, tag}}
      _ -> {:error, :encrypt_failed}
    end
  end

  @impl true
  def crypto_decrypt_frame(ciphertext, key, iv, tag, aad) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false) do
      :error -> {:error, :decrypt_failed}
      plaintext -> {:ok, plaintext}
    end
  end

  @impl true
  def crypto_hash_chain(prev_hash, payload) do
    :crypto.hash(:sha256, prev_hash <> payload)
  end

  @impl true
  def crypto_derive_frame_key(shared_secret, salt, info) do
    # HKDF-SHA256: extract then expand.
    prk = :crypto.mac(:hmac, :sha256, salt, shared_secret)
    # Expand to 32 bytes (one block).
    :crypto.mac(:hmac, :sha256, prk, info <> <<1::8>>)
  end

  # ---------------------------------------------------------------------------
  # I/O kernel
  # ---------------------------------------------------------------------------

  @impl true
  def io_jitter_buffer_push(buffer_state, packet, sequence, timestamp) do
    buffer = Map.get(buffer_state, :packets, [])
    target_delay = Map.get(buffer_state, :target_delay_ms, 40)
    base_ts = Map.get(buffer_state, :base_timestamp)

    entry = %{packet: packet, seq: sequence, ts: timestamp}
    updated_buffer = insert_sorted(buffer, entry)

    # Set base timestamp on first packet.
    base_ts = base_ts || timestamp

    new_state =
      buffer_state
      |> Map.put(:packets, updated_buffer)
      |> Map.put(:base_timestamp, base_ts)
      |> Map.put(:target_delay_ms, target_delay)

    # Emit the oldest packet if we have enough buffered.
    [oldest | rest] = updated_buffer
    age_ms = timestamp - oldest.ts

    if age_ms >= target_delay do
      {:ok, oldest.packet, Map.put(new_state, :packets, rest)}
    else
      {:ok, nil, new_state}
    end
  end

  @impl true
  def io_conceal_loss(prev_frames, frame_size) do
    # Simple packet loss concealment: repeat last frame with fade.
    case prev_frames do
      [last | _] ->
        # Apply gentle fade (0.95 gain) to avoid clicks.
        last
        |> :binary.bin_to_list()
        |> Enum.map(fn b -> trunc(b * 0.95) end)
        |> :binary.list_to_bin()
        |> binary_pad_or_trim(frame_size)

      [] ->
        # No previous frames — emit silence.
        <<0::size(frame_size * 8)>>
    end
  end

  @impl true
  def io_adaptive_bitrate(loss_ratio, rtt_ms, current_bitrate) do
    # Simple AIMD (Additive Increase Multiplicative Decrease).
    min_bitrate = 16_000
    max_bitrate = 128_000

    new_bitrate =
      cond do
        # High loss or high RTT — decrease multiplicatively.
        loss_ratio > 0.10 or rtt_ms > 300 ->
          trunc(current_bitrate * 0.7)

        # Moderate conditions — hold steady.
        loss_ratio > 0.02 or rtt_ms > 150 ->
          current_bitrate

        # Good conditions — increase additively.
        true ->
          current_bitrate + 4_000
      end

    max(min_bitrate, min(max_bitrate, new_bitrate))
  end

  # ---------------------------------------------------------------------------
  # DSP kernel
  # ---------------------------------------------------------------------------

  @impl true
  def dsp_fft(signal, size) do
    # Cooley-Tukey radix-2 DIT FFT.
    if size <= 1 do
      Enum.map(signal, fn s -> {s, 0.0} end)
    else
      half = div(size, 2)

      {evens, odds} =
        signal
        |> Enum.with_index()
        |> Enum.split_with(fn {_val, idx} -> rem(idx, 2) == 0 end)

      even_vals = Enum.map(evens, fn {v, _} -> v end)
      odd_vals = Enum.map(odds, fn {v, _} -> v end)

      fft_even = dsp_fft(even_vals, half)
      fft_odd = dsp_fft(odd_vals, half)

      Enum.map(0..(size - 1), fn k ->
        k_mod = rem(k, half)
        angle = -2.0 * :math.pi() * k / size
        {wr, wi} = {:math.cos(angle), :math.sin(angle)}

        {or_val, oi_val} = Enum.at(fft_odd, k_mod)
        {er, ei} = Enum.at(fft_even, k_mod)

        # Twiddle factor multiplication: W * odd[k]
        tr = wr * or_val - wi * oi_val
        ti = wr * oi_val + wi * or_val

        if k < half do
          {er + tr, ei + ti}
        else
          {er - tr, ei - ti}
        end
      end)
    end
  end

  @impl true
  def dsp_ifft(spectrum, size) do
    # IFFT via conjugate FFT trick: IFFT(X) = conj(FFT(conj(X))) / N
    conjugated = Enum.map(spectrum, fn {r, i} -> {r, -i} end)
    signal_vals = Enum.map(conjugated, fn {r, _i} -> r end)
    fft_result = dsp_fft(signal_vals, size)

    Enum.map(fft_result, fn {r, _i} -> r / size end)
  end

  @impl true
  def dsp_convolve(a, b) do
    len_a = length(a)
    len_b = length(b)
    out_len = len_a + len_b - 1

    a_indexed = Enum.with_index(a)

    Enum.map(0..(out_len - 1), fn n ->
      Enum.reduce(a_indexed, 0.0, fn {a_val, k}, acc ->
        b_idx = n - k

        if b_idx >= 0 and b_idx < len_b do
          acc + a_val * Enum.at(b, b_idx)
        else
          acc
        end
      end)
    end)
  end

  @impl true
  def dsp_mix(streams, matrix) do
    # matrix[output][input] — apply gain matrix to produce output streams.
    Enum.map(matrix, fn output_gains ->
      # For each output channel, sum the weighted input streams.
      weighted =
        streams
        |> Enum.zip(output_gains)
        |> Enum.map(fn {stream, gain} ->
          Enum.map(stream, fn s -> s * gain end)
        end)

      # Sum across all inputs, sample by sample.
      case weighted do
        [] ->
          []

        [first | rest] ->
          Enum.reduce(rest, first, fn stream, acc ->
            Enum.zip(acc, stream)
            |> Enum.map(fn {a, b} -> a + b end)
          end)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Neural kernel
  # ---------------------------------------------------------------------------

  @impl true
  def neural_init_model(_sample_rate) do
    # Reference implementation: spectral gating model state.
    # Tracks a running noise floor estimate across frames.
    %{
      noise_floor: nil,
      frame_count: 0,
      alpha: 0.98
    }
  end

  @impl true
  def neural_denoise(pcm, _sample_rate, model_state) do
    # Reference: spectral gating.
    # Estimate noise floor from quiet frames, gate frequencies below it.
    rms = rms_energy(pcm)
    frame_count = model_state.frame_count + 1

    noise_floor =
      case model_state.noise_floor do
        nil ->
          # First frame — assume it's noise to bootstrap.
          rms

        prev ->
          if rms < prev * 1.5 do
            # Quiet frame — update noise floor with exponential average.
            model_state.alpha * prev + (1.0 - model_state.alpha) * rms
          else
            prev
          end
      end

    # Gate: if frame RMS is close to noise floor, attenuate.
    gate_ratio = if noise_floor > 0.0, do: max(0.0, 1.0 - noise_floor / max(rms, 1.0e-10)), else: 1.0
    cleaned = Enum.map(pcm, fn s -> s * gate_ratio end)

    new_state = %{model_state | noise_floor: noise_floor, frame_count: frame_count}
    {cleaned, new_state}
  end

  @impl true
  def neural_classify_noise(pcm, _sample_rate) do
    rms = rms_energy(pcm)
    zcr = zero_crossing_rate(pcm)

    cond do
      rms < 0.001 -> {:silence, 0.95}
      zcr > 0.4 -> {:keyboard, 0.6}
      rms > 0.1 and zcr < 0.15 -> {:speech, 0.7}
      rms > 0.05 and zcr > 0.2 -> {:fan, 0.5}
      true -> {:unknown, 0.3}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp dot(a, b) do
    Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
  end

  defp pad_to(list, target_len) when length(list) >= target_len, do: Enum.take(list, target_len)
  defp pad_to(list, target_len), do: list ++ List.duplicate(0.0, target_len - length(list))

  defp insert_sorted([], entry), do: [entry]
  defp insert_sorted([head | tail] = list, entry) do
    if entry.seq <= head.seq, do: [entry | list], else: [head | insert_sorted(tail, entry)]
  end

  defp binary_pad_or_trim(bin, size) when byte_size(bin) >= size, do: binary_part(bin, 0, size)
  defp binary_pad_or_trim(bin, size), do: bin <> <<0::size((size - byte_size(bin)) * 8)>>

  defp rms_energy(pcm) do
    sum_sq = Enum.reduce(pcm, 0.0, fn s, acc -> acc + s * s end)
    :math.sqrt(sum_sq / max(length(pcm), 1))
  end

  defp zero_crossing_rate([]), do: 0.0
  defp zero_crossing_rate([_]), do: 0.0
  defp zero_crossing_rate(pcm) do
    crossings =
      pcm
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> (a >= 0 and b < 0) or (a < 0 and b >= 0) end)

    crossings / (length(pcm) - 1)
  end
end
