const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // The C part (#include <zlib.h>) needs libc; the header and libz
        // come from the conda host environment via the backend's
        // --search-prefix.
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path("src/compress.c"), .flags = &.{} });
    // conda-forge names the import library "zlib" on Windows, "z" elsewhere.
    const libname = if (target.result.os.tag == .windows) "zlib" else "z";
    mod.linkSystemLibrary(libname, .{
        .use_pkg_config = .no,
        // zig 0.16's Mach-O linker drops -rpath (no LC_RPATH is emitted;
        // verified with a minimal `zig cc -target aarch64-macos` link), and
        // cross builds skip rattler-build's relocation, so a dynamic libz
        // could not be resolved at runtime on macOS. The conda host env
        // ships libz.a — link it statically there. ELF targets stay
        // dynamic and keep the $ORIGIN rpath below.
        .preferred_link_mode = if (target.result.os.tag == .macos) .static else .dynamic,
    });

    // Make the installed binary find its conda dylibs relative to itself
    // (bin/ -> lib/), so it works even when rattler-build's relocation step
    // is skipped — which the backend does when cross-compiling for macOS
    // from a non-mac machine. On linux this matches what relocation would
    // add anyway; Windows resolves DLLs via PATH instead.
    switch (target.result.os.tag) {
        .macos => mod.addRPathSpecial("@loader_path/../lib"),
        .linux => mod.addRPathSpecial("$ORIGIN/../lib"),
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "zlib-zig",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
