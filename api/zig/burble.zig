// Batch Processing Optimizations
// ============================================================================

/// batch_process_audio processes multiple audio frames efficiently
pub fn batchProcessAudio(arena: BurbleArena, 
                         echo_state: *EchoCancellationState,
                         frames: [][]const u8, 
                         speaker_frames: [][]const u8) ![][]u8 {
=======
// ============================================================================
// Nonlinear Processing - Comfort Noise & Residual Suppression
// ============================================================================

/// apply_nonlinear_processing applies comfort noise and residual echo suppression
fn applyNonlinearProcessing(arena: BurbleArena, error_signal: []const f32, 
                             double_talk: bool, echo_level: f32) ![]f32 {
    const frame_size = error_signal.len;
    const output = try arena.alloc(f32, frame_size);
    
    // Apply comfort noise generator
    const comfort_noise = generateComfortNoise(arena, frame_size, double_talk);
    
    // Apply residual echo suppression
    var i: usize = 0;
    while (i < frame_size) : (i += 1) {
        // Suppress residual echo based on echo level
        const suppression_factor = if (echo_level > 0.3) {
            0.5 // Aggressive suppression when echo is strong
        } else if (echo_level > 0.1) {
            0.7 // Moderate suppression
        } else {
            0.9 // Light suppression
        };
        
        // Apply suppression and add comfort noise
        const suppressed = error_signal[i] * suppression_factor;
        output[i] = suppressed + comfort_noise[i] * (if (double_talk) 0.3 else 0.1);
        
        i += 1;
    }
    
    return output;
}

/// generate_comfort_noise generates comfort noise to mask residual echo
fn generateComfortNoise(arena: BurbleArena, length: usize, double_talk: bool) ![]f32 {
    const noise = try arena.alloc(f32, length);
    
    // Simple pseudo-random noise generator
    // In production, use a proper PRNG
    var seed: u32 = 12345;
    var i: usize = 0;
    while (i < length) : (i += 1) {
        // Simple LCG (Linear Congruential Generator)
        seed = 1664525 * seed + 1013904223;
        const random_val = @floatFromInt(f32, @intCast(seed)) / 4294967296.0;
        
        // Scale noise appropriately
        const noise_level = if (double_talk) {
            0.0001 // Lower noise during double-talk
        } else {
            0.0005 // Normal comfort noise level
        };
        
        // Band-limited noise (simple high-pass)
        noise[i] = (random_val - 0.5) * noise_level;
        
        i += 1;
    }
    
    return noise;
}

/// apply_post_filter applies additional filtering to clean up residual artifacts
fn applyPostFilter(arena: BurbleArena, signal: []const f32) ![]f32 {
    const frame_size = signal.len;
    const output = try arena.alloc(f32, frame_size);
    
    // Simple single-pole high-pass filter to remove DC offset
    var prev_output: f32 = 0.0;
    const alpha = 0.99; // Filter coefficient
    
    var i: usize = 0;
    while (i < frame_size) : (i += 1) {
        // High-pass filter: y[n] = x[n] - x[n-1] + alpha * y[n-1]
        const high_pass = signal[i] - (if (i > 0) signal[i - 1] else 0.0) + alpha * prev_output;
        
        // Soft clipping to prevent distortion
        output[i] = @tan(high_pass * 0.8) / @tan(0.8); // Soft saturation
        
        prev_output = output[i];
        i += 1;
    }
    
    return output;
}

// ============================================================================
// Batch Processing Optimizations
// ============================================================================

/// batch_process_audio processes multiple audio frames efficiently
pub fn batchProcessAudio(arena: BurbleArena, 
                         echo_state: *EchoCancellationState,
                         frames: [][]const u8, 
                         speaker_frames: [][]const u8) ![][]u8 {Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
/// Now includes optional SIMD pre-processing.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig, gain: ?f32) ![]u8 {
=======
// ============================================================================
// Echo Cancellation with SIMD Optimization
// ============================================================================

/// echo_cancellation_init initializes echo cancellation state
pub fn echoCancellationInit(allocator: std.mem.Allocator, params: EchoCancellationParams) !EchoCancellationState {
    return try EchoCancellationState.init(allocator, params);
}

/// echo_cancellation_process processes audio with echo cancellation
pub fn echoCancellationProcess(state: *EchoCancellationState, 
                               microphone_data: []const u8, 
                               speaker_data: []const u8) ![]u8 {
    if (microphone_data.len != state.params.frame_size * 2 || 
        speaker_data.len != state.params.frame_size * 2) {
        return error.invalid_param;
    }
    
    const output = try state.allocator.alloc(u8, state.params.frame_size * 2);
    
    // Convert 16-bit PCM to float
    const mic_float = try state.allocator.alloc(f32, state.params.frame_size);
    const speaker_float = try state.allocator.alloc(f32, state.params.frame_size);
    
    convertPcmToFloat(mic_float, microphone_data);
    convertPcmToFloat(speaker_float, speaker_data);
    
    // Process with echo cancellation
    if (state.params.use_simd && detectSimd()) {
        try echoCancellationSimd(state, mic_float, speaker_float);
    } else {
        try echoCancellationScalar(state, mic_float, speaker_float);
    }
    
    // Apply advanced features
    const double_talk = detectDoubleTalk(state, mic_float, speaker_float);
    const echo_level = computeEchoLevel(state, mic_float, speaker_float);
    
    // Apply nonlinear processing
    const processed_float = try applyNonlinearProcessing(arena, mic_float, double_talk, echo_level);
    const post_filtered = try applyPostFilter(arena, processed_float);
    
    // Convert back to 16-bit PCM
    convertFloatToPcm(output, post_filtered);
    
    state.allocator.free(mic_float);
    state.allocator.free(speaker_float);
    
    return output;
}

/// echo_cancellation_simd SIMD-optimized echo cancellation
fn echoCancellationSimd(state: *EchoCancellationState, mic_float: []f32, speaker_float: []f32) !void {
    const frame_size = state.params.frame_size;
    const filter_length = state.params.filter_length;
    const learning_rate = state.params.learning_rate;
    const leakage = state.params.leakage;
    
    // Update input history (shift and add new speaker data)
    @memcpy(state.input_history.ptr, state.input_history.ptr + frame_size, 
            (filter_length - frame_size) * @sizeOf(f32));
    @memcpy(state.input_history.ptr + (filter_length - frame_size), speaker_float.ptr, 
            frame_size * @sizeOf(f32));
    
    // Process in batches for better cache utilization
    const batch_size = state.params.batch_size;
    var batch: usize = 0;
    
    while (batch < frame_size) : (batch += batch_size) {
        const batch_end = @min(batch + batch_size, frame_size);
        const batch_size_actual = batch_end - batch;
        
        // Process each sample in the batch
        var i: usize = batch;
        while (i < batch_end) : (i += 1) {
            // Calculate echo estimate using adaptive filter
            var echo_estimate: f32 = 0.0;
            var k: usize = 0;
            
            // Use SIMD for filter convolution when possible
            if (detectSimd() && SimdVectorSize >= 16) {
                // Process in SIMD vectors
                var j: usize = 0;
                while (j + @truncate(usize, SimdVectorSize / @sizeOf(f32)) <= filter_length) : (j += @truncate(usize, SimdVectorSize / @sizeOf(f32))) {
                    const filter_vec = @load(@Vector(@truncate(usize, SimdVectorSize / @sizeOf(f32)), f32), 
                                           @ptrCast([*]const @Vector(@truncate(usize, SimdVectorSize / @sizeOf(f32)), f32), 
                                                    state.filter.ptr + j));
                    const input_vec = @load(@Vector(@truncate(usize, SimdVectorSize / @sizeOf(f32)), f32), 
                                          @ptrCast([*]const @Vector(@truncate(usize, SimdVectorSize / @sizeOf(f32)), f32), 
                                                   state.input_history.ptr + filter_length - frame_size + i - j));
                    
                    // Multiply and accumulate
                    const product = filter_vec * input_vec;
                    var sum: f32 = 0.0;
                    var vec_idx: usize = 0;
                    while (vec_idx < @vectorLen(@Vector(@truncate(usize, SimdVectorSize / @sizeOf(f32)), f32))) : (vec_idx += 1) {
                        sum += product[vec_idx];
                    }
                    echo_estimate += sum;
                    
                    j += @truncate(usize, SimdVectorSize / @sizeOf(f32));
                }
                
                // Process remaining samples
                while (j < filter_length) : (j += 1) {
                    echo_estimate += state.filter[j] * state.input_history[filter_length - frame_size + i - j];
                }
            } else {
                // Scalar fallback
                while (j < filter_length) : (j += 1) {
                    echo_estimate += state.filter[j] * state.input_history[filter_length - frame_size + i - j];
                }
            }
            
            // Subtract echo estimate from microphone signal
            const error = mic_float[i] - echo_estimate;
            
            // Adaptive filter update (NLMS algorithm)
            const power: f32 = computePower(state.input_history[filter_length - frame_size + i - filter_length..][0..filter_length]);
            const mu = if (power > 0.001) learning_rate / power else 0.0;
            
            // Update filter coefficients
            j = 0;
            while (j < filter_length) : (j += 1) {
                const index = filter_length - frame_size + i - j;
                if (index >= 0 && index < filter_length) {
                    state.filter[j] = leakage * state.filter[j] + mu * error * state.input_history[index];
                }
                j += 1;
            }
            
            // Store error signal
            mic_float[i] = error;
        }
    }
    
    // Store output for double-talk detection
    @memcpy(state.output_history.ptr, mic_float.ptr, frame_size * @sizeOf(f32));
}

/// echo_cancellation_scalar scalar fallback implementation
fn echoCancellationScalar(state: *EchoCancellationState, mic_float: []f32, speaker_float: []f32) !void {
    const frame_size = state.params.frame_size;
    const filter_length = state.params.filter_length;
    const learning_rate = state.params.learning_rate;
    const leakage = state.params.leakage;
    
    // Update input history
    @memcpy(state.input_history.ptr, state.input_history.ptr + frame_size, 
            (filter_length - frame_size) * @sizeOf(f32));
    @memcpy(state.input_history.ptr + (filter_length - frame_size), speaker_float.ptr, 
            frame_size * @sizeOf(f32));
    
    // Process each sample
    var i: usize = 0;
    while (i < frame_size) : (i += 1) {
        // Calculate echo estimate
        var echo_estimate: f32 = 0.0;
        var j: usize = 0;
        while (j < filter_length) : (j += 1) {
            echo_estimate += state.filter[j] * state.input_history[filter_length - frame_size + i - j];
        }
        
        // Subtract echo estimate
        const error = mic_float[i] - echo_estimate;
        
        // Adaptive filter update
        const power: f32 = computePower(state.input_history[filter_length - frame_size + i - filter_length..][0..filter_length]);
        const mu = if (power > 0.001) learning_rate / power else 0.0;
        
        // Update filter
        j = 0;
        while (j < filter_length) : (j += 1) {
            const index = filter_length - frame_size + i - j;
            if (index >= 0 && index < filter_length) {
                state.filter[j] = leakage * state.filter[j] + mu * error * state.input_history[index];
            }
            j += 1;
        }
        
        mic_float[i] = error;
    }
    
    // Store output
    @memcpy(state.output_history.ptr, mic_float.ptr, frame_size * @sizeOf(f32));
}

/// compute_power calculates signal power
fn computePower(signal: []const f32) f32 {
    var power: f32 = 0.0;
    var i: usize = 0;
    while (i < signal.len) : (i += 1) {
        power += signal[i] * signal[i];
    }
    return power / @floatFromInt(f32, @intCast(signal.len));
}

/// convert_pcm_to_float converts 16-bit PCM to float
fn convertPcmToFloat(output: []f32, input: []const u8) void {
    var i: usize = 0;
    while (i < output.len) : (i += 1) {
        const sample = @intFromBytes(i16, input[i * 2..][0..2]);
        output[i] = @floatFromInt(f32, @intCast(sample)) / 32768.0;
    }
}

/// convert_float_to_pcm converts float to 16-bit PCM
fn convertFloatToPcm(output: []u8, input: []const f32) void {
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        var sample = @intFromFloat(f32, input[i] * 32767.0);
        sample = @min(@max(sample, -32768), 32767);
        @memcpy(output.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
    }
}

// ============================================================================
// Advanced Double-Talk Detection
// ============================================================================

/// detect_double_talk detects double-talk conditions using energy and correlation
fn detectDoubleTalk(state: *EchoCancellationState, mic_float: []const f32, speaker_float: []const f32) bool {
    const frame_size = state.params.frame_size;
    
    // Calculate energy ratios
    const mic_energy = computePower(mic_float);
    const speaker_energy = computePower(speaker_float);
    const output_energy = computePower(state.output_history[0..frame_size]);
    
    // Energy-based detection: near-end speech likely if mic energy is significantly higher than output
    const energy_ratio = if (output_energy > 0.001) mic_energy / output_energy else 100.0;
    const energy_double_talk = energy_ratio > 3.0; // 3x energy increase suggests near-end speech
    
    // Correlation-based detection
    const correlation = computeCorrelation(mic_float, speaker_float);
    const correlation_double_talk = correlation < 0.5; // Low correlation suggests near-end speech
    
    // Combined decision
    return energy_double_talk && correlation_double_talk;
}

/// compute_correlation calculates cross-correlation between signals
fn computeCorrelation(signal1: []const f32, signal2: []const f32) f32 {
    if (signal1.len != signal2.len || signal1.len == 0) {
        return 0.0;
    }
    
    var sum_product: f32 = 0.0;
    var sum1: f32 = 0.0;
    var sum2: f32 = 0.0;
    var sum1_sq: f32 = 0.0;
    var sum2_sq: f32 = 0.0;
    
    var i: usize = 0;
    while (i < signal1.len) : (i += 1) {
        sum_product += signal1[i] * signal2[i];
        sum1 += signal1[i];
        sum2 += signal2[i];
        sum1_sq += signal1[i] * signal1[i];
        sum2_sq += signal2[i] * signal2[i];
        i += 1;
    }
    
    const n = @floatFromInt(f32, @intCast(signal1.len));
    const numerator = sum_product - (sum1 * sum2) / n;
    const denominator1 = @sqrt(sum1_sq - (sum1 * sum1) / n);
    const denominator2 = @sqrt(sum2_sq - (sum2 * sum2) / n);
    
    if (denominator1 > 0.001 && denominator2 > 0.001) {
        return numerator / (denominator1 * denominator2);
    }
    
    return 0.0;
}

/// adaptive_learning_rate adjusts learning rate based on conditions
fn adaptiveLearningRate(state: *EchoCancellationState, mic_float: []const f32, speaker_float: []const f32) f32 {
    const base_rate = state.params.learning_rate;
    
    // Detect double-talk
    const double_talk = detectDoubleTalk(state, mic_float, speaker_float);
    
    // Adjust learning rate
    if (double_talk) {
        return base_rate * 0.1; // Reduce learning during double-talk
    }
    
    // Check echo level
    const echo_level = computeEchoLevel(state, mic_float, speaker_float);
    if (echo_level > 0.5) { // High echo
        return base_rate * 2.0; // Increase learning when echo is strong
    }
    
    return base_rate; // Normal learning rate
}

/// compute_echo_level estimates echo level relative to near-end speech
fn computeEchoLevel(state: *EchoCancellationState, mic_float: []const f32, speaker_float: []const f32) f32 {
    const frame_size = state.params.frame_size;
    const filter_length = state.params.filter_length;
    
    // Estimate echo power
    var echo_power: f32 = 0.0;
    var i: usize = 0;
    while (i < frame_size) : (i += 1) {
        var echo_estimate: f32 = 0.0;
        var j: usize = 0;
        while (j < filter_length) : (j += 1) {
            const index = filter_length - frame_size + i - j;
            if (index >= 0 && index < filter_length) {
                echo_estimate += state.filter[j] * state.input_history[index];
            }
            j += 1;
        }
        echo_power += echo_estimate * echo_estimate;
        i += 1;
    }
    
    // Compute near-end speech power
    const mic_power = computePower(mic_float);
    const echo_power_normalized = echo_power / @floatFromInt(f32, @intCast(frame_size));
    
    if (mic_power > 0.001) {
        return echo_power_normalized / mic_power;
    }
    
    return 0.0;
}

// ============================================================================
// Batch Processing Optimizations
// ============================================================================

/// batch_process_audio processes multiple audio frames efficiently
pub fn batchProcessAudio(arena: BurbleArena, 
                         echo_state: *EchoCancellationState,
                         frames: [][]const u8, 
                         speaker_frames: [][]const u8) ![][]u8 {
    if (frames.len != speaker_frames.len || frames.len == 0) {
        return error.invalid_param;
    }
    
    const batch_size = frames.len;
    const result = try arena.alloc([[]]u8, batch_size);
    
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const processed = try echoCancellationProcess(echo_state, frames[i], speaker_frames[i]);
        result[i] = processed;
        i += 1;
    }
    
    return result;
}

/// batch_fft_perform performs FFT on multiple frames
pub fn batchFftPerform(arena: BurbleArena, 
                       frames: [][]const u8,
                       fft_size: FftSize,
                       window: WindowFunction) ![][]Complex {
    const batch_size = frames.len;
    const result = try arena.alloc([[]]Complex, batch_size);
    
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const fft_result = try fftPerform(arena, frames[i], fft_size, window);
        result[i] = fft_result;
        i += 1;
    }
    
    return result;
}

