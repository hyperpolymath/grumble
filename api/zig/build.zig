// SPDX-License-Identifier: PMPL-1.0-or-later
// Build script for Burble Zig API
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Create executable
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "burble-zig-api",
        .root_source_file = .{ .path = "server.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Add burble.zig as a module
    exe.addModule("burble", .{
        .source_file = .{ .path = "burble.zig" },
    });
    
    // Link with C libraries (for FFI)
    exe.linkLibC();
    
    // Install the executable
    b.installArtifact(exe);
    
    // Create a run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    // For running tests
    const test_step = b.addTest(.{
        .root_source_file = .{ .path = "tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_step.step.dependOn(b.getInstallStep());
    
    // Add build options
    const opts = b.addOptions();
    const enable_logging = opts.boolOption("logging", "Enable debug logging");
    
    // Conditional compilation based on options
    if (enable_logging) |enabled| {
        if (enabled) {
            exe.addDefine("ENABLE_LOGGING", "1");
        }
    }
}