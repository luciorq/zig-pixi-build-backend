const std = @import("std");
const builtin = @import("builtin");

pub fn main() void {
    // std.debug.print is stable across zig versions, unlike the stdout
    // writer API, which changed in 0.15/0.16.
    std.debug.print("hello from zig {s}, built for {s}-{s} ({s} mode)\n", .{
        builtin.zig_version_string,
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
        @tagName(builtin.mode),
    });
}
