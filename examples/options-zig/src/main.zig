const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const banner = @embedFile("banner");

// glibc 2.30 symbol: linking it is only possible because the backend's
// `glibc-version = "2.31"` raised the target above the 2.28 default, and it
// pins the binary's highest versioned symbol at GLIBC_2.30 for the check.
extern "c" fn gettid() c_int;

pub fn main() void {
    const tid_ok = gettid() > 0;
    // One line, key=value pairs, so the testbed's check script can assert
    // each backend option's effect from the output.
    std.debug.print("options-zig: greeting={s} optimize={s} cpu={s} env={s} target={s}-{s} tid_ok={} banner={s}\n", .{
        build_options.greeting,
        build_options.optimize,
        builtin.cpu.model.name,
        build_options.demo_env,
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
        tid_ok,
        banner,
    });
}
