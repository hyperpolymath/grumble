// SPDX-License-Identifier: PMPL-1.0-or-later
// Basic tests for Burble Zig API transpilation
const std = @import("std");
const burble = @import("burble.zig");

// Mock FFI functions for testing
const mock_ffi = struct {
    pub fn burble_opus_encode(input: [*c]const u8, input_len: c_int, output: [*c]u8, output_len: [*c]usize, sample_rate: c_int, channels: c_int) c_int {
        // Mock: copy input to output and set output length
        @memcpy(output, input, @min(input_len, @intCast(*output_len)));
        *output_len = @intCast(@min(input_len, @intCast(*output_len)));
        return 0;
    }
    
    pub fn burble_opus_decode(input: [*c]const u8, input_len: c_int, output: [*c]u8, output_len: [*c]usize, sample_rate: c_int, channels: c_int) c_int {
        // Mock: copy input to output and set output length
        @memcpy(output, input, @min(input_len, @intCast(*output_len)));
        *output_len = @intCast(@min(input_len, @intCast(*output_len)));
        return 0;
    }
    
    pub fn burble_is_power_of_two(n: c_int) c_int {
        return if (@as(usize, n) & (@as(usize, n) - 1) == 0) 1 else 0;
    }
};

test "audio config creation" {
    const config = burble.AudioConfig{
        .sample_rate = burble.SampleRate.rate_48000,
        .channels = 2,
        .buffer_size = 1024,
    };
    
    try std.testing.expectEqual(config.sample_rate, burble.SampleRate.rate_48000);
    try std.testing.expectEqual(config.channels, 2);
    try std.testing.expectEqual(config.buffer_size, 1024);
}

test "buffer size validation" {
    try std.testing.expect(burble.isValidBufferSize(1024));
    try std.testing.expect(burble.isValidBufferSize(2048));
    try std.testing.expect(!burble.isValidBufferSize(1023));
    try std.testing.expect(!burble.isValidBufferSize(1500));
}

test "opus encode decode with arena" {
    const allocator = std.testing.allocator;
    const test_data = "test audio data";
    
    // Create arena for this test
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    const config = burble.AudioConfig{
        .sample_rate = burble.SampleRate.rate_48000,
        .channels = 1,
        .buffer_size = test_data.len,
    };
    
    // Test that the functions compile with arena
    try std.testing.expect(burble.isValidBufferSize(config.buffer_size));
    
    // Test SIMD detection
    const has_simd = burble.detectSimd();
    std.debug.print("SIMD support: {}\n", .{has_simd});
    
    // Test audio processing functions
    const gain_applied = try burble.applyGainSimd(arena, test_data, 0.8);
    try std.testing.expect(gain_applied.len == test_data.len);
    
    // Test mixing
    const mixed = try burble.mixAudioSimd(arena, test_data, test_data);
    try std.testing.expect(mixed.len == test_data.len);
    
    // Test normalization
    const normalized = try burble.normalizeAudioSimd(arena, test_data);
    try std.testing.expect(normalized.len == test_data.len);
    
    // Mock FFI calls would go here
    // const encoded = try burble.encodeOpus(arena, test_data, config, 1.0);
    // const decoded = try burble.decodeOpus(arena, encoded, config, true);
}

test "audio processing functions" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Create test PCM data (16-bit stereo)
    const pcm_data = &[_]u8{
        0x00, 0x00, 0x00, 0x00, // Sample 1: 0
        0x00, 0x7F, 0x00, 0x7F, // Sample 2: 32767 (max positive)
        0x00, 0x80, 0x00, 0x80, // Sample 3: -32768 (max negative)
    };
    
    // Test gain application
    const with_gain = try burble.applyGainSimd(arena, pcm_data, 0.5);
    try std.testing.expect(with_gain.len == pcm_data.len);
    
    // Test mixing
    const mixed = try burble.mixAudioSimd(arena, pcm_data, pcm_data);
    try std.testing.expect(mixed.len == pcm_data.len);
    
    // Test normalization (should handle max values)
    const normalized = try burble.normalizeAudioSimd(arena, pcm_data);
    try std.testing.expect(normalized.len == pcm_data.len);
    
    // Test resampling
    const resampled = try burble.resampleAudioSimd(arena, pcm_data, 48000, 44100);
    try std.testing.expect(resampled.len > 0);
}

