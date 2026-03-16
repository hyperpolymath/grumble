// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble Coprocessor NIF — Erlang NIF entry point.
//
// Exports SIMD-accelerated audio processing functions as Erlang NIFs.
// Each NIF function matches a callback in Burble.Coprocessor.ZigBackend.
//
// Architecture:
//   nif.zig           — NIF boilerplate, argument marshalling, term conversion
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
const compression = @import("compression.zig");

const c = @cImport({
    @cInclude("erl_nif.h");
});

// Type aliases for readability.
const ErlNifEnv = c.ErlNifEnv;
const ERL_NIF_TERM = c.ERL_NIF_TERM;
const ErlNifBinary = c.ErlNifBinary;

// ---------------------------------------------------------------------------
// Helpers: Erlang term construction
// ---------------------------------------------------------------------------

fn make_atom(env: ?*ErlNifEnv, name: [*:0]const u8) ERL_NIF_TERM {
    return c.enif_make_atom(env, name);
}

fn make_ok(env: ?*ErlNifEnv, term: ERL_NIF_TERM) ERL_NIF_TERM {
    return c.enif_make_tuple2(env, make_atom(env, "ok"), term);
}

fn make_error(env: ?*ErlNifEnv, reason: [*:0]const u8) ERL_NIF_TERM {
    return c.enif_make_tuple2(env, make_atom(env, "error"), make_atom(env, reason));
}

fn make_float_list(env: ?*ErlNifEnv, values: []const f32) ERL_NIF_TERM {
    if (values.len == 0) return c.enif_make_list(env, 0);

    // Build list in reverse for efficiency.
    var list = c.enif_make_list(env, 0);
    var i: usize = values.len;
    while (i > 0) {
        i -= 1;
        const term = c.enif_make_double(env, @as(f64, @floatCast(values[i])));
        list = c.enif_make_list_cell(env, term, list);
    }
    return list;
}

/// Extract a list of f32 from an Erlang list term into a pre-allocated buffer.
/// Returns the number of elements extracted, or null on failure.
fn get_float_list(env: ?*ErlNifEnv, term: ERL_NIF_TERM, buf: []f32) ?usize {
    var list = term;
    var i: usize = 0;

    while (i < buf.len) {
        var head: ERL_NIF_TERM = undefined;
        var tail: ERL_NIF_TERM = undefined;

        if (c.enif_get_list_cell(env, list, &head, &tail) == 0) break;

        var dval: f64 = undefined;
        if (c.enif_get_double(env, head, &dval) == 0) {
            // Try integer.
            var ival: c_long = undefined;
            if (c.enif_get_long(env, head, &ival) == 0) return null;
            dval = @floatFromInt(ival);
        }

        buf[i] = @floatCast(dval);
        list = tail;
        i += 1;
    }

    return i;
}

// ---------------------------------------------------------------------------
// NIF: nif_available/0
// ---------------------------------------------------------------------------

