const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // libgreet comes from the conda host environment (a source dependency
    // built by the same backend) via --search-prefix.
    mod.linkSystemLibrary("greet", .{ .use_pkg_config = .no });

    // Find the conda-provided library relative to the installed binary;
    // see the zlib-zig example for why macOS needs no rpath here (zig's
    // Mach-O linker currently drops -rpath; dylib consumers on macOS are
    // covered by rattler-build relocation on native mac builds only).
    switch (target.result.os.tag) {
        .linux => mod.addRPathSpecial("$ORIGIN/../lib"),
        .macos => mod.addRPathSpecial("@loader_path/../lib"),
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "greet-cli",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
