const std = @import("std");
const Tree = @import("tree.zig").node_gen;

pub fn main() !void {
    var debug = std.heap.DebugAllocator(.{}).init;
    const allocator = debug.allocator();

    var root = try Tree(u64).init(allocator, 5);

    var new_root = try root.insert(allocator, 10) orelse @panic("");

    new_root = try new_root.insert(allocator, 15) orelse @panic("");

    // std.debug.print("\nOutput: {any}\n", .{new_root});

    new_root = try new_root.insert(allocator, 14) orelse @panic("");
    new_root = try new_root.insert(allocator, 13) orelse @panic("");
    new_root = try new_root.insert(allocator, 25) orelse @panic("");
    new_root = try new_root.insert(allocator, 30) orelse @panic("");

    std.debug.print("\n\nOutput: {any}\n", .{new_root});
}

test "everything works" {
    const allocator = std.heap.page_allocator; //Replace with the testing allocator after writing the logic to deinit nodes
    const expect = std.testing.expect;

    var root = try Tree(u64).init(allocator, 5);

    var new_root = try root.insert(allocator, 10) orelse @panic("");

    new_root = try new_root.insert(allocator, 15) orelse @panic("");
    new_root = try new_root.insert(allocator, 14) orelse @panic("");

    new_root = try new_root.insert(allocator, 16) orelse @panic("");
    // new_root = try new_root.insert(allocator, 17) orelse @panic("");
    // new_root = try new_root.insert(allocator, 20) orelse @panic("");

    try expect(new_root.value == 15);
    try expect(new_root.colour == .Black);
    try expect(new_root.parent_direction == .Root);
    try expect(new_root.parent == null);
}