fn nif_available(env: ?*ErlNifEnv, _: c_int, _ : [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    return make_atom(env, "true");
}

// ---------------------------------------------------------------------------
// NIF: nif_audio_encode/4 — (pcm_list, sample_rate, channels, bitrate)
// ---------------------------------------------------------------------------

fn nif_audio_encode(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    // Get list length.
    var list_len: c_uint = undefined;
    if (c.enif_get_list_length(env, argv[0], &list_len) == 0)
        return make_error(env, "bad_pcm_list");

    const num_samples: usize = @intCast(list_len);
    if (num_samples == 0) return make_error(env, "empty_pcm");

    // Allocate sample buffer.
    var pcm_buf: [4800]f32 = undefined; // max 100ms at 48kHz
    if (num_samples > pcm_buf.len) return make_error(env, "frame_too_large");

    const n = get_float_list(env, argv[0], pcm_buf[0..num_samples]) orelse
        return make_error(env, "bad_pcm_values");

    // Get channels param.
    var channels: c_int = undefined;
    if (c.enif_get_int(env, argv[2], &channels) == 0)
        return make_error(env, "bad_channels");

    // Encode PCM to 16-bit LE binary.
    var out_buf: [9600]u8 = undefined; // 2 bytes per sample
    const bytes_written = audio.pcm_encode(pcm_buf[0..n], &out_buf);

    // Build header: <<channels::8, len::32-little, data::binary>>
    var result_bin: ErlNifBinary = undefined;
    const total_size = 5 + bytes_written;
    if (c.enif_alloc_binary(total_size, &result_bin) == 0)
        return make_error(env, "alloc_failed");

    const data_ptr = result_bin.data;
    data_ptr[0] = @intCast(channels);
    const len32: u32 = @intCast(bytes_written);
    @memcpy(data_ptr[1..5], &std.mem.toBytes(std.mem.nativeToLittle(u32, len32)));
    @memcpy(data_ptr[5 .. 5 + bytes_written], out_buf[0..bytes_written]);

    return make_ok(env, c.enif_make_binary(env, &result_bin));
}

// ---------------------------------------------------------------------------
// NIF: nif_audio_decode/3 — (opus_binary, sample_rate, channels)
// ---------------------------------------------------------------------------

fn nif_audio_decode(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var bin: ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, argv[0], &bin) == 0)
        return make_error(env, "bad_binary");

    if (bin.size < 5) return make_error(env, "invalid_frame");

    const data = bin.data;
    const data_len = std.mem.readInt(u32, data[1..5], .little);

    if (5 + data_len > bin.size) return make_error(env, "invalid_frame");

    var pcm_buf: [4800]f32 = undefined;
    const num_samples = audio.pcm_decode(data[5 .. 5 + data_len], &pcm_buf);

    return make_ok(env, make_float_list(env, pcm_buf[0..num_samples]));
}

// ---------------------------------------------------------------------------
// NIF: nif_audio_echo_cancel/3 — (capture_list, reference_list, filter_length)
// ---------------------------------------------------------------------------

fn nif_audio_echo_cancel(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var cap_len: c_uint = undefined;
    var ref_len: c_uint = undefined;
    if (c.enif_get_list_length(env, argv[0], &cap_len) == 0) return make_error(env, "bad_capture");
    if (c.enif_get_list_length(env, argv[1], &ref_len) == 0) return make_error(env, "bad_reference");

    const nc: usize = @intCast(cap_len);
    const nr: usize = @intCast(ref_len);
    if (nc > 4800 or nr > 4800) return make_error(env, "frame_too_large");

    var capture: [4800]f32 = undefined;
    var reference: [4800]f32 = undefined;

    _ = get_float_list(env, argv[0], capture[0..nc]) orelse return make_error(env, "bad_capture_values");
    _ = get_float_list(env, argv[1], reference[0..nr]) orelse return make_error(env, "bad_reference_values");

    var filter_len_int: c_int = undefined;
    if (c.enif_get_int(env, argv[2], &filter_len_int) == 0) return make_error(env, "bad_filter_length");
    const filter_len: usize = @intCast(filter_len_int);
    if (filter_len > 1024) return make_error(env, "filter_too_large");

    var weights: [1024]f32 = [_]f32{0.0} ** 1024;

    audio.echo_cancel(capture[0..nc], reference[0..nr], weights[0..filter_len], 0.5);

    return make_ok(env, make_float_list(env, capture[0..nc]));
}

// ---------------------------------------------------------------------------
// NIF: nif_dsp_fft/2 — (signal_list, size)
// ---------------------------------------------------------------------------

fn nif_dsp_fft(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var size_int: c_int = undefined;
    if (c.enif_get_int(env, argv[1], &size_int) == 0) return make_error(env, "bad_size");
    const n: usize = @intCast(size_int);
    if (n > 2048) return make_error(env, "fft_too_large");

    // Input is a list of floats (real values). We need interleaved complex.
    var list_len: c_uint = undefined;
    if (c.enif_get_list_length(env, argv[0], &list_len) == 0) return make_error(env, "bad_signal");
    const nl: usize = @intCast(list_len);
    if (nl != n) return make_error(env, "size_mismatch");

    // Read real values, create interleaved complex (imaginary = 0).
    var reals: [2048]f32 = undefined;
    _ = get_float_list(env, argv[0], reals[0..n]) orelse return make_error(env, "bad_signal_values");

    var complex_data: [4096]f32 = undefined; // 2*n interleaved
    for (0..n) |i| {
        complex_data[i * 2] = reals[i];
        complex_data[i * 2 + 1] = 0.0;
    }

    dsp.fft(complex_data[0 .. n * 2], n);

    // Return as list of {real, imag} tuples.
    var result = c.enif_make_list(env, 0);
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        const re = c.enif_make_double(env, @as(f64, @floatCast(complex_data[i * 2])));
        const im = c.enif_make_double(env, @as(f64, @floatCast(complex_data[i * 2 + 1])));
        const tuple = c.enif_make_tuple2(env, re, im);
        result = c.enif_make_list_cell(env, tuple, result);
    }

    return make_ok(env, result);
}

