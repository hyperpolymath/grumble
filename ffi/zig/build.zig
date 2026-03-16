// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble Coprocessor — Zig 0.15 build configuration.
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
//   cp zig-out/lib/libburble_coprocessor.so ../../server/priv/burble_coprocessor.so

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Erlang NIF header include path.
    const erl_include = b.option(
        []const u8,
        "erl-include",
        "Path to Erlang NIF headers (directory containing erl_nif.h)",
    ) orelse "/var/mnt/eclipse/hyper-data/toolchains/asdf/installs/erlang/28.3.1/erts-16.2/include";

    // Root module for the NIF shared library.
    const nif_mod = b.createModule(.{
        .root_source_file = b.path("src/coprocessor/nif.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    nif_mod.addIncludePath(.{ .cwd_relative = erl_include });

    // Build as shared library (Erlang NIF).
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "burble_coprocessor",
        .root_module = nif_mod,
    });

    b.installArtifact(lib);

    // Unit tests.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/coprocessor_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run coprocessor unit tests");
    test_step.dependOn(&run_tests.step);
}
