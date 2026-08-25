const std = @import("std");
const builtin = @import("builtin");

extern fn greet_message() [*:0]const u8;

pub fn main() void {
    std.debug.print("{s} on {s}-{s}\n", .{
        greet_message(),
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
    });
}