// ---------------------------------------------------------------------------
// NIF: nif_dsp_ifft/2 — (spectrum_tuple_list, size)
// ---------------------------------------------------------------------------

fn nif_dsp_ifft(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var size_int: c_int = undefined;
    if (c.enif_get_int(env, argv[1], &size_int) == 0) return make_error(env, "bad_size");
    const n: usize = @intCast(size_int);
    if (n > 2048) return make_error(env, "fft_too_large");

    // Read list of {real, imag} tuples.
    var complex_data: [4096]f32 = undefined;
    var list = argv[0];
    for (0..n) |i| {
        var head: ERL_NIF_TERM = undefined;
        var tail: ERL_NIF_TERM = undefined;
        if (c.enif_get_list_cell(env, list, &head, &tail) == 0) return make_error(env, "bad_spectrum");

        var arity: c_int = undefined;
        var tuple_elems: [*c]const ERL_NIF_TERM = undefined;
        if (c.enif_get_tuple(env, head, &arity, &tuple_elems) == 0 or arity != 2)
            return make_error(env, "bad_tuple");

        var re: f64 = undefined;
        var im: f64 = undefined;
        if (c.enif_get_double(env, tuple_elems[0], &re) == 0) return make_error(env, "bad_real");
        if (c.enif_get_double(env, tuple_elems[1], &im) == 0) return make_error(env, "bad_imag");

        complex_data[i * 2] = @floatCast(re);
        complex_data[i * 2 + 1] = @floatCast(im);
        list = tail;
    }

    dsp.ifft(complex_data[0 .. n * 2], n);

    // Return real parts as a flat list.
    var reals: [2048]f32 = undefined;
    for (0..n) |i| {
        reals[i] = complex_data[i * 2];
    }

    return make_ok(env, make_float_list(env, reals[0..n]));
}

// ---------------------------------------------------------------------------
// NIF: nif_dsp_convolve/2 — (a_list, b_list)
// ---------------------------------------------------------------------------

fn nif_dsp_convolve(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var a_len_c: c_uint = undefined;
    var b_len_c: c_uint = undefined;
    if (c.enif_get_list_length(env, argv[0], &a_len_c) == 0) return make_error(env, "bad_list_a");
    if (c.enif_get_list_length(env, argv[1], &b_len_c) == 0) return make_error(env, "bad_list_b");

    const a_len: usize = @intCast(a_len_c);
    const b_len: usize = @intCast(b_len_c);
    if (a_len > 4096 or b_len > 4096) return make_error(env, "input_too_large");

    var a_buf: [4096]f32 = undefined;
    var b_buf: [4096]f32 = undefined;
    _ = get_float_list(env, argv[0], a_buf[0..a_len]) orelse return make_error(env, "bad_a_values");
    _ = get_float_list(env, argv[1], b_buf[0..b_len]) orelse return make_error(env, "bad_b_values");

    const out_len = a_len + b_len - 1;
    var out_buf: [8191]f32 = undefined;
    _ = dsp.convolve(a_buf[0..a_len], b_buf[0..b_len], out_buf[0..out_len]);

    return make_ok(env, make_float_list(env, out_buf[0..out_len]));
}

// ---------------------------------------------------------------------------
// NIF: nif_dsp_mix/2 — (streams_list_of_lists, matrix_list_of_lists)
// ---------------------------------------------------------------------------
// This is complex to marshal — for now, delegate to Elixir.
// The SIMD benefit for mixing is mainly at >8 streams which is uncommon.