/// batch_spectral_analysis performs spectral analysis on multiple frames
pub fn batchSpectralAnalysis(arena: BurbleArena, 
                           frames: [][]const u8,
                           fft_size: FftSize,
                           window: WindowFunction) ![][]f32 {
    const batch_size = frames.len;
    const result = try arena.alloc([[]]f32, batch_size);
    
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const spectrum = try spectralAnalysis(arena, frames[i], fft_size, window);
        result[i] = spectrum;
        i += 1;
    }
    
    return result;
}

// ============================================================================
// Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
/// Now includes optional SIMD pre-processing.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig, gain: ?f32) ![]u8 {FFT Configuration
// ============================================================================

/// FFT size must be power of 2
pub const FftSize = enum {
    size_256 = 256,
    size_512 = 512,
    size_1024 = 1024,
    size_2048 = 2048,
    size_4096 = 4096,
};

/// Complex number type for FFT
pub const Complex = struct {
    re: f32,
    im: f32,
};

/// Window functions for FFT
pub const WindowFunction = enum {
    rectangular,
    hann,
    hamming,
    blackman,
    blackman_harris,
};
=======
// ============================================================================
// Echo Cancellation Configuration
// ============================================================================

/// Echo cancellation parameters
pub const EchoCancellationParams = struct {
    frame_size: usize = 256,          // Samples per frame (16-bit)
    filter_length: usize = 1024,       // Adaptive filter taps
    learning_rate: f32 = 0.01,        // Adaptation speed
    leakage: f32 = 0.999,             // Filter leakage factor
    use_simd: bool = true,             // Enable SIMD optimization
    batch_size: usize = 4,            // Batch processing size
};

