const std = @import("std");
const builtin = @import("builtin");

extern fn zlib_version_string() [*:0]const u8;
extern fn compress_size(input: [*:0]const u8) c_long;

pub fn main() void {
    const message = "the quick brown fox jumps over the lazy dog, " ** 8;
    const compressed = compress_size(message);
    std.debug.print("zlib {s} on {s}-{s}: {d} bytes -> {d} bytes\n", .{
        zlib_version_string(),
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
        message.len,
        compressed,
    });
}
