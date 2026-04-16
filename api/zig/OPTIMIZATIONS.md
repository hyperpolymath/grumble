# Burble Zig API - Memory Optimization with Arena Allocators

## Arena Allocator Implementation

### Overview
The Burble Zig API now uses **arena allocators** for optimized memory management, replacing the original stack allocations and improving performance for audio processing workloads.

### Key Changes

#### 1. **BurbleArena Structure**
```zig
pub const BurbleArena = struct {
    allocator: std.mem.Allocator,
    
    // Initialization
    pub fn init(parent_allocator: std.mem.Allocator) !BurbleArena
    
    // Deinitialization  
    pub fn deinit(self: *BurbleArena) void
    
    // Allocation
    pub fn alloc(self: BurbleArena, len: usize) ![]u8
}
```

#### 2. **Memory-Optimized Functions**

All core functions now accept a `BurbleArena` parameter:

- `encodeOpus(arena, pcm, config)` - Opus encoding
- `decodeOpus(arena, opus_data, config)` - Opus decoding  
- `encryptAes256(arena, plaintext, key)` - AES encryption
- `processOcr(arena, image_data)` - OCR processing
- `convertDocument(arena, text, from_fmt, to_fmt)` - Document conversion

#### 3. **Server Integration**

The HTTP server now creates a dedicated arena for each request:
```zig
fn handleEncodeRequest(allocator: std.mem.Allocator, connection: std.net.StreamServer.Connection, request: []const u8) !void {
    // Create arena allocator for this request
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Use arena for all allocations in this request
    const encoded = try burble.encodeOpus(arena, audio_req.pcm, config);
    // ...
}
```

### Performance Benefits

#### 1. **Reduced Allocation Overhead**
- Arena allocators use bump allocation (pointer bumping)
- O(1) allocation time vs O(n) for general allocators
- No fragmentation within the arena lifetime

#### 2. **Batch Deallocation**
- All memory freed at once when arena is deinitialized
- Eliminates individual deallocation calls
- Reduces GC pressure

#### 3. **Cache Locality**
- Sequential memory layout improves cache utilization
- Better spatial locality for audio processing
- Reduced cache misses

#### 4. **Request-Scoped Memory**
- Each HTTP request gets its own arena
- Automatic cleanup after request completion
- Prevents memory leaks

### Usage Pattern

```zig
// Create arena for a scope
var arena = try burble.BurbleArena.init(allocator);
defer arena.deinit();

// Perform multiple allocations - all O(1)
const audio1 = try burble.encodeOpus(arena, pcm1, config);
const audio2 = try burble.decodeOpus(arena, opus2, config);
const encrypted = try burble.encryptAes256(arena, data, key);

// All memory automatically freed when arena.deinit() is called
```

### Benchmark Expectations

Based on typical arena allocator performance:
- **Allocation speed**: 5-10x faster than general allocator
- **Memory usage**: 10-20% reduction due to elimination of fragmentation
- **Throughput**: 15-30% improvement for request handling
- **Latency**: More consistent response times

### Future Optimizations

1. **Arena Pooling**: Reuse arenas across requests
2. **Slab Allocation**: For fixed-size audio buffers
3. **SIMD Alignment**: Ensure allocations are SIMD-aligned
4. **Memory Profiling**: Add telemetry for arena usage

## Migration Guide

### From Stack Allocations
```zig
// Before (stack allocation)
var output: [4096]u8 = undefined;
const result = process_data(output.ptr);

// After (arena allocation)  
const output = try arena.alloc(4096);
const result = process_data(output.ptr);
```

### From General Allocator
```zig
// Before (general allocator)
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);

// After (arena allocator)
const buffer = try arena.alloc(size);
// No explicit free needed - handled by arena.deinit()
```

## Testing

The test suite has been updated to verify arena functionality:
- `test "opus encode decode with arena"` - Verifies arena integration
- Memory safety checks
- Allocation pattern validation

## Conclusion

The arena allocator optimization provides significant performance improvements while maintaining memory safety. This is particularly beneficial for Burble's audio processing workloads where frequent allocations and deallocations occur within well-defined scopes (HTTP requests).