/// Echo cancellation state
pub const EchoCancellationState = struct {
    params: EchoCancellationParams,
    filter: []f32,                    // Adaptive filter coefficients
    input_history: []f32,             // Input signal history
    output_history: []f32,           // Output signal history
    allocator: std.mem.Allocator,
    
    /// Initialize echo cancellation state
    pub fn init(allocator: std.mem.Allocator, params: EchoCancellationParams) !EchoCancellationState {
        const filter = try allocator.alloc(f32, params.filter_length);
        const input_history = try allocator.alloc(f32, params.filter_length + params.frame_size);
        const output_history = try allocator.alloc(f32, params.frame_size);
        
        // Initialize filter to zeros
        var i: usize = 0;
        while (i < params.filter_length) : (i += 1) {
            filter[i] = 0.0;
        }
        
        return EchoCancellationState{
            .params = params,
            .filter = filter,
            .input_history = input_history,
            .output_history = output_history,
            .allocator = allocator,
        };
    }
    
    /// Deinitialize and free memory
    pub fn deinit(self: *EchoCancellationState) void {
        self.allocator.free(self.filter);
        self.allocator.free(self.input_history);
        self.allocator.free(self.output_history);
    }
};

// ============================================================================
// FFT Configuration
// ============================================================================

/// FFT size must be power of 2
pub const FftSize = enum {
    size_256 = 256,
    size_512 = 512,
    size_1024 = 1024,
    size_2048 = 2048,
    size_4096 = 4096,
};

/// Complex number type for FFT
pub const Complex = struct {
    re: f32,
    im: f32,
};

/// Window functions for FFT
pub const WindowFunction = enum {
    rectangular,
    hann,
    hamming,
    blackman,
    blackman_harris,
};Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
/// Now includes optional SIMD pre-processing.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig, gain: ?f32) ![]u8 {
=======
// ============================================================================
// FFT Implementation (Radix-2 Decimation-in-Time)
// ============================================================================

/// fft_perform performs FFT on audio data
pub fn fftPerform(arena: BurbleArena, pcm: []const u8, fft_size: FftSize, window: WindowFunction) ![]Complex {
    const size = @enumToInt(fft_size);
    const required_samples = size * 2; // 16-bit samples
    
    if (pcm.len < required_samples) {
        return error.buffer_too_small;
    }
    
    // Apply window function
    const windowed = try applyWindowFunction(arena, pcm[0..required_samples], window);
    
    // Convert to complex numbers (real-only input)
    const input = try arena.alloc(size * @sizeOf(Complex));
    defer arena.deinit(); // Clean up temp allocation
    
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const sample = @intFromBytes(i16, windowed[i * 2..][0..2]);
        const complex_ptr = @ptrCast([*]Complex, @intToPtr([*]u8, input.ptr) + i * @sizeOf(Complex));
        complex_ptr.* = .{
            .re = @floatFromInt(f32, @intCast(sample)),
            .im = 0.0,
        };
    }
    
    // Perform FFT
    const output = try arena.alloc(size * @sizeOf(Complex));
    @memcpy(@ptrCast([*]u8, @intToPtr([*]Complex, output.ptr)), input.ptr, size * @sizeOf(Complex));
    
    try fftRadix2(@ptrCast([*]Complex, @intToPtr([*]Complex, output.ptr)), size);
    
    return @ptrCast([*]Complex, @intToPtr([*]Complex, output.ptr))[0..size];
}