fn nif_dsp_mix(env: ?*ErlNifEnv, _: c_int, _ : [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    return make_error(env, "not_implemented_use_elixir");
}

// ---------------------------------------------------------------------------
// NIF: nif_neural_init_model/1 — (sample_rate)
// ---------------------------------------------------------------------------

fn nif_neural_init_model(env: ?*ErlNifEnv, _: c_int, _ : [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    // Serialize the initial denoiser state to a portable binary format.
    // No unsafe pointer casts — uses explicit byte-level serialization.
    const state = neural.DenoiserState.init();

    var bin: ErlNifBinary = undefined;
    if (c.enif_alloc_binary(neural.DenoiserState.SERIALIZED_SIZE, &bin) == 0)
        return make_error(env, "alloc_failed");

    var out_buf: [neural.DenoiserState.SERIALIZED_SIZE]u8 = undefined;
    state.serialize(&out_buf);
    @memcpy(bin.data[0..neural.DenoiserState.SERIALIZED_SIZE], &out_buf);

    return make_ok(env, c.enif_make_binary(env, &bin));
}

// ---------------------------------------------------------------------------
// NIF: nif_neural_denoise/3 — (pcm_list, sample_rate, model_state_binary)
// ---------------------------------------------------------------------------

fn nif_neural_denoise(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    // Get PCM samples.
    var list_len: c_uint = undefined;
    if (c.enif_get_list_length(env, argv[0], &list_len) == 0) return make_error(env, "bad_pcm");

    const n: usize = @intCast(list_len);
    if (n != 960) return make_error(env, "frame_must_be_960_samples");

    var pcm: [960]f32 = undefined;
    _ = get_float_list(env, argv[0], &pcm) orelse return make_error(env, "bad_pcm_values");

    // Get model state from binary — safe deserialization, no pointer casts.
    var state_bin: ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, argv[2], &state_bin) == 0) return make_error(env, "bad_state");
    if (state_bin.size != neural.DenoiserState.SERIALIZED_SIZE) return make_error(env, "invalid_state_size");

    // Deserialize state from portable binary format.
    var state_bytes: [neural.DenoiserState.SERIALIZED_SIZE]u8 = undefined;
    @memcpy(&state_bytes, state_bin.data[0..neural.DenoiserState.SERIALIZED_SIZE]);
    var state = neural.DenoiserState.deserialize(&state_bytes);

    var output: [960]f32 = undefined;
    neural.denoise_frame(&pcm, &output, &state);

    // Serialize updated state back to binary.
    var new_state_bin: ErlNifBinary = undefined;
    if (c.enif_alloc_binary(neural.DenoiserState.SERIALIZED_SIZE, &new_state_bin) == 0)
        return make_error(env, "alloc_failed");

    var new_state_bytes: [neural.DenoiserState.SERIALIZED_SIZE]u8 = undefined;
    state.serialize(&new_state_bytes);
    @memcpy(new_state_bin.data[0..neural.DenoiserState.SERIALIZED_SIZE], &new_state_bytes);

    const pcm_term = make_float_list(env, &output);
    const state_term = c.enif_make_binary(env, &new_state_bin);
    const result = c.enif_make_tuple2(env, pcm_term, state_term);

    return make_ok(env, result);
}

// ---------------------------------------------------------------------------
// NIF: nif_compress_lz4/1 — (binary)
// ---------------------------------------------------------------------------

fn nif_compress_lz4(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var bin: ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, argv[0], &bin) == 0)
        return make_error(env, "bad_binary");

    if (bin.size == 0) return make_error(env, "empty_input");

    // Allocate output buffer (worst case: input + overhead).
    const max_out = compression.lz4_compress_bound(bin.size);
    var out_bin: ErlNifBinary = undefined;
    if (c.enif_alloc_binary(max_out, &out_bin) == 0)
        return make_error(env, "alloc_failed");

    const compressed_len = compression.lz4_compress(
        bin.data[0..bin.size],
        out_bin.data[0..max_out],
    );

    if (compressed_len == 0) {
        c.enif_release_binary(&out_bin);
        return make_error(env, "compress_failed");
    }

    // Shrink to actual size.
    if (c.enif_realloc_binary(&out_bin, compressed_len) == 0) {
        c.enif_release_binary(&out_bin);
        return make_error(env, "realloc_failed");
    }

    return make_ok(env, c.enif_make_binary(env, &out_bin));
}

