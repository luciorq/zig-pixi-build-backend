const std = @import("std");
const builtin = @import("builtin");

extern fn zlib_version_string() [*:0]const u8;
extern fn compress_size(input: [*:0]const u8) c_long;

// Repeat a string literal at comptime. Array multiplication (`"..." ** 8`)
// was removed in zig 0.17 and `@splat` only repeats a scalar, so build the
// repeated, zero-terminated array by hand; this compiles on 0.16 and 0.17.
fn repeat(comptime part: []const u8, comptime times: usize) [part.len * times:0]u8 {
    var buf: [part.len * times:0]u8 = undefined;
    for (0..times) |i| @memcpy(buf[i * part.len ..][0..part.len], part);
    buf[part.len * times] = 0;
    return buf;
}

const message_array = repeat("the quick brown fox jumps over the lazy dog, ", 8);

pub fn main() void {
    const message: *const [message_array.len:0]u8 = &message_array;
    const compressed = compress_size(message);
    std.debug.print("zlib {s} on {s}-{s}: {d} bytes -> {d} bytes\n", .{
        zlib_version_string(),
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
        message.len,
        compressed,
    });
}
