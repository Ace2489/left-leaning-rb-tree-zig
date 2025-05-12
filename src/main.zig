const std = @import("std");
const Tree = @import("tree.zig").Tree;

pub fn main() !void {
    var debug = std.heap.DebugAllocator(.{}).init;
    const allocator = debug.allocator();
    defer _ = debug.deinit();

    var root = try Tree(u64, compare_fn).init(allocator, 14);
    defer root.deinit(allocator);

    var tree_root = try root.insert(allocator, 25) orelse @panic("");
    tree_root = try tree_root.insert(allocator, 10) orelse @panic("");
    std.debug.print("\n\nOutput: {any}\n", .{tree_root});
}

fn compare_fn(a: u64, b: u64) std.math.Order {
    if (a == b) return .eq;
    if (a < b) return .lt;
    return .gt;
}
test "everything works" {
    const allocator = std.heap.page_allocator; //Replace with the testing allocator after writing the logic to deinit nodes
    const expect = std.testing.expect;

    var root = try Tree(u64).init(allocator, 5);

    var new_root = try root.insert(allocator, 10) orelse @panic("");

    new_root = try new_root.insert(allocator, 15) orelse @panic("");
    new_root = try new_root.insert(allocator, 14) orelse @panic("");

    new_root = try new_root.insert(allocator, 16) orelse @panic("");

    try expect(new_root.value == 15);
    try expect(new_root.colour == .Black);
    try expect(new_root.parent_direction == .Root);
    try expect(new_root.parent == null);
}
