// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble Coprocessor — Zig build configuration.
//
// Compiles SIMD-accelerated audio processing kernels as Erlang NIFs.
// The output shared library is loaded by Burble.Coprocessor.ZigBackend.
//
// Build:
//   zig build -Doptimize=ReleaseFast
//
// Output:
//   zig-out/lib/libburble_coprocessor.so  (Linux)
//   zig-out/lib/libburble_coprocessor.dylib (macOS)
//
// Install to priv/:
//   cp zig-out/lib/libburble_coprocessor.* ../server/priv/burble_coprocessor.*

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main shared library (Erlang NIF).
    const lib = b.addSharedLibrary(.{
        .name = "burble_coprocessor",
        .root_source_file = b.path("src/coprocessor/nif.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with Erlang NIF headers.
    // ERL_INTERFACE_DIR is set by mix at compile time.
    if (std.process.getEnvVarOwned(b.allocator, "ERL_EI_INCLUDE_DIR")) |dir| {
        lib.addIncludePath(.{ .cwd_relative = dir });
        b.allocator.free(dir);
    } else |_| {
        // Fallback: try common Erlang NIF header locations.
        lib.addIncludePath(.{ .cwd_relative = "/usr/lib/erlang/usr/include" });
        lib.addIncludePath(.{ .cwd_relative = "/usr/local/lib/erlang/usr/include" });
    }

    lib.linkLibC();
    b.installArtifact(lib);

    // Unit tests.
    const tests = b.addTest(.{
        .root_source_file = b.path("test/coprocessor_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run coprocessor unit tests");
    test_step.dependOn(&run_tests.step);
}
