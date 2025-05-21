const std = @import("std");

pub fn isNotEqual16(a: [16]u8, b: [16]u8) bool {
    // reinterpret the 16-byte arrays as a SIMD vector of 16 u8 lanes
    const va: @Vector(16, u8) = @bitCast(a);
    const vb: @Vector(16, u8) = @bitCast(b);
    // per-lane compare: produces a 16-lane mask
    const mask = va != vb;
    // reduce OR across all lanes
    return @reduce(.Or, mask);
}

pub fn main() void {
    const x = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    const y = [_]u8{ 0, 1, 2, 3, 4, 0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    const b = isNotEqual16(x, y);

    std.debug.print("{}", .{b});
}