// ---------------------------------------------------------------------------
// NIF: nif_decompress_lz4/2 — (compressed_binary, original_size)
// ---------------------------------------------------------------------------

fn nif_decompress_lz4(env: ?*ErlNifEnv, _: c_int, argv: [*c]const ERL_NIF_TERM) callconv(.c) ERL_NIF_TERM {
    var bin: ErlNifBinary = undefined;
    if (c.enif_inspect_binary(env, argv[0], &bin) == 0)
        return make_error(env, "bad_binary");

    var orig_size_int: c_int = undefined;
    if (c.enif_get_int(env, argv[1], &orig_size_int) == 0)
        return make_error(env, "bad_size");

    const original_size: usize = @intCast(orig_size_int);
    if (original_size == 0 or original_size > 10 * 1024 * 1024) // 10MB limit
        return make_error(env, "invalid_size");

    var out_bin: ErlNifBinary = undefined;
    if (c.enif_alloc_binary(original_size, &out_bin) == 0)
        return make_error(env, "alloc_failed");

    const decompressed_len = compression.lz4_decompress(
        bin.data[0..bin.size],
        out_bin.data[0..original_size],
        original_size,
    );

    if (decompressed_len == 0) {
        c.enif_release_binary(&out_bin);
        return make_error(env, "decompress_failed");
    }

    if (decompressed_len != original_size) {
        if (c.enif_realloc_binary(&out_bin, decompressed_len) == 0) {
            c.enif_release_binary(&out_bin);
            return make_error(env, "realloc_failed");
        }
    }

    return make_ok(env, c.enif_make_binary(env, &out_bin));
}

// ---------------------------------------------------------------------------
// NIF function table
// ---------------------------------------------------------------------------

var nif_funcs = [_]c.ErlNifFunc{
    .{ .name = "nif_available", .arity = 0, .fptr = nif_available, .flags = 0 },
    .{ .name = "nif_audio_encode", .arity = 4, .fptr = nif_audio_encode, .flags = 0 },
    .{ .name = "nif_audio_decode", .arity = 3, .fptr = nif_audio_decode, .flags = 0 },
    .{ .name = "nif_audio_echo_cancel", .arity = 3, .fptr = nif_audio_echo_cancel, .flags = 0 },
    .{ .name = "nif_dsp_fft", .arity = 2, .fptr = nif_dsp_fft, .flags = 0 },
    .{ .name = "nif_dsp_ifft", .arity = 2, .fptr = nif_dsp_ifft, .flags = 0 },
    .{ .name = "nif_dsp_convolve", .arity = 2, .fptr = nif_dsp_convolve, .flags = 0 },
    .{ .name = "nif_dsp_mix", .arity = 2, .fptr = nif_dsp_mix, .flags = 0 },
    .{ .name = "nif_neural_init_model", .arity = 1, .fptr = nif_neural_init_model, .flags = 0 },
    .{ .name = "nif_neural_denoise", .arity = 3, .fptr = nif_neural_denoise, .flags = 0 },
    .{ .name = "nif_compress_lz4", .arity = 1, .fptr = nif_compress_lz4, .flags = 0 },
    .{ .name = "nif_decompress_lz4", .arity = 2, .fptr = nif_decompress_lz4, .flags = 0 },
};

// ---------------------------------------------------------------------------
// NIF initialisation (ERL_NIF_INIT equivalent)
// ---------------------------------------------------------------------------

export fn nif_init() *const c.ErlNifEntry {
    const entry = struct {
        var e: c.ErlNifEntry = .{
            .major = c.ERL_NIF_MAJOR_VERSION,
            .minor = c.ERL_NIF_MINOR_VERSION,
            .name = "Elixir.Burble.Coprocessor.ZigBackend",
            .num_of_funcs = nif_funcs.len,
            .funcs = &nif_funcs,
            .load = null,
            .reload = null,
            .upgrade = null,
            .unload = null,
            .vm_variant = "beam.vanilla",
            .options = 1, // ERL_NIF_ENTRY_OPTIONS
            .sizeof_ErlNifResourceTypeInit = @sizeOf(c.ErlNifResourceTypeInit),
            .min_erts = "erts-13.0",
        };
    };
    return &entry.e;
}
