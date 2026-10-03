const std = @import("std");

pub fn build(b: *std.Build) void {
    // The backend passes -Dtarget/-Dcpu/-Doptimize; these register them.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Custom project option, supplied by the backend's `extra-args`.
    const greeting = b.option([]const u8, "greeting", "Word the binary prints") orelse "hello";

    // The backend's `env` reaches the build script; echo it at configure
    // time so the build log proves it was set, and bake it into the binary.
    const demo_env = b.graph.environ_map.get("OPTIONS_ZIG_DEMO") orelse "unset";
    std.debug.print("options-zig configure: OPTIONS_ZIG_DEMO={s} greeting={s}\n", .{ demo_env, greeting });

    const options = b.addOptions();
    options.addOption([]const u8, "greeting", greeting);
    options.addOption([]const u8, "optimize", @tagName(optimize));
    options.addOption([]const u8, "demo_env", demo_env);

    const exe = b.addExecutable(.{
        .name = "options-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Dynamic glibc, so the `glibc-version` suffix is observable
            // through the binary's versioned symbols (readelf -V).
            .link_libc = true,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    // Build input outside src/, covered by `extra-input-globs = ["assets/**"]`.
    exe.root_module.addAnonymousImport("banner", .{ .root_source_file = b.path("assets/banner.txt") });

    b.installArtifact(exe);
}
