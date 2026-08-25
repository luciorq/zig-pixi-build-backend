const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/greet.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "greet",
        .linkage = .dynamic,
        .root_module = mod,
    });
    // Header for downstream C/zig consumers -> $PREFIX/include/greet.h
    lib.installHeader(b.path("include/greet.h"), "greet.h");
    // Shared library -> $PREFIX/lib (dll lands in bin on Windows)
    b.installArtifact(lib);
}
