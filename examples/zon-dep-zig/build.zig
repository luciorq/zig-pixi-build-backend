const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const greeter = b.dependency("greeter", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("greeter", greeter.module("greeter"));

    const exe = b.addExecutable(.{
        .name = "zon-dep-zig",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
