// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble REST API — Zig implementation.
// Direct transpilation from V-lang using Zig's HTTP server.
const std = @import("std");
const burble = @import("burble.zig");

// ============================================================================
// HTTP Server Implementation
// ============================================================================

/// Audio request structure (equivalent to V-lang AudioRequest)
const AudioRequest = struct {
    pcm: []const u8,
    sample_rate: u32,
    channels: u8,
};

/// HTTP Server with Burble API endpoints
pub fn serve() !void {
    // Create allocator for HTTP operations
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create TCP server
    const address = try std.net.Address.resolveIp("0.0.0.0", 4021);
    const server = try std.net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();
    
    try server.listen(address);
    std.debug.print("Burble Zig API server listening on http://{}:{}\n", .{address, server.local_address});
    
    // Accept connections in a loop
    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();
        
        // Handle each connection in separate async task
        try std.Thread.spawn(.{ .detached = true }, handleConnection, .{allocator, connection});
    }
}

/// Handle individual HTTP connection
fn handleConnection(allocator: std.mem.Allocator, connection: std.net.StreamServer.Connection) !void {
    defer connection.stream.close();
    
    var buffer: [4096]u8 = undefined;
    const bytes_read = try connection.stream.read(&buffer);
    
    if (bytes_read == 0) {
        return;
    }
    
    // Parse HTTP request (simplified - in production use proper HTTP parser)
    const request = std.mem.trim(u8, buffer[0..bytes_read], 0);
    
    // Check if this is a POST request to /encode
    if (std.mem.indexOf(u8, request, "POST /encode") != null) {
        try handleEncodeRequest(allocator, connection, request);
    } else {
        // Simple 404 response
        const not_found = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
        try connection.stream.writeAll(not_found);
    }
}

/// Handle encode request (equivalent to V-lang encode handler)
/// Now uses arena allocation for better performance
fn handleEncodeRequest(allocator: std.mem.Allocator, connection: std.net.StreamServer.Connection, request: []const u8) !void {
    // Create arena allocator for this request
    var arena = try burble.BurbleArena.init(allocator);
    defer arena.deinit();
    
    // Parse JSON body (simplified - in production use JSON parser)
    // For now, we'll create a mock AudioRequest
    const mock_pcm: [1024]u8 = undefined; // Mock PCM data
    const audio_req = AudioRequest{
        .pcm = &mock_pcm,
        .sample_rate = 48000,
        .channels = 2,
    };
    
    // Create audio config
    const config = burble.AudioConfig{
        .sample_rate = switch (audio_req.sample_rate) {
            8000 => burble.SampleRate.rate_8000,
            16000 => burble.SampleRate.rate_16000,
            else => burble.SampleRate.rate_48000,
        },
        .channels = audio_req.channels,
        .buffer_size = audio_req.pcm.len,
    };
    
    // Validate buffer size
    if (!burble.isValidBufferSize(config.buffer_size)) {
        const error_response = "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: 45\r\n\r\n{\"error\":\"Invalid buffer size: must be power of 2\"}";
        try connection.stream.writeAll(error_response);
        return;
    }
    
    // Encode Opus using arena allocation with SIMD optimizations
    // Apply slight gain reduction to prevent clipping
    const encoded = try burble.encodeOpus(arena, audio_req.pcm, config, 0.95);
    
    // Create JSON response using arena allocation
    const response = try std.json.stringifyAlloc(allocator, .{
        .status = "success",
        .data = encoded,
    }, .{ .pretty = false });
    
    const http_response = std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}", .{ response.len, response });
    defer allocator.free(http_response);
    defer allocator.free(response);
    
    try connection.stream.writeAll(http_response);
}

// ============================================================================
// Main entry point
// ============================================================================

pub fn main() !void {
    std.debug.print("Starting Burble Zig API server...\n", .{});
    try serve();
}