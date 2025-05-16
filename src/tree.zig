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

//We use indexes instead of pointers to improve cache locality
//Using the max value as a null index for the handles,
const NULL_IDX: u32 = 0xFFFFFFFF;

pub fn Tree(T: type, compare_fn: fn (value: T, self_value: T) Order) type {
    return struct {
        const Node = node_gen(T, compare_fn);
        const Nodes = std.ArrayListUnmanaged(Node);
        const Values = std.ArrayListUnmanaged(T);
        const Self = @This();
        root_idx: u32,
        nodes: *Nodes,
        values: *Values,

        pub fn init_with_capacity(allocator: Allocator, capacity: usize, root: T) !Self {
            const nodes = try allocator.create(Nodes);
            nodes.* = try Nodes.initCapacity(allocator, capacity);
            const values = try allocator.create(Values);
            values.* = try Values.initCapacity(allocator, capacity);

            return Self{ .root_idx = Node.init(nodes, values, root), .nodes = nodes, .values = values };
        }

        pub fn insert(self: *Self, value: T) !*Self {
            self.root_idx = self.nodes.items[@as(usize, self.root_idx)].insert(self.elements, self.values, self.root_idx, value);
            return self.nodes.items[@as(usize, self.root_idx)];
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.nodes.deinit(allocator);
            self.values.deinit(allocator);
            allocator.destroy(self.nodes);
            allocator.destroy(self.values);
        }

        pub fn search(self: *Self, value: T) ?*Node {
            return self.root_idx.search(value);
        }
    };
}

