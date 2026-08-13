const std = @import("std");

pub fn build(b: *std.Build) void {
    // The backend passes -Dtarget/-Dcpu/-Doptimize; these two calls are what
    // register those options (the ecosystem convention the backend assumes).
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hello-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Marks the executable for installation into the --prefix.
    b.installArtifact(exe);
}
