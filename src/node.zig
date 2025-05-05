const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Node(comptime T: type) type {
    return struct {
        const Self = @This();
        left: ?*Self = null,
        right: ?*Self = null,

        value: T,

        pub fn init(value: T) Self {
            return Self{ .value = value };
        }

        pub fn insert(self: *Self, value: T, allocator: Allocator) !bool {
            if (value == self.value) return false;
            if (value < self.value) {
                if (self.left == null) {
                    const allocated_node = try allocator.create(Self);
                    allocated_node.* = .{ .value = value };
                    self.left = allocated_node;
                    return true;
                }
                return try self.left.?.insert(value, allocator);
            } else {
                if (self.right == null) {
                    const allocated_node = try allocator.create(Self);
                    allocated_node.* = .{ .value = value };
                    self.right = allocated_node;
                    return true;
                }
                return try self.right.?.insert(value, allocator);
            }
        }

        pub fn search(self: *Self, value: T) ?*Self {
            if (value == self.value) return self;

            const branch = if (value < self.value) self.left else self.right;
            return if (branch) |child| child.search(value) else null;
        }
    };
}