/// fft_radix2 recursive radix-2 FFT implementation
fn fftRadix2(data: [*]Complex, n: usize) !void {
    if (n <= 1) {
        return;
    }
    
    // Even-odd split
    try fftRadix2(data, n / 2);
    try fftRadix2(data + n / 2, n / 2);
    
    var k: usize = 0;
    while (k < n / 2) : (k += 1) {
        const angle = -2.0 * @pi * @floatFromInt(f32, @intCast(k)) / @floatFromInt(f32, @intCast(n));
        const t = Complex{
            .re = @cos(angle),
            .im = @sin(angle),
        };
        
        const even = data[k];
        const odd = data[k + n / 2];
        
        // Butterfly operation
        const t_odd = Complex{
            .re = t.re * odd.re - t.im * odd.im,
            .im = t.re * odd.im + t.im * odd.re,
        };
        
        data[k] = Complex{
            .re = even.re + t_odd.re,
            .im = even.im + t_odd.im,
        };
        
        data[k + n / 2] = Complex{
            .re = even.re - t_odd.re,
            .im = even.im - t_odd.im,
        };
    }
}

/// ifft_perform performs inverse FFT
pub fn ifftPerform(arena: BurbleArena, fft_data: []const Complex, fft_size: FftSize) ![]u8 {
    const size = @enumToInt(fft_size);
    
    if (fft_data.len < size) {
        return error.invalid_param;
    }
    
    // Create working copy
    const input = try arena.alloc(size * @sizeOf(Complex));
    @memcpy(input.ptr, @ptrCast([*]const u8, @intToPtr([*]const Complex, fft_data.ptr)), size * @sizeOf(Complex));
    
    // Conjugate input
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const complex_ptr = @ptrCast([*]Complex, input.ptr + i * @sizeOf(Complex));
        complex_ptr.* = .{
            .re = complex_ptr.re,
            .im = -complex_ptr.im,
        };
    }
    
    // Perform FFT (which gives us IFFT of conjugated input)
    try fftRadix2(@ptrCast([*]Complex, input.ptr), size);
    
    // Conjugate result and normalize
    const output = try arena.alloc(size * 2); // 16-bit output
    
    i = 0;
    while (i < size) : (i += 1) {
        const complex_ptr = @ptrCast([*]Complex, input.ptr + i * @sizeOf(Complex));
        const conj = Complex{
            .re = complex_ptr.re / @floatFromInt(f32, @intCast(size)),
            .im = -complex_ptr.im / @floatFromInt(f32, @intCast(size)),
        };
        
        // Take real part only (imaginary should be near zero)
        const sample = @truncate(i16, @intFromFloat(f32, conj.re));
        @memcpy(output.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(sample))), 2);
    }
    
    return output;
}

/// spectral_analysis performs FFT and returns frequency spectrum
pub fn spectralAnalysis(arena: BurbleArena, pcm: []const u8, fft_size: FftSize, 
                        window: WindowFunction = .hann) ![]f32 {
    const fft_result = try fftPerform(arena, pcm, fft_size, window);
    const size = fft_result.len;
    
    // Calculate magnitude spectrum
    const spectrum = try arena.alloc(size * @sizeOf(f32));
    
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const mag = @sqrt(fft_result[i].re * fft_result[i].re + fft_result[i].im * fft_result[i].im);
        const mag_ptr = @ptrCast([*]f32, spectrum.ptr + i * @sizeOf(f32));
        mag_ptr.* = mag;
    }
    
    return @ptrCast([*]f32, spectrum.ptr)[0..size];
}

/// spectral_peaks finds dominant frequency peaks
pub fn spectralPeaks(arena: BurbleArena, spectrum: []const f32, sample_rate: u32, 
                     max_peaks: usize = 5, threshold_db: f32 = -60.0) ![]f32 {
    if (spectrum.len == 0) {
        return try arena.alloc(0);
    }
    
    // Convert to dB scale
    const db_spectrum = try arena.alloc(spectrum.len * @sizeOf(f32));
    
    var i: usize = 0;
    while (i < spectrum.len) : (i += 1) {
        const mag = spectrum[i];
        const db = if (mag > 0.0) 20.0 * @log10(mag) else -1000.0;
        const db_ptr = @ptrCast([*]f32, db_spectrum.ptr + i * @sizeOf(f32));
        db_ptr.* = db;
    }
    
    // Find peaks
    const peaks = try arena.alloc(max_peaks * @sizeOf(f32));
    var peak_count: usize = 0;
    
    i = 1;
    while (i < spectrum.len - 1 && peak_count < max_peaks) : (i += 1) {
        const db_ptr = @ptrCast([*]f32, db_spectrum.ptr + i * @sizeOf(f32));
        const prev_ptr = @ptrCast([*]f32, db_spectrum.ptr + (i - 1) * @sizeOf(f32));
        const next_ptr = @ptrCast([*]f32, db_spectrum.ptr + (i + 1) * @sizeOf(f32));
        
        if (db_ptr.* > prev_ptr.* && db_ptr.* > next_ptr.* && db_ptr.* > threshold_db) {
            // Found a peak - calculate frequency
            const freq = @floatFromInt(f32, @intCast(sample_rate)) * @floatFromInt(f32, @intCast(i)) / 
                        @floatFromInt(f32, @intCast(spectrum.len));
            
            const peak_ptr = @ptrCast([*]f32, peaks.ptr + peak_count * @sizeOf(f32));
            peak_ptr.* = freq;
            peak_count += 1;
        }
    }
    
    return @ptrCast([*]f32, peaks.ptr)[0..peak_count];
}

// ============================================================================
// Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
/// Now includes optional SIMD pre-processing.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig, gain: ?f32) ![]u8 {SIMD Configuration
// ============================================================================

/// Detect and configure SIMD capabilities
pub inline fn detectSimd() bool {
    return @hasDecl(builtin, "simd");
}

/// SIMD vector size (in bytes) - detected at compile time
pub const SimdVectorSize = comptime {
    if (@hasDecl(builtin, "simd")) {
        // Use native SIMD width (typically 16-64 bytes)
        @break(@sizeOf(@Vector(@sizeOf(u8), @vectorLen(@Vector(@sizeOf(u8), undefined)))));
    } else {
        // Fallback to 16 bytes (128-bit) if no SIMD
        @break(16);
    }
};
=======
// ============================================================================
// SIMD Configuration
// ============================================================================

/// Detect and configure SIMD capabilities
pub inline fn detectSimd() bool {
    return @hasDecl(builtin, "simd");
}

/// SIMD vector size (in bytes) - detected at compile time
pub const SimdVectorSize = comptime {
    if (@hasDecl(builtin, "simd")) {
        // Use native SIMD width (typically 16-64 bytes)
        @break(@sizeOf(@Vector(@sizeOf(u8), @vectorLen(@Vector(@sizeOf(u8), undefined)))));
    } else {
        // Fallback to 16 bytes (128-bit) if no SIMD
        @break(16);
    }
};

// ============================================================================
// FFT Configuration
// ============================================================================

/// FFT size must be power of 2
pub const FftSize = enum {
    size_256 = 256,
    size_512 = 512,
    size_1024 = 1024,
    size_2048 = 2048,
    size_4096 = 4096,
};

