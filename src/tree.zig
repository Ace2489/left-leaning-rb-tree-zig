const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Order = std.math.Order;

const Colour = enum(u1) { Red, Black };
const ParentDirection = enum(u2) {
    Left,
    Right,
    Root, // This is the root node
};

pub fn node_gen(T: type, comptime compare_fn: fn (value: T, self_value: T) Order) type {
    return struct {
        const Node = @This();
        left: ?*Node = null,
        right: ?*Node = null,
        parent: ?*Node,
        ///Note: When ParentDirection == .Root, the parent field is required to be null, any other thing implies a programmer error
        parent_direction: ParentDirection,
        colour: Colour = .Black,
        value: T,

        pub fn init(allocator: Allocator, value: T) !*Node {
            const alloc_node = try allocator.create(Node);
            alloc_node.* = .{ .parent = null, .parent_direction = .Root, .colour = .Black, .value = value };
            return alloc_node;
        }

        pub fn insert(self: *Node, allocator: Allocator, value: u64) !?*Node {
            const compare: Order = compare_fn(value, self.value);

            const branch: *?*Node, const direction: u1 = switch (compare) {
                .eq => return null,
                .lt => .{ &self.left, 0 },
                .gt => .{ &self.right, 1 },
            };

            if (branch.*) |child| {
                return child.*.insert(allocator, value);
            }

            const allocated_child = try allocator.create(Node);
            allocated_child.* = Node{ .value = value, .colour = .Red, .parent = self, .parent_direction = @enumFromInt(direction) };

            branch.* = allocated_child;

            std.debug.print("\nInserted child: {any}\n", .{branch.*.?.value});

            return balance_tree(branch.*.?);
        }

        pub fn search(self: *Node, value: u64) ?*Node {
            if (self.value == value) return self;
            const branch = if (value < self.value) self.left else self.right;
            if (branch) |child| return child.*.search(value);
            return null;
        }

        ///Called statically. DO NOT CALL THIS FROM AN INSTANCE
        //Precondiitions and Rules:
        //You can only rotate left on a node with a red right link
        //Rotating left on the root node makes the child node the new root

        fn rotate_left(node: *Node) void {
            std.debug.print("\nRotating node {} left\n", .{node.value});

            assert(node.right.?.colour == .Red);

            const right_child = node.right orelse @panic("No right child to rotate on\n");

            if (node.parent) |parent| {
                std.debug.print("Parent found. Reassigning\n", .{});
                right_child.parent = parent;
                switch (node.parent_direction) {
                    .Right => {
                        assert(parent.right == node);
                        std.debug.print("Assigning right child to parent's Right node\n", .{});
                        parent.right = right_child;
                    },
                    .Left => {
                        assert(parent.left == node);
                        std.debug.print("Assigning right child to parent's Left node\n", .{});
                        parent.left = right_child;
                    },
                    else => @panic("The root node cannot have a parent\n"),
                }
            } else {
                assert(node.parent_direction == .Root);
                assert(node.parent == null);
            }

            right_child.parent_direction = node.parent_direction; //Setting this outside means that even setting new root nodes will be covered
            right_child.parent = node.parent;

            std.debug.print("Rotating node to right child's left child\n", .{});

            if (right_child.left) |child_left| {
                std.debug.print("\nReassigning the right child of the node\n", .{});
                node.right = child_left;
                child_left.parent = node;
                child_left.parent_direction = .Right;
            } else {
                std.debug.print("\nRight child of the node set to null\n", .{});
                node.right = null;
            }

            right_child.left = node;
            node.parent = right_child;
            node.parent_direction = .Left;
            node.colour = .Red;
            right_child.colour = .Black;

            std.debug.print("Rotated successfully.\n", .{});
        }

        ///Called statically. DO NOT CALL THIS FROM AN INSTANCE
        //Precondiitions and Rules:
        //You can only rotate right on a node with a red left link
        //Rotating right on the root node makes the child node the new root
        fn rotate_right(node: *Node) void {
            std.debug.print("\nRotating node {} right\n", .{node.value});

            assert(node.left.?.colour == .Red);

            const left_child = node.left orelse @panic("No left child to rotate on\n");

            if (node.parent) |parent| {
                switch (node.parent_direction) {
                    .Left => {
                        assert(parent.left == node);
                        parent.left = left_child;
                    },
                    .Right => {
                        assert(parent.right == node);
                        parent.right = left_child;
                    },
                    else => @panic("The root node cannot have a parent"),
                }
            }
            left_child.parent = node.parent;
            left_child.parent_direction = node.parent_direction;

            std.debug.print("Rotating node to left child's right child\n", .{});

            if (left_child.right) |child_right| {
                std.debug.print("\nReassigning the left child of the node\n", .{});
                node.left = child_right;
                child_right.parent = node;
                child_right.parent_direction = .Left;
            } else {
                std.debug.print("Left child of node set to null\n", .{});
                node.left = null;
            }

            left_child.right = node;
            node.parent = left_child;
            node.parent_direction = .Right;
            node.colour = .Red;
            left_child.colour = .Black;

            std.debug.print("Rotated successfully {}\n", .{node});
        }

        ///Called statically. DO NOT CALL THIS FROM AN INSTANCE
        fn balance_tree(node: *Node) *Node {
            std.debug.print("\nBalancing tree from node: {}\n", .{node.value});

            if (node.parent_direction == .Root) {
                std.debug.print("Balanced to root node. Exiting....\n", .{});
                return node;
            }

            const parent = node.parent orelse @panic("No parent node for the child"); //The previous check should stop this from being triggered
            assert(node.parent_direction != .Root);

            if (node.colour == .Black) {
                std.debug.print("Black node found. Balancing on parent\n", .{});
                return balance_tree(parent);
            }

            std.debug.print("Balancing red node\n", .{});

            if (node.parent_direction == .Right) {
                flip_check: {
                    std.debug.print("Checking for a flip\n", .{});
                    assert(parent.right == node); //Something went very wrong to have this node's parent not point to it

                    const left = parent.left orelse {
                        std.debug.print("Flip not possible. Skipping....\n", .{});
                        break :flip_check;
                    };
                    if (left.colour != .Red) break :flip_check;
                    colour_flip(parent);

                    switch (parent.parent_direction) {
                        .Root => {
                            std.debug.print("Root node colour flipped. No more nodes to fix. Making root node black.\n", .{});
                            assert(parent.parent == null);
                            parent.colour = .Black;
                            return parent;
                        },
                        else => return balance_tree(parent),
                    }
                }
                rotate_left(parent);
            } else { //a left red child
                //Because of the earlier assertion, we are assured that the parent of this node is not the root node
                if (parent.colour == .Red) {
                    std.debug.print("Fixing double red links\n", .{});
                    assert(parent.parent != null); //We can't have a red node as the root of the tree

                    const grand_parent = parent.parent orelse @panic("Cannot have double red links without a grandparent\n");

                    rotate_right(grand_parent);
                    //After flipping, the grandparent is now the child of the parent, hence this code -- man, what is this family tree nonsense?
                    assert(grand_parent.parent == parent);
                    colour_flip(parent); //Rotating a double-left always requires a subsequent colour flip

                    if (parent.parent_direction == .Root) {
                        assert(parent.parent == null);
                        std.debug.print("ZRoot node colour flipped. No more nodes to fix. Making root node black.\n", .{});
                        parent.colour = .Black;
                    }
                }
                // A left red link is perfectly fine. Ignore it
            }

            if (node.parent_direction == .Root) {
                assert(node.parent == null);
                std.debug.print("Root node reached before recursive call. Exiting....\n", .{});
                return node;
            }
            std.debug.print("Recursively calling balance for node: {}\n", .{node.value});
            return balance_tree(parent);
        }

        ///Called statically. DO NOT CALL THIS FROM AN INSTANCE
        fn colour_flip(node: *Node) void {
            const left = node.left orelse std.debug.panic("Can't flip without two children {}\n", .{node.value});
            const right = node.right orelse std.debug.panic("Can't flip without two children {}\n", .{node.value});

            std.debug.print("Flipping sub-tree from parent node: {}\n\n", .{node.value});
            assert(left.colour == .Red and right.colour == .Red);

            left.colour = .Black;
            right.colour = .Black;
            node.colour = .Red;
        }
    };
}
