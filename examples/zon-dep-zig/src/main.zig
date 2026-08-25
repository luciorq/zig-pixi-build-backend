const std = @import("std");
const builtin = @import("builtin");
const greeter = @import("greeter");

pub fn main() void {
    std.debug.print("{s} on {s}-{s}\n", .{
        greeter.greeting(),
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
    });
}
