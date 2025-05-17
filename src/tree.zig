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

        pub fn insert(self: *Self, value: T) void {
            const idx = self.nodes.items[self.root_idx].insert(self.nodes, self.values, self.root_idx, value);
            if (idx == NULL_IDX) return;
            self.root_idx = idx;
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

        pub fn insert(self: *Node, nodes: *NodeList, values: *ValueList, self_idx: u32, value: T) u32 {
            const compare: Order = compare_fn(value, values.items[self.value_idx]);

            const branch_idx: *u32, const direction: u1 = switch (compare) {
                .eq => return NULL_IDX,
                .lt => .{ &self.left_idx, 0 },
                .gt => .{ &self.right_idx, 1 },
            };

            //maybe address branch misses later
            if (branch_idx.* != NULL_IDX) {
                return nodes.*.items[branch_idx.*].insert(nodes, values, branch_idx.*, value);
            }

            values.*.appendAssumeCapacity(value);
            const len_values = values.*.items.len;

            assert(len_values < 0xFFFFFFFF); //We don't have enough bits for any indexes beyond this limit
            const val_index: u32 = @truncate(len_values - 1);

            const child = Node{ .value_idx = val_index, .colour = .Red, .parent_idx = self_idx, .parent_direction = @enumFromInt(direction) };

            nodes.*.appendAssumeCapacity(child);

            const len_elements = nodes.*.items.len;
            assert(len_elements < 0xFFFFFFFF);
            const child_index: u32 = @truncate(len_elements - 1);

            branch_idx.* = child_index;

            return balance_tree(nodes, child_index);
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
        fn rotate_left(nodes: *NodeList, node_idx: u32) void {
            const node = &nodes.items[node_idx];

            assert(node.right_idx != NULL_IDX);

            const right_child_idx = node.right_idx;
            const right_child = &nodes.items[right_child_idx];
            assert(right_child.*.colour == .Red);

            if (node.*.parent_idx != NULL_IDX) {
                const parent = &nodes.items[node.*.parent_idx];
                switch (node.*.parent_direction) {
                    .Right => {
                        assert(parent.*.right_idx == node_idx);
                        parent.*.right_idx = right_child_idx;
                    },
                    .Left => {
                        assert(parent.*.left_idx == node_idx);
                        parent.*.left_idx = right_child_idx;
                    },
                    else => @panic("The root node cannot have a parent\n"),
                }
            } else {
                assert(node.parent_direction == .Root);
                assert(node.parent_idx == NULL_IDX); //make sure we have the root node
            }

            right_child.*.parent_direction = node.*.parent_direction; //Setting this outside means that even setting new root nodes will be covered
            right_child.*.parent_idx = node.parent_idx;

            if (right_child.*.left_idx != NULL_IDX) {
                @branchHint(.unlikely); //I cannot think of a scenario where this could happen, but let this be here for correctness
                const child_left = &nodes.items[right_child.*.left_idx];
                node.*.right_idx = right_child.*.left_idx;
                child_left.*.parent_idx = node_idx;
                child_left.*.parent_direction = .Right;
            } else {
                node.right_idx = NULL_IDX;
            }

            right_child.*.left_idx = node_idx;
            node.*.parent_idx = right_child_idx;
            node.*.parent_direction = .Left;
            const node_colour = node.*.colour;
            node.*.colour = right_child.*.colour;
            right_child.*.colour = node_colour;
        }

        ///Preconditions and Rules:
        /// You can only rotate right on a node with a red left link
        /// Rotating right on the root node makes the child node the new root

        // Rotate right at node [30] to fix Red-Red left link: [30] -> [20] -> [10]
        //
        // BEFORE: Double Red Violation at [30]
        //
        //             [30] (B)
        //            /        \
        //           /          \      <- Links from [30]
        //          /            \
        //       [20] (R)        [40] (B)
        //      /        \
        //    /          \      <- Links from [20]
        //    /            \
        // [10] (R)        [25] (B)
        //
        // AFTER: Structure & Color Adjusted
        //
        //              [20] (B)   <- [20] moved up, became Black
        //             /        \
        //           /           \     <- Link [20] -> [10] stayed Red.
        //           /            \     <- Link [20] -> [30] became Red!
        //        [10] (R)        [30] (R)
        //                       /         \
        //                      /           \     <- Links from [30]
        //                     /             \
        //                   [25] (B)      [40] (B) <- [25] moved. [40] stayed.

        fn rotate_right(nodes: *NodeList, node_idx: u32) void {
            const node = access(node_idx, nodes);

            assert(node.left_idx != NULL_IDX);
            const left_child = access(node.left_idx, nodes);

            assert(left_child.colour == .Red);

            if (node.parent_idx != NULL_IDX) {
                const parent = access(node.parent_idx, nodes);
                switch (node.parent_direction) {
                    .Left => {
                        assert(parent.left_idx == node_idx);
                        parent.left_idx = node.left_idx;
                    },
                    .Right => {
                        assert(parent.right_idx == node_idx);
                        parent.right_idx = node.left_idx;
                    },
                    else => @panic("The root node cannot have a parent"),
                }
            }
            left_child.parent_idx = node.parent_idx;
            left_child.parent_direction = node.parent_direction;

            node.parent_idx = node.left_idx;
            if (left_child.right_idx != NULL_IDX) {
                const right_child = access(left_child.right_idx, nodes);
                node.left_idx = left_child.right_idx;
                right_child.parent_idx = node_idx;
                right_child.parent_direction = .Left;
            } else {
                node.left_idx = NULL_IDX;
            }

            left_child.right_idx = node_idx;
            node.parent_direction = .Right;
            const node_colour = node.colour;
            node.colour = left_child.colour;
            left_child.colour = node_colour;
        }

        fn balance_tree(nodes: *NodeList, node_idx: u32) u32 {
            assert(node_idx != NULL_IDX);
            const node = access(node_idx, nodes);

            if (node.parent_direction == .Root) {
                return node_idx;
            }

            if (node.parent_idx == NULL_IDX) @panic("Cannot balance the root node"); //The previous check should stop this from being triggered

            const parent = access(node.parent_idx, nodes);
            const parent_idx = node.parent_idx;

            if (node.colour == .Black) { //A black node indicates that this node has been fully balanced
                return balance_tree(nodes, node.parent_idx);
            }

            if (node.parent_direction == .Right) {
                flip_check: {
                    assert(parent.right_idx == node_idx); //Something went very wrong to have this node's parent not point to it
                    if (parent.left_idx == NULL_IDX) break :flip_check;

                    const left = access(parent.left_idx, nodes);

                    if (left.colour != .Red) break :flip_check;
                    colour_flip(parent, nodes, parent_idx);

                    switch (parent.parent_direction) {
                        .Root => {
                            assert(parent.parent_idx == NULL_IDX);
                            parent.colour = .Black;
                            return parent_idx;
                        },
                        else => return balance_tree(nodes, parent_idx),
                    }
                }
                rotate_left(nodes, parent_idx);
                return balance_tree(nodes, node.left_idx);
            } else { //a left red child
                //Because of the earlier assertion, we are assured that the parent of this node is not the root node
                if (parent.colour == .Red) { //Double red left-links, we need to rotate

                    //This state should be impossible to reach, hence the assertion
                    if (parent.parent_idx == NULL_IDX) @panic("Cannot have double red links without a grandparent\n");
                    const grand_parent_idx = parent.parent_idx;

                    rotate_right(nodes, grand_parent_idx);
                    //After flipping, the grandparent is now the child of the parent, hence this code -- man, what is this family tree nonsense?
                    colour_flip(parent, nodes, node.parent_idx); //Rotating a double-left always requires a subsequent colour flip

                    if (parent.parent_direction == .Root) {
                        assert(parent.parent_idx == NULL_IDX);
                        parent.colour = .Black;
                    }
                }
                return balance_tree(nodes, parent_idx);
                // A left red link is perfectly fine otherwise. Ignore it
            }

            return balance_tree(nodes, node_idx);
        }

        fn colour_flip(node: *Node, nodes: *NodeList, node_idx: u32) void {
            if (node.left_idx == NULL_IDX or node.right_idx == NULL_IDX) {
                std.debug.panic("Can't flip without two children.\nNodes:{}\t{}", .{ node.left_idx, node.right_idx });
            }
            assert(access(node_idx, nodes) == node);

            const left = access(node.left_idx, nodes);
            const right = access(node.right_idx, nodes);
            assert(left.colour == .Red and right.colour == .Red);

            left.colour = .Black;
            right.colour = .Black;
            node.colour = .Red;
        }

        //helper function because I can't keep typing the @as syntax over and over
        fn access(index: u32, nodes: *NodeList) *Node {
            return &nodes.items[index];
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