/// Complex number type for FFT
pub const Complex = struct {
    re: f32,
    im: f32,
};

/// Window functions for FFT
pub const WindowFunction = enum {
    rectangular,
    hann,
    hamming,
    blackman,
    blackman_harris,
};Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig) ![]u8 {
    // Allocate output buffer (same size as input initially)
    const output = try arena.alloc(pcm.len);
    var out_len: usize = output.len;
    
    const result = c.burble_opus_encode(
        pcm.ptr,
        @intCast(pcm.len),
        output.ptr,
        &out_len,
        @intCast(config.sample_rate),
        @intCast(config.channels)
    );
    
    if (result != 0) {
        return error.OpusEncodeFailed;
    }
    
    return output[0..out_len];
}
=======
// ============================================================================
// SIMD-Optimized Audio Processing
// ============================================================================

/// apply_gain_simd applies volume gain to PCM audio using SIMD
/// This is a pre-processing step that can be applied before encoding
pub fn applyGainSimd(arena: BurbleArena, pcm: []const u8, gain: f32) ![]u8 {
    if (!detectSimd()) {
        // Fallback to scalar implementation if no SIMD
        return applyGainScalar(arena, pcm, gain);
    }
    
    const output = try arena.alloc(pcm.len);
    
    // Convert gain to fixed-point for integer arithmetic
    const gain_fixed = @intFromFloat(f32, gain * 32768.0);
    
    // Process audio using SIMD vectors
    var i: usize = 0;
    while (i + SimdVectorSize <= pcm.len) : (i += SimdVectorSize) {
        // Load SIMD vector
        const vec = @as(@Vector(SimdVectorSize, i16), @load(@Vector(SimdVectorSize, i16), @ptrCast([*]const @Vector(SimdVectorSize, i16), @intToPtr([*]const u8, pcm.ptr + i))));
        
        // Apply gain using fixed-point multiplication
        const gained = @splat(@Vector(SimdVectorSize, i16), gain_fixed) * vec;
        
        // Store result
        @store(@ptrCast([*]@Vector(SimdVectorSize, i16), @intToPtr([*]u8, output.ptr + i)), gained);
    }
    
    // Handle remaining samples (tail)
    while (i < pcm.len) : (i += 1) {
        const sample = @intFromBytes(i16, pcm[i..][0..2]);
        const gained = @truncate(i16, (@intFromFloat(i32, @floatFromInt(f32, @intCast(sample)) * gain)));
        @memcpy(output.ptr + i, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(gained))), 2);
    }
    
    return output;
}

/// apply_gain_scalar fallback implementation for platforms without SIMD
fn applyGainScalar(arena: BurbleArena, pcm: []const u8, gain: f32) ![]u8 {
    const output = try arena.alloc(pcm.len);
    
    var i: usize = 0;
    while (i < pcm.len) : (i += 2) {
        if (i + 1 >= pcm.len) break;
        
        const sample_bytes = pcm[i..][0..2];
        const sample = @intFromBytes(i16, sample_bytes);
        const float_sample = @floatFromInt(f32, @intCast(sample));
        const gained = @truncate(i16, @intFromFloat(f32, float_sample * gain));
        
        @memcpy(output.ptr + i, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(gained))), 2);
    }
    
    return output;
}

/// mix_audio_simd mixes two audio streams using SIMD
pub fn mixAudioSimd(arena: BurbleArena, audio1: []const u8, audio2: []const u8) ![]u8 {
    const min_len = @min(audio1.len, audio2.len);
    const output = try arena.alloc(min_len);
    
    if (!detectSimd()) {
        // Scalar fallback
        var i: usize = 0;
        while (i < min_len) : (i += 1) {
            output[i] = @divExact(@truncate(u8, @intCast(audio1[i]) + @intCast(audio2[i])), 2);
        }
        return output;
    }
    
    // SIMD mixing
    var i: usize = 0;
    while (i + SimdVectorSize <= min_len) : (i += SimdVectorSize) {
        const vec1 = @load(@Vector(SimdVectorSize, u8), @ptrCast([*]const @Vector(SimdVectorSize, u8), audio1.ptr + i));
        const vec2 = @load(@Vector(SimdVectorSize, u8), @ptrCast([*]const @Vector(SimdVectorSize, u8), audio2.ptr + i));
        
        // Average the two vectors
        const mixed = (vec1 + vec2) / 2;
        
        @store(@ptrCast([*]@Vector(SimdVectorSize, u8), output.ptr + i), mixed);
    }
    
    // Handle tail
    while (i < min_len) : (i += 1) {
        output[i] = @divExact(@truncate(u8, @intCast(audio1[i]) + @intCast(audio2[i])), 2);
    }
    
    return output;
}

// ============================================================================
// Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
/// Now includes optional SIMD pre-processing.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig, gain: ?f32) ![]u8 {
    // Apply gain if specified (using SIMD if available)
    const processed_pcm = if (gain) |g| {
        try applyGainSimd(arena, pcm, g)
    } else {
        pcm
    };
    
    // Allocate output buffer (same size as input initially)
    const output = try arena.alloc(processed_pcm.len);
    var out_len: usize = output.len;
    
    const result = c.burble_opus_encode(
        processed_pcm.ptr,
        @intCast(processed_pcm.len),
        output.ptr,
        &out_len,
        @intCast(config.sample_rate),
        @intCast(config.channels)
    );
    
    if (result != 0) {
        return error.OpusEncodeFailed;
    }
    
    return output[0..out_len];
}Types (mirroring Idris2 ABI and V-lang structures)
// ============================================================================

/// Coprocessor operation result codes
pub const CoprocessorResult = enum {
    ok,
    error,
    invalid_param,
    buffer_too_small,
    not_initialised,
    codec_error,
    crypto_error,
    out_of_memory,
};
=======
// ============================================================================
// SIMD Configuration
// ============================================================================

/// Detect and configure SIMD capabilities
pub inline fn detectSimd() bool {
    return @hasDecl(builtin, "simd");
}

/// SIMD vector size (in bytes) - detected at compile time
pub const SimdVectorSize = comptime {
    if (@hasDecl(builtin, "simd")) {
        // Use native SIMD width (typically 16-64 bytes)
        @break(@sizeOf(@Vector(@sizeOf(u8), @vectorLen(@Vector(@sizeOf(u8), undefined)))));
    } else {
        // Fallback to 16 bytes (128-bit) if no SIMD
        @break(16);
    }
};

// ============================================================================
// Types (mirroring Idris2 ABI and V-lang structures)
// ============================================================================

/// Coprocessor operation result codes
pub const CoprocessorResult = enum {
    ok,
    error,
    invalid_param,
    buffer_too_small,
    not_initialised,
    codec_error,
    crypto_error,
    out_of_memory,
};Live Chat Tools (Co-processor supported)
// ============================================================================

/// process_ocr extracts text from an image using co-processor acceleration.
pub fn processOcr(image_data: []const u8) ![]const u8 {
    var output: [4096]u8 = undefined;
    var out_len: usize = output.len;
    
    const result = c.burble_ocr_process(image_data.ptr, @intCast(image_data.len), output.ptr, &out_len);
    
    if (result != 0) {
        return error.OcrProcessingFailed;
    }
    
    return std.mem.trim(u8, output[0..out_len], 0);
}

