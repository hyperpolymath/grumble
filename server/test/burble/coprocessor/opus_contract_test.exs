# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Opus contract regression test.
#
# Burble is an E2EE-opaque SFU. Clients perform Opus encoding in the
# browser's WebRTC stack; the server never transcodes live audio. The
# Backend.audio_encode/4 and Backend.audio_decode/3 callbacks pack raw PCM
# into a length-prefixed frame — they do NOT perform Opus compression.
#
# The explicit Backend.opus_transcode/4 callback exists so callers that
# *do* want real Opus transcoding fail loudly with {:error, :not_implemented}
# rather than silently receiving a round-tripped PCM frame.
#
# These tests pin that contract so a future change that silently adds real
# Opus to audio_encode (or removes opus_transcode) will break the suite.

defmodule Burble.Coprocessor.OpusContractTest do
  use ExUnit.Case, async: true

  alias Burble.Coprocessor.{ElixirBackend, SmartBackend, ZigBackend}

  describe "opus_transcode/4 contract" do
    test "ElixirBackend returns {:error, :not_implemented}" do
      pcm = [0.0, 0.5, -0.5, 0.25]
      assert {:error, :not_implemented} =
               ElixirBackend.opus_transcode(pcm, 48_000, 1, 32_000)
    end

    test "ZigBackend returns {:error, :not_implemented}" do
      pcm = [0.0, 0.5, -0.5, 0.25]
      assert {:error, :not_implemented} =
               ZigBackend.opus_transcode(pcm, 48_000, 1, 32_000)
    end

    test "SmartBackend returns {:error, :not_implemented}" do
      pcm = [0.0, 0.5, -0.5, 0.25]
      assert {:error, :not_implemented} =
               SmartBackend.opus_transcode(pcm, 48_000, 1, 32_000)
    end

    test "opus_available?/0 is false on every backend" do
      refute ElixirBackend.opus_available?()
      refute ZigBackend.opus_available?()
      refute SmartBackend.opus_available?()
    end
  end

  describe "audio_encode/4 is PCM framing, NOT Opus" do
    test "round-trips raw PCM through audio_decode/3 (ElixirBackend)" do
      pcm = [0.0, 0.5, -0.5, 0.25, -0.25]
      {:ok, frame} = ElixirBackend.audio_encode(pcm, 48_000, 1, 32_000)
      {:ok, decoded} = ElixirBackend.audio_decode(frame, 48_000, 1)

      # Exact round-trip within quantisation error confirms no Opus
      # compression is being applied — real Opus is lossy and would lose
      # precision well below the 16-bit quantisation floor we see here.
      assert length(decoded) == length(pcm)

      Enum.zip(pcm, decoded)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig, dec, 1.0e-4
      end)
    end

    test "bitrate parameter is ignored (ElixirBackend)" do
      pcm = [0.0, 0.5, -0.5]

      {:ok, frame_low} = ElixirBackend.audio_encode(pcm, 48_000, 1, 8_000)
      {:ok, frame_high} = ElixirBackend.audio_encode(pcm, 48_000, 1, 320_000)

      # If bitrate controlled a real codec, low-bitrate frames would be
      # shorter than high-bitrate frames. Since this is PCM framing, the
      # two outputs are byte-identical regardless of "bitrate".
      assert frame_low == frame_high
    end

    test "frame format is a stable 1-byte channel + 4-byte LE length + i16 LE PCM" do
      # Two 16-bit samples × 1 channel, plus 1-byte channels header +
      # 4-byte length field = 9 bytes total.
      pcm = [0.5, -0.5]
      {:ok, frame} = ElixirBackend.audio_encode(pcm, 48_000, 1, 32_000)

      assert byte_size(frame) == 1 + 4 + 2 * 2
      <<channels::8, len::32-little, _data::binary-size(len), _rest::binary>> = frame
      assert channels == 1
      assert len == 4
    end
  end
end
