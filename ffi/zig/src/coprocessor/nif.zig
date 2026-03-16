// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble Coprocessor NIF — Erlang NIF entry point.
//
// Exports SIMD-accelerated audio processing functions as Erlang NIFs.
// Each NIF function matches a callback in Burble.Coprocessor.ZigBackend.
//
// Architecture:
//   nif.zig           — NIF boilerplate, argument marshalling
//   audio.zig         — Opus codec, noise gate, echo cancellation
//   dsp.zig           — FFT, IFFT, convolution, mixing matrix
//   neural.zig        — ML-based noise suppression inference
//
// All kernel implementations use Zig's SIMD vectors (@Vector) for
// parallel sample processing. Memory is managed via Zig allocators
// with explicit lifetime control (no GC interference with BEAM).

const std = @import("std");
const audio = @import("audio.zig");
const dsp = @import("dsp.zig");
const neural = @import("neural.zig");

// ---------------------------------------------------------------------------
// NIF function table
// ---------------------------------------------------------------------------

// Placeholder NIF table — functions will be wired as kernels are implemented.
// Each entry maps an Elixir function atom to a Zig implementation.
//
// Format: .{ "function_name", arity, nif_function_ptr, flags }
//
// TODO: Wire each kernel function as it's implemented:
//   .{ "nif_audio_encode", 4, nif_audio_encode, 0 },
//   .{ "nif_audio_decode", 3, nif_audio_decode, 0 },
//   .{ "nif_audio_echo_cancel", 3, nif_audio_echo_cancel, 0 },
//   .{ "nif_dsp_fft", 2, nif_dsp_fft, 0 },
//   .{ "nif_dsp_ifft", 2, nif_dsp_ifft, 0 },
//   .{ "nif_dsp_convolve", 2, nif_dsp_convolve, 0 },
//   .{ "nif_dsp_mix", 2, nif_dsp_mix, 0 },
//   .{ "nif_neural_init_model", 1, nif_neural_init_model, 0 },
//   .{ "nif_neural_denoise", 3, nif_neural_denoise, 0 },
//   .{ "nif_available", 0, nif_available, 0 },

/// Reports whether the NIF library is loaded and functional.
fn nif_available(_env: ?*anyopaque, _argc: c_int, _argv: ?[*]const anyopaque) callconv(.C) ?*anyopaque {
    // Return Erlang atom 'true'.
    // TODO: use erl_nif.h bindings to construct proper term.
    return null;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Called when the NIF is loaded by the BEAM.
fn nif_load(_env: ?*anyopaque, _priv_data: ?*?*anyopaque, _load_info: ?*anyopaque) callconv(.C) c_int {
    // Initialise thread-local state, allocators, etc.
    return 0;
}

/// Called when the NIF is unloaded.
fn nif_unload(_env: ?*anyopaque, _priv_data: ?*anyopaque) callconv(.C) void {
    // Clean up.
}

// ---------------------------------------------------------------------------
// Version and build info
// ---------------------------------------------------------------------------

/// Return version string for diagnostics.
pub export fn burble_coprocessor_version() [*:0]const u8 {
    return "0.1.0";
}

/// Return build info for diagnostics.
pub export fn burble_coprocessor_build_info() [*:0]const u8 {
    return "zig " ++ @import("builtin").zig_version_string;
}