/// convert_document uses Pandoc functionality for live chat transformations.
pub fn convertDocument(text: []const u8, from_fmt: []const u8, to_fmt: []const u8) ![]const u8 {
    // Allocate output buffer (2x input size)
    var output: [text.len * 2]u8 = undefined;
    var out_len: usize = output.len;
    
    const result = c.burble_pandoc_convert(
        text.ptr,
        @intCast(text.len),
        from_fmt.ptr,
        to_fmt.ptr,
        output.ptr,
        &out_len
    );
    
    if (result != 0) {
        return error.PandocConversionFailed;
    }
    
    return std.mem.trim(u8, output[0..out_len], 0);
}
=======
// ============================================================================
// Memory Management
// ============================================================================

/// BurbleArena provides optimized memory allocation for audio processing
pub const BurbleArena = struct {
    allocator: std.mem.Allocator,
    
    /// Initialize a new arena allocator
    pub fn init(parent_allocator: std.mem.Allocator) !BurbleArena {
        return BurbleArena{
            .allocator = std.heap.ArenaAllocator.init(parent_allocator),
        };
    }
    
    /// Deinitialize the arena
    pub fn deinit(self: *BurbleArena) void {
        const allocator = self.allocator;
        self.allocator = std.mem.Allocator{
            .ptr = null,
            .vtable = null,
        };
        allocator.deinit();
    }
    
    /// Allocate memory from the arena
    pub fn alloc(self: BurbleArena, len: usize) ![]u8 {
        return self.allocator.alloc(u8, len) catch |err| {
            std.debug.print("Arena allocation failed: {}\n", .{err});
            return error.out_of_memory;
        };
    }
};

// ============================================================================
// Live Chat Tools (Co-processor supported with arena optimization)
// ============================================================================

/// process_ocr extracts text from an image using co-processor acceleration.
/// Uses arena allocation for better performance.
pub fn processOcr(arena: BurbleArena, image_data: []const u8) ![]const u8 {
    const output = try arena.alloc(4096);
    var out_len: usize = output.len;
    
    const result = c.burble_ocr_process(image_data.ptr, @intCast(image_data.len), output.ptr, &out_len);
    
    if (result != 0) {
        return error.OcrProcessingFailed;
    }
    
    return output[0..out_len];
}

/// convert_document uses Pandoc functionality for live chat transformations.
/// Uses arena allocation for better performance.
pub fn convertDocument(arena: BurbleArena, text: []const u8, from_fmt: []const u8, to_fmt: []const u8) ![]const u8 {
    // Allocate output buffer (2x input size)
    const output = try arena.alloc(text.len * 2);
    var out_len: usize = output.len;
    
    const result = c.burble_pandoc_convert(
        text.ptr,
        @intCast(text.len),
        from_fmt.ptr,
        to_fmt.ptr,
        output.ptr,
        &out_len
    );
    
    if (result != 0) {
        return error.PandocConversionFailed;
    }
    
    return output[0..out_len];
}SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Burble Zig API — Direct transpilation from V-lang.
// Maintains the same interface but uses native Zig types and error handling.
const std = @import("std");
const c = @cImport({
    @cInclude("burble_ffi.h");
});

// ============================================================================
// Types (mirroring Idris2 ABI and V-lang structures)
// ============================================================================

/// Coprocessor operation result codes
pub const CoprocessorResult = enum {
    ok,
    error,
    invalid_param,
    buffer_too_small,
    not_initialised,
    codec_error,
    crypto_error,
    out_of_memory,
};

/// Supported audio sample rates
pub const SampleRate = enum {
    rate_8000 = 8000,
    rate_16000 = 16000,
    rate_48000 = 48000,
};

/// Audio configuration structure
pub const AudioConfig = struct {
    sample_rate: SampleRate,
    channels: u8, // 1 or 2 only (proven by ABI)
    buffer_size: usize, // Must be power-of-2 (proven by ABI)
};

/// Language representation for internationalization
pub const Language = struct {
    iso3: []const u8,
    name: []const u8,
};

// ============================================================================
// Error Handling
// ============================================================================

/// Custom error set for Burble operations
pub const BurbleError = error{
    OcrProcessingFailed,
    PandocConversionFailed,
    OpusEncodeFailed,
    OpusDecodeFailed,
    EncryptionFailed,
    FileLockdownFailed,
    InvalidBufferSize,
    InvalidAesKey,
};

// ============================================================================
// Internationalization Functions
// ============================================================================

/// translate handles cross-language text alignment via the LOL corpus.
/// In production, this calls the LOL orchestrator.
pub fn translate(text: []const u8, target_iso3: []const u8) ![]const u8 {
    // Direct return for now (placeholder for LOL integration)
    return text;
}

// ============================================================================
// Live Chat Tools (Co-processor supported)
// ============================================================================

/// process_ocr extracts text from an image using co-processor acceleration.
pub fn processOcr(image_data: []const u8) ![]const u8 {
    var output: [4096]u8 = undefined;
    var out_len: usize = output.len;
    
    const result = c.burble_ocr_process(image_data.ptr, @intCast(image_data.len), output.ptr, &out_len);
    
    if (result != 0) {
        return error.OcrProcessingFailed;
    }
    
    return std.mem.trim(u8, output[0..out_len], 0);
}

/// convert_document uses Pandoc functionality for live chat transformations.
pub fn convertDocument(text: []const u8, from_fmt: []const u8, to_fmt: []const u8) ![]const u8 {
    // Allocate output buffer (2x input size)
    var output: [text.len * 2]u8 = undefined;
    var out_len: usize = output.len;
    
    const result = c.burble_pandoc_convert(
        text.ptr,
        @intCast(text.len),
        from_fmt.ptr,
        to_fmt.ptr,
        output.ptr,
        &out_len
    );
    
    if (result != 0) {
        return error.PandocConversionFailed;
    }
    
    return std.mem.trim(u8, output[0..out_len], 0);
}

// ============================================================================
// Security (File Isolation)
// ============================================================================

/// secure_file_send implements executable isolation with chmod lockdown.
pub fn secureFileSend(file_path: []const u8) !void {
    // Convert string to C-style and call chmod
    const c_path = std.mem.dupeZ(u8, file_path);
    defer std.mem.free(c_path);
    
    // chmod to 0o644 (rw-r--r--)
    if (std.os.chmod(c_path, 0o644)) |err| {
        return error.FileLockdownFailed;
    }
}

// ============================================================================
// FFI bindings (direct calls to Zig coprocessor layer)
// ============================================================================

// These are declared in the FFI header and implemented in the coprocessor
// ============================================================================
// Public API Functions
// ============================================================================

/// encode_opus encodes raw PCM audio to Opus format.
/// Uses arena allocation for optimal performance.
pub fn encodeOpus(arena: BurbleArena, pcm: []const u8, config: AudioConfig) ![]u8 {
    // Allocate output buffer (same size as input initially)
    const output = try arena.alloc(pcm.len);
    var out_len: usize = output.len;
    
    const result = c.burble_opus_encode(
        pcm.ptr,
        @intCast(pcm.len),
        output.ptr,
        &out_len,
        @intCast(config.sample_rate),
        @intCast(config.channels)
    );
    
    if (result != 0) {
        return error.OpusEncodeFailed;
    }
    
    return output[0..out_len];
}

