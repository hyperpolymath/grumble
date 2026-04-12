// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble Coprocessor — Zig 0.15 build configuration.
//
// Compiles SIMD-accelerated audio processing kernels as Erlang NIFs.
// The output shared library is loaded by Burble.Coprocessor.ZigBackend.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Erlang NIF header include path.
    const erl_include = b.option(
        []const u8,
        "erl-include",
        "Path to Erlang NIF headers (directory containing erl_nif.h)",
    ) orelse "/usr/lib/erlang/usr/include";

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

    // Named modules for coprocessor kernels — required by Zig 0.15 because
    // test/coprocessor_test.zig cannot @import("../src/…") outside its root.
    const audio_mod = b.createModule(.{
        .root_source_file = b.path("src/coprocessor/audio.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dsp_mod = b.createModule(.{
        .root_source_file = b.path("src/coprocessor/dsp.zig"),
        .target = target,
        .optimize = optimize,
    });
    const neural_mod = b.createModule(.{
        .root_source_file = b.path("src/coprocessor/neural.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "dsp", .module = dsp_mod },
        },
    });

    // Unit tests.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/coprocessor_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audio", .module = audio_mod },
            .{ .name = "dsp", .module = dsp_mod },
            .{ .name = "neural", .module = neural_mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run coprocessor unit tests");
    test_step.dependOn(&run_tests.step);
}