fn node_gen(T: type, comptime compare_fn: fn (value: T, self_value: T) Order) type {
    return struct {
        const Node = @This();
        const NodeList = std.ArrayListUnmanaged(Node);
        const ValueList = std.ArrayListUnmanaged(T);
        left_idx: u32 = NULL_IDX, //handles into an array for increased cache locality, to represent a null handle
        right_idx: u32 = NULL_IDX,
        parent_idx: u32,
        ///Note: When ParentDirection == .Root, the parent field is required to be null, any other thing implies a programmer error
        parent_direction: ParentDirection,
        colour: Colour = .Black,
        value_idx: u32, //index to the array of values

        pub fn init(elements: *NodeList, values: *ValueList, value: T) u32 {
            values.*.appendAssumeCapacity(value);
            const len_values = values.*.items.len;

            assert(len_values < 0xFFFFFFFF); //We don't have enough bits for any indexes beyond this limit
            const val_index: u32 = @truncate(len_values - 1);

            const node = Node{ .parent_idx = NULL_IDX, .parent_direction = .Root, .colour = .Black, .value_idx = val_index };
            elements.*.appendAssumeCapacity(node);

            const len_elements = elements.*.items.len;
            assert(len_elements < 0xFFFFFFFF);
            const elem_index: u32 = @truncate(len_elements - 1);

            return elem_index;
        }

        pub fn insert(self: *Node, elements: *NodeList, values: *ValueList, self_idx: u32, value: T) u32 {
            const compare: Order = compare_fn(value, self.value_idx);

            const branch: u32, const direction: u1 = switch (compare) {
                .eq => return null,
                .lt => .{ self.left_idx, 0 },
                .gt => .{ self.right_idx, 1 },
            };

            //maybe address branch misses later
            if (branch != NULL_IDX) {
                return elements[branch].insert(elements, value);
            }

            values.*.appendAssumeCapacity(value);
            const len_values = values.*.items.len;

            assert(len_values < 0xFFFFFFFF); //We don't have enough bits for any indexes beyond this limit
            const val_index: u32 = @truncate(len_values - 1);

            const child = Node{ .value_idx = val_index, .colour = .Red, .parent_idx = self_idx, .parent_direction = @enumFromInt(direction) };

            elements.*.appendAssumeCapacity(child);

            const len_elements = elements.*.items.len;
            assert(len_elements < 0xFFFFFFFF);
            const elem_index: u32 = @truncate(len_elements - 1);

            return elem_index;
        }

        //     pub fn search(self: *Node, value: T) ?*Node {
        //         const compare = compare_fn(value, self.value_idx);
        //         if (compare == .eq) return self;
        //         const branch = if (compare == .lt) self.left_idx else self.right_idx;
        //         if (branch) |child| return child.*.search(value);
        //         return null;
        //     }

        //     pub fn deinit(self: *Node, allocator: Allocator) void {
        //         if (self.left_idx) |left| left.deinit(allocator);
        //         if (self.right_idx) |right| right.deinit(allocator);
        //         allocator.destroy(self);
        //     }

            // ///Precondiitions and Rules:
            //You can only rotate left on a node with a red right link
            // //Rotating left on the root node makes the child node the new root
            // fn rotate_left(node: *Node) void {
            //     assert(node.right.?.colour == .Red);

            //     const right_child = node.right orelse @panic("No right child to rotate on\n");

            //     if (node.parent) |parent| {
            //         right_child.parent = parent;
            //         switch (node.parent_direction) {
            //             .Right => {
            //                 assert(parent.right == node);
            //                 parent.right = right_child;
            //             },
            //             .Left => {
            //                 assert(parent.left == node);
            //                 parent.left = right_child;
            //             },
            //             else => @panic("The root node cannot have a parent\n"),
            //         }
            //     } else {
            //         assert(node.parent_direction == .Root);
            //         assert(node.parent == null);
            //     }

            //     right_child.parent_direction = node.parent_direction; //Setting this outside means that even setting new root nodes will be covered
            //     right_child.parent = node.parent;

                if (right_child.left) |child_left| {
                    node.right = child_left;
                    child_left.parent = node;
                    child_left.parent_direction = .Right;
                } else {
                    node.right = null;
                }

                right_child.left = node;
                node.parent = right_child;
                node.parent_direction = .Left;
                node.colour = .Red;
                right_child.colour = .Black;
            }

            ///Precondiitions and Rules:
            //You can only rotate right on a node with a red left link
            //Rotating right on the root node makes the child node the new root
            fn rotate_right(node: *Node) void {
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

                if (left_child.right) |child_right| {
                    node.left = child_right;
                    child_right.parent = node;
                    child_right.parent_direction = .Left;
                } else {
                    node.left = null;
                }

                left_child.right = node;
                node.parent = left_child;
                node.parent_direction = .Right;
                node.colour = .Red;
                left_child.colour = .Black;
            }

            fn balance_tree(node: *Node) *Node {
                if (node.parent_direction == .Root) {
                    return node;
                }

                const parent = node.parent orelse @panic("No parent node for the child"); //The previous check should stop this from being triggered
                assert(node.parent_direction != .Root);

                if (node.colour == .Black) {
                    return balance_tree(parent);
                }

                if (node.parent_direction == .Right) {
                    flip_check: {
                        assert(parent.right == node); //Something went very wrong to have this node's parent not point to it

                        const left = parent.left orelse {
                            break :flip_check;
                        };
                        if (left.colour != .Red) break :flip_check;
                        colour_flip(parent);

                        switch (parent.parent_direction) {
                            .Root => {
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
                        assert(parent.parent != null); //We can't have a red node as the root of the tree

                        const grand_parent = parent.parent orelse @panic("Cannot have double red links without a grandparent\n");

                        rotate_right(grand_parent);
                        //After flipping, the grandparent is now the child of the parent, hence this code -- man, what is this family tree nonsense?
                        assert(grand_parent.parent == parent);
                        colour_flip(parent); //Rotating a double-left always requires a subsequent colour flip

                        if (parent.parent_direction == .Root) {
                            assert(parent.parent == null);
                            parent.colour = .Black;
                        }
                    }
                    // A left red link is perfectly fine. Ignore it
                }

                if (node.parent_direction == .Root) {
                    assert(node.parent == null);
                    return node;
                }
                return balance_tree(parent);
            }

            fn colour_flip(node: *Node) void {
                const left = node.left orelse std.debug.panic("Can't flip without two children {}\n", .{node.value});
                const right = node.right orelse std.debug.panic("Can't flip without two children {}\n", .{node.value});

                assert(left.colour == .Red and right.colour == .Red);

                left.colour = .Black;
                right.colour = .Black;
                node.colour = .Red;
            }
    };
}

fn compare_int(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

const testing = std.testing;
const rand = std.Random;
const crypto = std.crypto;
const heap = std.heap;
const mem = std.mem;
const Timer = std.time.Timer;

// Helper compare function for integers
fn compareInt(a: i32, b: i32) Order {
    return std.math.order(a, b);
}

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = gpa.deinit(); // Ensure GPA is deinitialized
    const allocator = gpa.allocator();

    const num_elements_insert = 100_000;
    const num_elements_search = 10_000;

    std.debug.print("Preparing data for RBTree benchmark...\n", .{});

    // --- Prepare data for insertion ---
    var numbers_to_insert = try allocator.alloc(i32, num_elements_insert);
    defer allocator.free(numbers_to_insert);

    // Initialize a random number generator
    // For reproducible benchmarks, you might use a fixed seed.
    // For general use, std.time.nanoTimestamp() provides a varying seed.
    var prng = std.Random.DefaultPrng.init(0x0DFEED); // Fixed seed for reproducibility
    const random = prng.random();

    for (0..num_elements_insert) |i| {
        numbers_to_insert[i] = @intCast(i); // Fill with sequential numbers first
    }
    random.shuffle(i32, numbers_to_insert); // Shuffle them

    std.debug.print("Starting RBTree Insertion Benchmark ({} elements)...\n", .{num_elements_insert});

    // --- Insertion Benchmark ---
    var timer = try Timer.start();
    var rb_tree = try Tree(i32, compareInt).init(allocator, numbers_to_insert[0]);
    defer rb_tree.deinit(allocator);

    for (numbers_to_insert[1..]) |value| {
        // The `insert` function can return `null` if value already exists or `!*Self` on error.
        // We'll assume for benchmark purposes that errors are fatal and duplicates are skipped.
        _ = try rb_tree.insert(allocator, value);
    }

    const insert_time_ns = timer.lap();
    std.debug.print("Insertion of {} elements took: {} ns\n", .{
        num_elements_insert,
        insert_time_ns,
    });
    std.debug.print("Average time per insertion: {} ns\n", .{
        @as(f64, @floatFromInt(insert_time_ns)) / @as(f64, @floatFromInt(num_elements_insert)),
    });

    // --- Prepare data for search ---
    // We'll search for some elements that are in the tree and some that are not.
    var numbers_to_search = try allocator.alloc(i32, num_elements_search);
    defer allocator.free(numbers_to_search);

    for (0..num_elements_search) |i| {
        if (i % 2 == 0) { // Half of the searches for existing elements
            numbers_to_search[i] = numbers_to_insert[random.uintLessThan(u32, @intCast(num_elements_insert))];
        } else { // Half for non-existing elements (likely outside the range)
            numbers_to_search[i] = @intCast(num_elements_insert + random.uintLessThan(u32, 1000));
        }
    }
    random.shuffle(i32, numbers_to_search); // Shuffle search queries

    std.debug.print("Starting RBTree Search Benchmark ({} queries)...\n", .{num_elements_search});
    timer.reset(); // Reset the timer for the new measurement

    var found_count: usize = 0;

    for (numbers_to_search) |value_to_search| {
        if (rb_tree.search(value_to_search) != null) {
            found_count += 1;
        }
    }

    const search_time_ns = timer.lap();
    std.debug.print("Search for {} elements (found {}) took: {} ns\n", .{
        num_elements_search,
        found_count,
        search_time_ns,
    });
    std.debug.print("Average time per search: {} ns\n", .{
        @as(f64, @floatFromInt(search_time_ns)) / @as(f64, @floatFromInt(num_elements_search)),
    });

    // --- Cleanup ---
    std.debug.print("Deinitializing tree...\n", .{});
    // rb_tree.deinit(allocator);
    std.debug.print("Benchmark complete.\n", .{});
}