/// decode_opus decodes Opus audio to raw PCM.
/// Uses arena allocation for optimal performance.
/// Optionally applies post-processing with SIMD.
pub fn decodeOpus(arena: BurbleArena, opus_data: []const u8, config: AudioConfig, apply_normalization: bool) ![]u8 {
    // Allocate output buffer (10x input size for decoded audio)
    const output = try arena.alloc(opus_data.len * 10);
    var out_len: usize = output.len;
    
    const result = c.burble_opus_decode(
        opus_data.ptr,
        @intCast(opus_data.len),
        output.ptr,
        &out_len,
        @intCast(config.sample_rate),
        @intCast(config.channels)
    );
    
    if (result != 0) {
        return error.OpusDecodeFailed;
    }
    
    // Apply normalization if requested
    const final_output = if (apply_normalization) {
        try normalizeAudioSimd(arena, output[0..out_len])
    } else {
        output[0..out_len]
    };
    
    return final_output;
}

/// normalize_audio_simd normalizes audio to prevent clipping using SIMD
pub fn normalizeAudioSimd(arena: BurbleArena, pcm: []const u8) ![]u8 {
    if (pcm.len == 0) {
        return try arena.alloc(0);
    }
    
    if (!detectSimd()) {
        return normalizeAudioScalar(arena, pcm);
    }
    
    const output = try arena.alloc(pcm.len);
    
    // Find maximum sample value using SIMD
    var max_val: i16 = 0;
    var i: usize = 0;
    
    // Process in SIMD vectors to find max
    while (i + SimdVectorSize <= pcm.len) : (i += SimdVectorSize) {
        const vec = @load(@Vector(SimdVectorSize, i16), @ptrCast([*]const @Vector(SimdVectorSize, i16), pcm.ptr + i));
        
        // Find max in this vector
        var vec_max = vec[0];
        var j: usize = 1;
        while (j < @vectorLen(@Vector(SimdVectorSize, i16))) : (j += 1) {
            if (vec[j] > vec_max) vec_max = vec[j];
            if (-vec[j] > vec_max) vec_max = -vec[j]; // Handle negative values
        }
        
        if (vec_max > max_val) max_val = vec_max;
    }
    
    // Check remaining samples
    while (i < pcm.len) : (i += 2) {
        if (i + 1 >= pcm.len) break;
        const sample = @intFromBytes(i16, pcm[i..][0..2]);
        const abs_sample = if (sample < 0) -sample else sample;
        if (abs_sample > max_val) max_val = abs_sample;
    }
    
    // If no clipping needed, return original
    if (max_val <= 32000) {
        @memcpy(output.ptr, pcm.ptr, pcm.len);
        return output;
    }
    
    // Calculate normalization factor
    const scale = 32000.0 / @floatFromInt(f32, @intCast(max_val));
    
    // Apply normalization using SIMD
    i = 0;
    while (i + SimdVectorSize <= pcm.len) : (i += SimdVectorSize) {
        const vec = @load(@Vector(SimdVectorSize, i16), @ptrCast([*]const @Vector(SimdVectorSize, i16), pcm.ptr + i));
        const scale_fixed = @intFromFloat(f32, scale * 32768.0);
        const normalized = (@splat(@Vector(SimdVectorSize, i16), scale_fixed) * vec) / 32768;
        @store(@ptrCast([*]@Vector(SimdVectorSize, i16), output.ptr + i), normalized);
    }
    
    // Handle tail
    while (i < pcm.len) : (i += 2) {
        if (i + 1 >= pcm.len) break;
        const sample = @intFromBytes(i16, pcm[i..][0..2]);
        const normalized = @truncate(i16, @intFromFloat(f32, @floatFromInt(f32, @intCast(sample)) * scale));
        @memcpy(output.ptr + i, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(normalized))), 2);
    }
    
    return output;
}

/// normalize_audio_scalar fallback for platforms without SIMD
fn normalizeAudioScalar(arena: BurbleArena, pcm: []const u8) ![]u8 {
    if (pcm.len == 0) {
        return try arena.alloc(0);
    }
    
    const output = try arena.alloc(pcm.len);
    
    // Find max sample
    var max_val: i16 = 0;
    var i: usize = 0;
    while (i < pcm.len) : (i += 2) {
        if (i + 1 >= pcm.len) break;
        const sample = @intFromBytes(i16, pcm[i..][0..2]);
        const abs_sample = if (sample < 0) -sample else sample;
        if (abs_sample > max_val) max_val = abs_sample;
    }
    
    // If no clipping needed, return original
    if (max_val <= 32000) {
        @memcpy(output.ptr, pcm.ptr, pcm.len);
        return output;
    }
    
    // Apply normalization
    const scale = 32000.0 / @floatFromInt(f32, @intCast(max_val));
    i = 0;
    while (i < pcm.len) : (i += 2) {
        if (i + 1 >= pcm.len) break;
        const sample = @intFromBytes(i16, pcm[i..][0..2]);
        const normalized = @truncate(i16, @intFromFloat(f32, @floatFromInt(f32, @intCast(sample)) * scale));
        @memcpy(output.ptr + i, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(normalized))), 2);
    }
    
    return output;
}

/// resample_audio_simd resamples audio using linear interpolation with SIMD
pub fn resampleAudioSimd(arena: BurbleArena, pcm: []const u8, original_rate: u32, target_rate: u32) ![]u8 {
    if (original_rate == target_rate) {
        const output = try arena.alloc(pcm.len);
        @memcpy(output.ptr, pcm.ptr, pcm.len);
        return output;
    }
    
    const ratio = @floatFromInt(f32, @intCast(target_rate)) / @floatFromInt(f32, @intCast(original_rate));
    const output_samples = @truncate(usize, @floatFromInt(f32, @intCast(pcm.len / 2)) * ratio);
    const output = try arena.alloc(output_samples * 2);
    
    if (!detectSimd()) {
        return resampleAudioScalar(arena, pcm, original_rate, target_rate);
    }
    
    // SIMD resampling would go here
    // For now, use scalar implementation
    return resampleAudioScalar(arena, pcm, original_rate, target_rate);
}

/// resample_audio_scalar linear interpolation resampling
fn resampleAudioScalar(arena: BurbleArena, pcm: []const u8, original_rate: u32, target_rate: u32) ![]u8 {
    const ratio = @floatFromInt(f32, @intCast(target_rate)) / @floatFromInt(f32, @intCast(original_rate));
    const input_samples = pcm.len / 2;
    const output_samples = @truncate(usize, @floatFromInt(f32, @intCast(input_samples)) * ratio);
    const output = try arena.alloc(output_samples * 2);
    
    var output_idx: usize = 0;
    var input_pos: f32 = 0.0;
    
    while (output_idx < output_samples) : (output_idx += 1) {
        const pos_int = @truncate(usize, input_pos);
        const pos_frac = input_pos - @floatFromInt(f32, @intCast(pos_int));
        
        // Get surrounding samples
        const sample1_pos = @min(pos_int, input_samples - 1) * 2;
        const sample2_pos = @min(pos_int + 1, input_samples - 1) * 2;
        
        const sample1 = @intFromBytes(i16, pcm[sample1_pos..][0..2]);
        const sample2 = @intFromBytes(i16, pcm[sample2_pos..][0..2]);
        
        // Linear interpolation
        const interpolated = @truncate(i16, @intFromFloat(f32, 
            @floatFromInt(f32, @intCast(sample1)) * (1.0 - pos_frac) + 
            @floatFromInt(f32, @intCast(sample2)) * pos_frac
        ));
        
        @memcpy(output.ptr + output_idx * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(interpolated))), 2);
        
        input_pos += 1.0 / ratio;
    }
    
    return output;
}

// ============================================================================
// Advanced Resampling Algorithms
// ============================================================================