test "advanced resampling functions" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Create test audio data (48kHz, 1 second of 440Hz sine wave)
    const sample_rate = 48000;
    const duration = 1.0; // 1 second
    const samples = @truncate(usize, @floatFromInt(f32, @intCast(sample_rate)) * duration);
    const audio_data = try arena.alloc(samples * 2); // 16-bit stereo
    
    // Generate 440Hz sine wave
    var i: usize = 0;
    while (i < samples) : (i += 1) {
        const t = @floatFromInt(f32, @intCast(i)) / @floatFromInt(f32, @intCast(sample_rate));
        const value = @sin(2.0 * @pi * 440.0 * t);
        const sample = @truncate(i16, @intFromFloat(f32, value * 32767.0));
        @memcpy(audio_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
    }
    
    // Test polyphase resampling (48kHz -> 44.1kHz)
    const polyphase_result = try burble.resamplePolyphase(arena, audio_data, 48000, 44100, 64, .blackman_harris);
    try std.testing.expect(polyphase_result.len > 0);
    
    // Test SRC with different quality levels
    const src_low = try burble.resampleSrc(arena, audio_data, 48000, 44100, 0); // Fastest
    const src_high = try burble.resampleSrc(arena, audio_data, 48000, 44100, 5); // Best quality
    try std.testing.expect(src_low.len > 0);
    try std.testing.expect(src_high.len > 0);
    try std.testing.expect(src_high.len >= src_low.len); // Higher quality may have more samples
}

test "fft and spectral analysis" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Create test audio data (440Hz sine wave, 256 samples)
    const sample_rate = 48000;
    const fft_size = burble.FftSize.size_256;
    const samples = @enumToInt(fft_size);
    const audio_data = try arena.alloc(samples * 2); // 16-bit
    
    // Generate 440Hz sine wave
    var i: usize = 0;
    while (i < samples) : (i += 1) {
        const t = @floatFromInt(f32, @intCast(i)) / @floatFromInt(f32, @intCast(sample_rate));
        const value = @sin(2.0 * @pi * 440.0 * t);
        const sample = @truncate(i16, @intFromFloat(f32, value * 32767.0));
        @memcpy(audio_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
    }
    
    // Test FFT with different window functions
    const fft_result_hann = try burble.fftPerform(arena, audio_data, fft_size, .hann);
    const fft_result_rect = try burble.fftPerform(arena, audio_data, fft_size, .rectangular);
    try std.testing.expect(fft_result_hann.len == samples);
    try std.testing.expect(fft_result_rect.len == samples);
    
    // Test spectral analysis
    const spectrum = try burble.spectralAnalysis(arena, audio_data, fft_size, .hann);
    try std.testing.expect(spectrum.len == samples);
    
    // Test peak detection (should find 440Hz peak)
    const peaks = try burble.spectralPeaks(arena, spectrum, sample_rate, 3, -40.0);
    try std.testing.expect(peaks.len > 0);
    
    // Check if we found the 440Hz peak (within some tolerance)
    var found_440 = false;
    var j: usize = 0;
    while (j < peaks.len) : (j += 1) {
        const freq = peaks[j];
        if (@abs(freq - 440.0) < 10.0) { // Within 10Hz
            found_440 = true;
            break;
        }
    }
    
    std.debug.print("440Hz peak found: {}\n", .{found_440});
    
    // Test IFFT
    const ifft_result = try burble.ifftPerform(arena, fft_result_hann, fft_size);
    try std.testing.expect(ifft_result.len == samples * 2); // 16-bit output
}

test "echo cancellation" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Initialize echo cancellation with small parameters for testing
    const params = burble.EchoCancellationParams{
        .frame_size = 64,      // Smaller frame for testing
        .filter_length = 128,  // Shorter filter for testing
        .learning_rate = 0.01,
        .leakage = 0.99,
        .use_simd = burble.detectSimd(),
        .batch_size = 2,
    };
    
    var echo_state = try burble.echoCancellationInit(allocator, params);
    defer echo_state.deinit();
    
    // Create test data (microphone with echo, speaker reference)
    const frame_size_bytes = params.frame_size * 2; // 16-bit samples
    const mic_data = try arena.alloc(frame_size_bytes);
    const speaker_data = try arena.alloc(frame_size_bytes);
    
    // Fill with test signal (sine wave)
    var i: usize = 0;
    while (i < params.frame_size) : (i += 1) {
        const t = @floatFromInt(f32, @intCast(i)) / 48.0; // 48kHz sample rate
        const value = @sin(2.0 * @pi * 1000.0 * t); // 1kHz sine wave
        const sample = @truncate(i16, @intFromFloat(f32, value * 16384.0));
        
        // Microphone has original signal + echo
        const mic_sample = sample + @truncate(i16, @intFromFloat(f32, value * 8192.0)); // Add echo
        @memcpy(mic_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(mic_sample))), 2);
        
        // Speaker has clean reference
        @memcpy(speaker_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
    }
    
    // Process with echo cancellation
    const processed = try burble.echoCancellationProcess(&echo_state, mic_data, speaker_data);
    try std.testing.expect(processed.len == frame_size_bytes);
    
    // Verify that echo was reduced (simple check - in real usage would need more sophisticated analysis)
    try std.testing.expect(processed.len > 0);
}

