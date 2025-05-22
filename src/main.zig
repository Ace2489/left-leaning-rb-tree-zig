const std = @import("std");
const Tree = @import("tree.zig").Tree;

pub fn main() !void {
    var debug = std.heap.DebugAllocator(.{}).init;
    const allocator = debug.allocator();
    defer _ = debug.deinit();

    const capacity: usize = 100;

    var tree = try Tree([]const u8, u64, compare_fn).init_with_capacity(allocator, capacity);
    defer tree.deinit(allocator);

    const res = tree.getOrPutAssumeCapacity(.{ .key = "koon", .value = 24 });
    res.update_value();
    const result = tree.getOrPutAssumeCapacity(.{ .key = "rooney", .value = 2500 });
    std.debug.print("getOrPutResult: {}\n", .{result});
    std.debug.print("getOrPutResult branch pointer: {}\n\n", .{result.parent_branch_pointer.*});

    result.update_value();
    // tree.insert(3);
    // tree.insert(2);
    // tree.insert(7);
    // tree.insert(11);
    // tree.insert(23);
    // tree.insert(27);
    // tree.insert(6);

    std.debug.print("Tree: {}\n\n", .{tree});
    std.debug.print("KV list keys:{s}\n", .{tree.kv_list.items(.key)});
    std.debug.print("KV list values:{any}\n", .{tree.kv_list.items(.value)});
}

fn compare_fn(a: []const u8, b: []const u8) std.math.Order {
    _ = a;
    _ = b;
    // if (a == b) return .eq;
    // if (a < b) return .lt;
    // return .gt;

    return .gt;
}

// test "verify tree structure after insertions" {
//     // Use proper leak checking for DebugAllocator
//     var debug = std.heap.DebugAllocator(.{}).init;
//     const allocator = debug.allocator();
//     defer _ = debug.deinit();

//     // Initialize tree with proper error handling
//     var tree = try Tree(u64, compare_fn).init(allocator, 5);
//     const Node = @TypeOf(tree.root.*);
//     defer tree.deinit(allocator);

//     // Simplified insertions - assumes insert returns void or error
//     _ = try tree.insert(allocator, 10);
//     _ = try tree.insert(allocator, 12);
//     _ = try tree.insert(allocator, 15);
//     _ = try tree.insert(allocator, 11);
//     _ = try tree.insert(allocator, 3);

//     //Expected structure
//     //                              12 (Black) [Root]
//     //                              /                \
//     //                             /                  \
//     //                   10 (Red)                      15 (Black)
//     //                  /        \                    /          \
//     //                 /          \                  /            \
//     //       5 (Black)          11 (Black)        null          null
//     //      /      \            /      \
//     //     /        \          /        \
//     //    3 (Red)    null    null        null

//     //And now, we verify

//     const root = tree.root;

//     // Verify Root Node (12 Black)
//     try std.testing.expectEqual(@as(u64, 12), root.value);
//     try std.testing.expectEqual(.Black, root.colour);
//     try std.testing.expectEqual(@as(?*Node, null), root.parent);
//     try std.testing.expectEqual(.Root, root.parent_direction);

//     // Verify Root's Left Child (10 Red)
//     const node10 = root.left orelse @panic("Node 10 missing");
//     try std.testing.expectEqual(@as(u64, 10), node10.value);
//     try std.testing.expectEqual(.Red, node10.colour);
//     try std.testing.expectEqual(root, node10.parent);
//     try std.testing.expectEqual(.Left, node10.parent_direction);

//     // Verify Root's Right Child (15 Black)
//     const node15 = root.right orelse @panic("Node 15 missing");
//     try std.testing.expectEqual(@as(u64, 15), node15.value);
//     try std.testing.expectEqual(.Black, node15.colour);
//     try std.testing.expectEqual(root, node15.parent);
//     try std.testing.expectEqual(.Right, node15.parent_direction);
//     try std.testing.expectEqual(@as(?*Node, null), node15.left);
//     try std.testing.expectEqual(@as(?*Node, null), node15.right);

//     // Verify Node 10's Children
//     const node5 = node10.left orelse @panic("Node 5 missing");
//     try std.testing.expectEqual(@as(u64, 5), node5.value);
//     try std.testing.expectEqual(.Black, node5.colour);
//     try std.testing.expectEqual(node10, node5.parent);
//     try std.testing.expectEqual(.Left, node5.parent_direction);
//     try std.testing.expectEqual(@as(?*Node, null), node5.right);

//     const node11 = node10.right orelse @panic("Node 11 missing");
//     try std.testing.expectEqual(@as(u64, 11), node11.value);
//     try std.testing.expectEqual(.Black, node11.colour);
//     try std.testing.expectEqual(node10, node11.parent);
//     try std.testing.expectEqual(.Right, node11.parent_direction);
//     try std.testing.expectEqual(@as(?*Node, null), node11.left);
//     try std.testing.expectEqual(@as(?*Node, null), node11.right);

//     // Verify Node 5's Left Child (3 Red)
//     const node3 = node5.left orelse @panic("Node 3 missing");
//     try std.testing.expectEqual(@as(u64, 3), node3.value);
//     try std.testing.expectEqual(.Red, node3.colour);
//     try std.testing.expectEqual(node5, node3.parent);
//     try std.testing.expectEqual(.Left, node3.parent_direction);
//     try std.testing.expectEqual(@as(?*Node, null), node3.left);
//     try std.testing.expectEqual(@as(?*Node, null), node3.right);
// }