/// apply_window_function applies window function to audio data
fn applyWindowFunction(arena: BurbleArena, pcm: []const u8, window: WindowFunction) ![]u8 {
    const output = try arena.alloc(pcm.len);
    const samples = pcm.len / 2;
    
    var i: usize = 0;
    while (i < samples) : (i += 1) {
        const pos = @floatFromInt(f32, @intCast(i)) / @floatFromInt(f32, @intCast(samples));
        
        // Calculate window value
        const window_val = switch (window) {
            .rectangular => 1.0,
            .hann => 0.5 * (1.0 - @cos(@tau * pos)),
            .hamming => 0.54 - 0.46 * @cos(@tau * pos),
            .blackman => 0.42 - 0.5 * @cos(@tau * pos) + 0.08 * @cos(2.0 * @tau * pos),
            .blackman_harris => 0.35875 - 0.48829 * @cos(@tau * pos) + 
                                0.14128 * @cos(2.0 * @tau * pos) - 
                                0.01168 * @cos(3.0 * @tau * pos),
        };
        
        // Read sample
        const sample_pos = i * 2;
        const sample = @intFromBytes(i16, pcm[sample_pos..][0..2]);
        
        // Apply window and store
        const windowed = @truncate(i16, @intFromFloat(f32, @floatFromInt(f32, @intCast(sample)) * window_val));
        @memcpy(output.ptr + sample_pos, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(windowed))), 2);
    }
    
    return output;
}

/// resample_polyphase advanced polyphase resampling
pub fn resamplePolyphase(arena: BurbleArena, pcm: []const u8, original_rate: u32, target_rate: u32, 
                         filter_length: usize = 16, window: WindowFunction = .blackman_harris) ![]u8 {
    if (original_rate == target_rate) {
        const output = try arena.alloc(pcm.len);
        @memcpy(output.ptr, pcm.ptr, pcm.len);
        return output;
    }
    
    const ratio = @floatFromInt(f32, @intCast(target_rate)) / @floatFromInt(f32, @intCast(original_rate));
    const input_samples = pcm.len / 2;
    const output_samples = @truncate(usize, @floatFromInt(f32, @intCast(input_samples)) * ratio);
    const output = try arena.alloc(output_samples * 2);
    
    // Create polyphase filter bank (simplified implementation)
    // In production, this would use pre-computed filters
    const filter = try arena.alloc(filter_length * 2);
    
    // Generate sinc-based filter with window
    var i: usize = 0;
    while (i < filter_length) : (i += 1) {
        const pos = @floatFromInt(f32, @intCast(i - filter_length / 2));
        
        // Sinc function with window
        var sinc_val: f32 = 0.0;
        if (pos != 0.0) {
            sinc_val = @sin(@pi * pos) / (@pi * pos);
        } else {
            sinc_val = 1.0;
        }
        
        // Apply window
        const window_pos = @floatFromInt(f32, @intCast(i)) / @floatFromInt(f32, @intCast(filter_length));
        const window_val = switch (window) {
            .rectangular => 1.0,
            .hann => 0.5 * (1.0 - @cos(@tau * window_pos)),
            .hamming => 0.54 - 0.46 * @cos(@tau * window_pos),
            .blackman => 0.42 - 0.5 * @cos(@tau * window_pos) + 0.08 * @cos(2.0 * @tau * window_pos),
            .blackman_harris => 0.35875 - 0.48829 * @cos(@tau * window_pos) + 
                                0.14128 * @cos(2.0 * @tau * window_pos) - 
                                0.01168 * @cos(3.0 * @tau * window_pos),
        };
        
        const filter_val = sinc_val * window_val;
        const int_val = @truncate(i16, @intFromFloat(f32, filter_val * 32767.0));
        @memcpy(filter.ptr + i * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(int_val))), 2);
    }
    
    // Apply polyphase resampling
    var output_idx: usize = 0;
    var input_pos: f32 = 0.0;
    
    while (output_idx < output_samples) : (output_idx += 1) {
        const center = input_pos;
        var sum: f32 = 0.0;
        
        // Apply filter
        var k: usize = 0;
        while (k < filter_length) : (k += 1) {
            const sample_pos = @truncate(usize, center + @floatFromInt(f32, @intCast(k - filter_length / 2)));
            const clamped_pos = @min(sample_pos, input_samples - 1);
            
            const sample = @intFromBytes(i16, pcm[clamped_pos * 2..][0..2]);
            const filter_val = @intFromBytes(i16, filter.ptr + k * 2..][0..2]);
            
            sum += @floatFromInt(f32, @intCast(sample)) * @floatFromInt(f32, @intCast(filter_val));
        }
        
        // Normalize and store
        const normalized = @truncate(i16, @intFromFloat(f32, sum / 32767.0));
        @memcpy(output.ptr + output_idx * 2, @ptrCast([*]const u8, @intToPtr([*]const i16, @addressOf(normalized))), 2);
        
        input_pos += 1.0 / ratio;
    }
    
    return output;
}

/// resample_src advanced sample rate conversion with quality control
pub fn resampleSrc(arena: BurbleArena, pcm: []const u8, original_rate: u32, target_rate: u32, 
                    quality: u8 = 3) ![]u8 {
    // Quality levels: 0=fastest, 5=best
    const filter_length = switch (quality) {
        0 => 8,
        1 => 16,
        2 => 32,
        3 => 64,
        4 => 128,
        5 => 256,
        else => 64,
    };
    
    // Select window function based on quality
    const window = switch (quality) {
        0, 1 => .hann,
        2, 3 => .hamming,
        4, 5 => .blackman_harris,
        else => .hamming,
    };
    
    return try resamplePolyphase(arena, pcm, original_rate, target_rate, filter_length, window);
}

/// decode_opus decodes Opus audio to raw PCM.
/// Uses arena allocation for optimal performance.
/// Optionally applies post-processing with SIMD.
pub fn decodeOpus(arena: BurbleArena, opus_data: []const u8, config: AudioConfig, apply_normalization: bool) ![]u8 {
    // Allocate output buffer (10x input size for decoded audio)
    const output = try arena.alloc(opus_data.len * 10);
    var out_len: usize = output.len;
    
    const result = c.burble_opus_decode(
        opus_data.ptr,
        @intCast(opus_data.len),
        output.ptr,
        &out_len,
        @intCast(config.sample_rate),
        @intCast(config.channels)
    );
    
    if (result != 0) {
        return error.OpusDecodeFailed;
    }
    
    // Apply normalization if requested
    const final_output = if (apply_normalization) {
        try normalizeAudioSimd(arena, output[0..out_len])
    } else {
        output[0..out_len]
    };
    
    return final_output;
}

/// encrypt_aes256 encrypts data with AES-256.
/// Uses arena allocation for optimal performance.
pub fn encryptAes256(arena: BurbleArena, plaintext: []const u8, key: []const u8) ![]u8 {
    if (key.len != 32) {
        return error.InvalidAesKey;
    }
    
    // Allocate output buffer (input size + 16 bytes for AES block)
    const output = try arena.alloc(plaintext.len + 16);
    
    const result = c.burble_aes_encrypt(
        plaintext.ptr,
        @intCast(plaintext.len),
        key.ptr,
        @intCast(key.len),
        output.ptr
    );
    
    if (result != 0) {
        return error.EncryptionFailed;
    }
    
    return output[0..plaintext.len + 16];
}

/// is_valid_buffer_size checks if a buffer size is power-of-2 (ABI requirement).
pub fn isValidBufferSize(size: usize) bool {
    return c.burble_is_power_of_two(@intCast(size)) == 1;
}