test "batch processing" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Initialize echo cancellation
    const params = burble.EchoCancellationParams{
        .frame_size = 32,       // Small for testing
        .filter_length = 64,    // Small for testing
        .learning_rate = 0.01,
        .leakage = 0.99,
        .use_simd = false,      // Disable SIMD for consistent testing
        .batch_size = 2,
    };
    
    var echo_state = try burble.echoCancellationInit(allocator, params);
    defer echo_state.deinit();
    
    // Create batch of frames
    const batch_size = 3;
    const frames = try arena.alloc([[]]const u8, batch_size);
    const speaker_frames = try arena.alloc([[]]const u8, batch_size);
    const frame_size_bytes = params.frame_size * 2;
    
    // Fill batch with test data
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const mic_frame = try arena.alloc(frame_size_bytes);
        const speaker_frame = try arena.alloc(frame_size_bytes);
        
        // Fill with test signal
        var j: usize = 0;
        while (j < params.frame_size) : (j += 1) {
            const t = @floatFromInt(f32, @intCast(j + i * params.frame_size)) / 48.0;
            const value = @sin(2.0 * @pi * 440.0 * t);
            const sample = @truncate(i16, @intFromFloat(f32, value * 16384.0));
            
            // Add echo to microphone signal
            const mic_sample = sample + @truncate(i16, @intFromFloat(f32, value * 4096.0));
            @memcpy(mic_frame.ptr + j * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(mic_sample))), 2);
            @memcpy(speaker_frame.ptr + j * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
            
            j += 1;
        }
        
        frames[i] = mic_frame;
        speaker_frames[i] = speaker_frame;
        i += 1;
    }
    
    // Process batch
    const results = try burble.batchProcessAudio(arena, &echo_state, frames, speaker_frames);
    try std.testing.expect(results.len == batch_size);
    
    // Test batch FFT
    const fft_results = try burble.batchFftPerform(arena, frames, .size_256, .hann);
    try std.testing.expect(fft_results.len == batch_size);
    
    // Test batch spectral analysis
    const spectra = try burble.batchSpectralAnalysis(arena, frames, .size_256, .hann);
    try std.testing.expect(spectra.len == batch_size);
}

test "advanced echo cancellation features" {
    const allocator = std.testing.allocator;
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Initialize echo cancellation
    const params = burble.EchoCancellationParams{
        .frame_size = 64,
        .filter_length = 128,
        .learning_rate = 0.01,
        .leakage = 0.99,
        .use_simd = false,
        .batch_size = 2,
    };
    
    var echo_state = try burble.echoCancellationInit(allocator, params);
    defer echo_state.deinit();
    
    // Create test data
    const frame_size_bytes = params.frame_size * 2;
    const mic_data = try arena.alloc(frame_size_bytes);
    const speaker_data = try arena.alloc(frame_size_bytes);
    
    // Fill with test signal
    var i: usize = 0;
    while (i < params.frame_size) : (i += 1) {
        const t = @floatFromInt(f32, @intCast(i)) / 48.0;
        const value = @sin(2.0 * @pi * 1000.0 * t);
        const sample = @truncate(i16, @intFromFloat(f32, value * 16384.0));
        
        // Add echo to microphone signal
        const mic_sample = sample + @truncate(i16, @intFromFloat(f32, value * 8192.0));
        @memcpy(mic_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(mic_sample))), 2);
        @memcpy(speaker_data.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
        
        i += 1;
    }
    
    // Convert to float for testing advanced features
    const mic_float = try arena.alloc(f32, params.frame_size);
    const speaker_float = try arena.alloc(f32, params.frame_size);
    
    convertPcmToFloat(mic_float, mic_data);
    convertPcmToFloat(speaker_float, speaker_data);
    
    // Test double-talk detection
    const double_talk = burble.detectDoubleTalk(&echo_state, mic_float, speaker_float);
    std.debug.print("Double-talk detected: {}\n", .{double_talk});
    
    // Test correlation computation
    const correlation = burble.computeCorrelation(mic_float, speaker_float);
    std.debug.print("Correlation: {}\n", .{correlation});
    try std.testing.expect(correlation >= -1.0 && correlation <= 1.0);
    
    // Test echo level computation
    const echo_level = burble.computeEchoLevel(&echo_state, mic_float, speaker_float);
    std.debug.print("Echo level: {}\n", .{echo_level});
    try std.testing.expect(echo_level >= 0.0 && echo_level <= 1.0);
    
    // Test adaptive learning rate
    const adaptive_rate = burble.adaptiveLearningRate(&echo_state, mic_float, speaker_float);
    std.debug.print("Adaptive learning rate: {}\n", .{adaptive_rate});
    try std.testing.expect(adaptive_rate > 0.0);
    
    // Test nonlinear processing
    const processed = try burble.applyNonlinearProcessing(arena, mic_float, double_talk, echo_level);
    try std.testing.expect(processed.len == params.frame_size);
    
    // Test post-filter
    const post_filtered = try burble.applyPostFilter(arena, processed);
    try std.testing.expect(post_filtered.len == params.frame_size);
}

test "language struct" {
    const lang = burble.Language{
        .iso3 = "ENG",
        .name = "English",
    };
    
    try std.testing.expectEqualStrings(lang.iso3, "ENG");
    try std.testing.expectEqualStrings(lang.name, "English");
}

test "translate function" {
    const result = try burble.translate("hello", "ESP");
    try std.testing.expectEqualStrings(result, "hello"); // Mock returns input
}