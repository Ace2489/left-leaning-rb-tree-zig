const std = @import("std");
const Node = @import("node.zig").Node;

pub fn main() !void {
    var debug = std.heap.DebugAllocator(.{}).init;
    const allocator = debug.allocator();
    // defer _ = debug.deinit();

    var big_node = Node(u64).init(10);

    const result = try big_node.insert(5, allocator);
    const result1 = try big_node.insert(50, allocator);
    std.debug.print("Node:{}\nResult: {}\nResult_Bigger: {}\n", .{ big_node, result, result1 });

    const search = big_node.search(10);
    const not_found = big_node.search(15);

    std.debug.print("Search: {any}\nNOt FOund: {any}", .{ search, not_found });
}
