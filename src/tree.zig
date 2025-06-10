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
pub const NULL_IDX: u32 = 0xFFFFFFFF;

pub fn Tree(comptime K: type, comptime V: type, compare_fn: fn (key: K, self_key: K) Order) type {
    return struct {
        pub const KV = struct { key: K, value: V };
        pub const Node = node_gen(K, compare_fn);
        pub const Nodes = std.ArrayListUnmanaged(Node);
        pub const KVList = std.MultiArrayList(KV); //Multiarraylist allows us to work with one without loading the other
        const Self = @This();
        root_idx: u32,
        nodes: Nodes,
        kv_list: KVList,

        pub const empty: Self = .{
            .root_idx = NULL_IDX,
            .nodes = .empty,
            .kv_list = .empty,
        };

        pub const GetOrPutResult = struct {
            key: K,
            ///Null_idx if the key is not already present in the tree
            ///Any other u32 otherwise
            kv_index: u32,

            ///The value which would be inserted into the tree if the update_value function were called
            pending_value: V,

            parent_idx: u32,
            parent_branch_pointer: *u32,
            parent_direction: u2,
            kv_list: *KVList,
            nodes: *Nodes,
            tree: *Self,

            ///Update the value, or create a new node if it doesn't exist
            pub fn update_value(self: @This()) void {
                const kv = KV{ .key = self.key, .value = self.pending_value };
                if (self.kv_index != NULL_IDX) { //Just modify the value for that key
                    assert(self.parent_direction == 3);
                    assert(self.parent_branch_pointer.* == NULL_IDX);
                    assert(self.parent_idx == NULL_IDX);
                    self.kv_list.*.set(self.kv_index, kv);
                    return;
                }

                if (self.tree.root_idx == NULL_IDX) { //No root node yet, let's set this to the root
                    assert(self.parent_idx == NULL_IDX);
                    assert(self.parent_direction == 2);
                    assert(self.parent_branch_pointer.* == NULL_IDX);

                    self.kv_list.*.appendAssumeCapacity(kv);
                    const len_kv = self.kv_list.*.len;

                    assert(len_kv < 0xFFFFFFFF); //We don't have enough bits for any indexes beyond this limit
                    const val_index: u32 = @truncate(len_kv - 1);

                    const node = Node{
                        .parent_idx = self.parent_idx,
                        .parent_direction = @enumFromInt(self.parent_direction),
                        .colour = .Black,
                        .key_idx = val_index,
                    };

                    self.nodes.*.appendAssumeCapacity(node);

                    const len_elements = self.nodes.*.items.len;
                    assert(len_elements < 0xFFFFFFFF);
                    const root_index: u32 = @truncate(len_elements - 1);
                    self.tree.root_idx = root_index;
                    return;
                }

                //A new insertion
                assert(self.parent_idx != NULL_IDX);
                assert(self.parent_direction < 2);
                assert(self.parent_branch_pointer.* == NULL_IDX);

                self.kv_list.*.appendAssumeCapacity(kv);
                const len_kv = self.kv_list.*.len;

                assert(len_kv < 0xFFFFFFFF); //We don't have enough bits for any indexes beyond this limit
                const val_index: u32 = @truncate(len_kv - 1);

                const child = Node{ .key_idx = val_index, .colour = .Red, .parent_idx = self.parent_idx, .parent_direction = @enumFromInt(self.parent_direction) };

                self.nodes.*.appendAssumeCapacity(child);

                const len_elements = self.nodes.*.items.len;
                assert(len_elements < 0xFFFFFFFF);
                const child_index: u32 = @truncate(len_elements - 1);

                self.parent_branch_pointer.* = child_index;

                const new_root_idx = Node.balance_tree(self.nodes, child_index);
                self.tree.root_idx = new_root_idx;
            }
        };

        pub fn init_with_capacity(allocator: Allocator, capacity: usize) !Self {
            const nodes = try Nodes.initCapacity(allocator, capacity);
            var kv_list = KVList.empty;
            try kv_list.setCapacity(allocator, capacity);

            return Self{ .root_idx = NULL_IDX, .nodes = nodes, .kv_list = kv_list };
        }

        pub fn getOrPutAssumeCapacity(self: *Self, kv: KV) GetOrPutResult {
            assert(self.nodes.items.len < self.nodes.capacity);
            assert(self.kv_list.len < self.kv_list.capacity);
            const keys = self.kv_list.items(.key);
            if (self.root_idx == NULL_IDX) { //No root node yet, let's set this to the root
                return .{
                    .key = kv.key,
                    .kv_index = NULL_IDX,
                    .pending_value = kv.value,
                    .parent_idx = NULL_IDX,
                    .parent_branch_pointer = @constCast(&NULL_IDX),
                    .parent_direction = 2,
                    .kv_list = &self.kv_list,
                    .nodes = &self.nodes,
                    .tree = self,
                };
            }
            var root = &self.nodes.items[self.root_idx];
            const res = root.getParentForPut(&self.nodes, keys, self.root_idx, kv.key);

            if (res.found_existing) {
                assert(res.parent_idx == NULL_IDX);
                assert(res.parent_branch_pointer.* == NULL_IDX);
                assert(res.parent_direction == 3); //invalid direction
                const result: GetOrPutResult = .{
                    .kv_index = res.key_idx,
                    .pending_value = kv.value,
                    .parent_idx = res.parent_idx,
                    .parent_branch_pointer = res.parent_branch_pointer,
                    .parent_direction = res.parent_direction,
                    .kv_list = &self.kv_list,
                    .nodes = &self.nodes,
                    .key = kv.key,
                    .tree = self,
                };
                return result;
            }
            assert(res.parent_idx != NULL_IDX);
            assert(res.parent_branch_pointer.* == NULL_IDX);
            assert(res.parent_direction < 2);
            assert(res.key_idx == NULL_IDX);

            return .{
                .kv_index = res.key_idx,
                .pending_value = kv.value,
                .parent_idx = res.parent_idx,
                .parent_branch_pointer = res.parent_branch_pointer,
                .parent_direction = res.parent_direction,
                .kv_list = &self.kv_list,
                .nodes = &self.nodes,
                .key = kv.key,
                .tree = self,
            };
        }

        pub fn getOrPut(self: *Self, allocator: Allocator, kv: KV) !GetOrPutResult {
            if (self.nodes.capacity <= self.nodes.items.len + 1) {
                const cap = std.math.ceilPowerOfTwo(usize, @max(1, self.nodes.capacity)) catch unreachable;
                try self.nodes.ensureUnusedCapacity(allocator, cap);
            }

            if (self.kv_list.capacity <= self.kv_list.len + 1) {
                const cap = std.math.ceilPowerOfTwo(usize, @max(1, self.nodes.capacity)) catch unreachable;
                try self.kv_list.ensureUnusedCapacity(allocator, cap);
            }
            return getOrPutAssumeCapacity(self, kv);
        }

        pub fn update(self: *Self, modifications: anytype) ?V {
            if (!@hasField(@TypeOf(modifications), "key")) return; //No key in the details, we can't find an entry to modify
            const val_idx = self.getValueIdx(modifications.key);
            if (val_idx == NULL_IDX) return null;
            //No value found for the key

            var value_for_modification = self.kv_list.get(val_idx);

            const info = @typeInfo(@TypeOf(modifications.value));

            if (!(info == .@"struct")) {
                value_for_modification.value = modifications.value;
            } else {
                inline for (info.@"struct".fields) |field| {
                    if (!@hasField(V, field.name)) {
                        return null;
                    }
                    @field(value_for_modification.value, field.name) = @field(modifications.value, field.name);
                }
            }

            self.kv_list.set(val_idx, .{ .key = modifications.key, .value = value_for_modification.value });
            return value_for_modification.value;
        }

        pub fn delete(self: *Self, key: K) ?KV {
            if (self.root_idx == NULL_IDX) return null; //No tree lol
            var root = &self.nodes.items[self.root_idx];

            if (self.search(key) == null) return null;
            const result = root.delete(&self.nodes, self.kv_list.items(.key), self.root_idx, key);

            if (result.removed_idx == NULL_IDX) return null; //Element not found;

            // If root_idx is NULL_IDX here, it means the tree is now empty.
            // The previously non-null root was the only node and has been removed.
            self.root_idx = result.root_idx;

            const removed_node = self.nodes.swapRemove(result.removed_idx);

            const removed_kv = self.kv_list.get(removed_node.key_idx);
            self.kv_list.swapRemove(removed_node.key_idx);

            if (result.removed_idx == self.nodes.items.len) return removed_kv;

            var swapped_node = &self.nodes.items[result.removed_idx];
            swapped_node.key_idx = result.removed_idx;

            var swapped_kv = self.kv_list.slice().get(result.removed_idx);
            swapped_kv.key = result.removed_idx;

            //Re-linking parent and child nodes

            if (swapped_node.left_idx != NULL_IDX) {
                var left = &self.nodes.items[swapped_node.left_idx];
                left.parent_idx = result.removed_idx;
            }
            if (swapped_node.right_idx != NULL_IDX) {
                var right = &self.nodes.items[swapped_node.right_idx];
                right.parent_idx = result.removed_idx;
            }

            if (swapped_node.parent_idx != NULL_IDX) {
                var parent = &self.nodes.items[swapped_node.parent_idx];
                switch (swapped_node.parent_direction) {
                    .Left => parent.left_idx = result.removed_idx,
                    .Right => parent.right_idx = result.removed_idx,
                    .Root => @panic("The root cannot have a non-null parent idx"),
                }
            }

            return removed_kv;
        }

        pub fn inorder(self: *Self, allocator: Allocator) !std.ArrayListUnmanaged(K) {
            var out_list = std.ArrayListUnmanaged(K).empty;
            var visited_nodes: std.SinglyLinkedList(u32) = .{};

            const StackFrame = std.SinglyLinkedList(u32).Node;

            if (self.root_idx == NULL_IDX) return .empty;
            var current_idx = self.root_idx;

            while (visited_nodes.first != null or current_idx != NULL_IDX) {
                while (current_idx != NULL_IDX) {
                    const stack_entry = try allocator.create(StackFrame);
                    stack_entry.*.data = current_idx;
                    visited_nodes.prepend(stack_entry);

                    const node = &self.nodes.items[current_idx];
                    current_idx = node.left_idx;
                }
                const current = visited_nodes.popFirst().?;
                current_idx = current.*.data;
                allocator.destroy(current);

                try out_list.append(allocator, self.kv_list.items(.key)[current_idx]);
                current_idx = (&self.nodes.items[current_idx]).*.right_idx;
            }

            return out_list;
        }
        ///Search for all the keys which match a range of values
        pub fn filter(self: *Self, min: K, max: K, out_buffer: []K) usize {
            assert(compare_fn(min, max) != .gt);

            const keys = self.kv_list.items(.key);
            if (self.root_idx == NULL_IDX) return 0;
            const node = &self.nodes.items[self.root_idx];

            return node.filter(&self.nodes, self.root_idx, keys, min, max, out_buffer, 0);
        }
        ///Note: When using this method, it is your responsibility to make sure that all modifications to the value are coherent with the structure of the other values
        ///
        /// E.g For a value which is a struct, making sure that the re-assigned value has all of the fields of the old value
        /// Failure to do this will result in an inconsistent tree structure.
        ///
        ///Gets a index to the value in the tree for the given key.
        pub fn getValueIdx(self: *Self, key: K) u32 {
            if (self.root_idx == NULL_IDX) return NULL_IDX; // No nodes in the tree
            var root = self.nodes.items[self.root_idx];
            const idx = root.search(&self.nodes, self.kv_list.items(.key), key);

            if (idx == NULL_IDX) return NULL_IDX;
            return idx;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.nodes.deinit(allocator);
            self.kv_list.deinit(allocator);
        }

        pub fn search(self: *Self, key: K) ?V {
            if (self.root_idx == NULL_IDX) return null; // No nodes in the tree
            var root = self.nodes.items[self.root_idx];
            const idx = root.search(&self.nodes, self.kv_list.items(.key), key);

            if (idx == NULL_IDX) return null;
            return self.kv_list.get(idx).value;
        }
    };
}

/// Note: Could the logic about the keys be moved out of the node somehow? Perhaps some more efficiency could be netted by taking it to the tree
pub fn node_gen(K: type, comptime compare_fn: fn (entry: K, self_entry: K) Order) type {
    return struct {
        const Node = @This();
        const NodeList = std.ArrayListUnmanaged(Node);
        const Keys = []const K;
        left_idx: u32 = NULL_IDX, //handles into an array for increased cache locality, use NULL_IDX to represent a null handle
        right_idx: u32 = NULL_IDX,
        parent_idx: u32,
        ///Note: When ParentDirection == .Root, the parent field is required to be null, any other thing implies a programmer error
        parent_direction: ParentDirection,
        colour: Colour = .Black,
        key_idx: u32, //index to the array of keys

        ///Gets the would-be parent of a new key insert, or the index of the value if the key already exists
        pub fn getParentForPut(self: *Node, nodes: *const NodeList, keys: Keys, self_idx: u32, key: K) struct { parent_branch_pointer: *u32, parent_idx: u32, key_idx: u32, parent_direction: u2, found_existing: bool } {
            const compare: Order = compare_fn(key, keys[self.key_idx]);

            const branch_idx: *u32, const direction: u1 = switch (compare) {
                .eq => return .{
                    .key_idx = self.key_idx,
                    .parent_idx = NULL_IDX,
                    .parent_direction = 3, //The direction is invalid in this case, set to a wrong value to break attempts to enumCast it
                    .parent_branch_pointer = @constCast(&NULL_IDX),
                    .found_existing = true,
                },
                .lt => .{ &self.left_idx, 0 },
                .gt => .{ &self.right_idx, 1 },
            };

            //maybe address branch misses later
            if (branch_idx.* != NULL_IDX) {
                var node = &nodes.*.items[branch_idx.*];
                return node.getParentForPut(nodes, keys, branch_idx.*, key);
            }

            return .{ .key_idx = NULL_IDX, .parent_idx = self_idx, .parent_direction = direction, .parent_branch_pointer = branch_idx, .found_existing = false };
        }

        pub fn search(self: *Node, nodes: *const NodeList, keys: Keys, key: K) u32 {
            const compare = compare_fn(key, keys[self.key_idx]);
            if (compare == .eq) return self.key_idx;
            const branch_idx = if (compare == .lt) &self.left_idx else &self.right_idx;

            if (branch_idx.* == NULL_IDX) return NULL_IDX;
            const child = &nodes.items[branch_idx.*];
            return child.*.search(nodes, keys, key);
        }

        pub fn delete(self: *Node, nodes: *NodeList, keys: Keys, self_idx: u32, key: K) struct { root_idx: u32, removed_idx: u32 } {
            const compare = compare_fn(key, keys[self.key_idx]);
            if (compare == .lt) {
                if (self.left_idx == NULL_IDX) return .{ .root_idx = NULL_IDX, .removed_idx = NULL_IDX };
                var call_move_left_red = false;

                //if left is black and left.left is black
                var left = &nodes.items[self.left_idx];
                blk: {
                    if (left.colour != .Black) break :blk;
                    if (left.left_idx == NULL_IDX) {
                        call_move_left_red = true;
                        break :blk;
                    }
                    const left_left = nodes.items[left.left_idx];
                    if (left_left.colour != .Black) break :blk;
                    call_move_left_red = true;
                }
                if (call_move_left_red) self.move_left_red(nodes, self_idx);
                return left.delete(nodes, keys, self.left_idx, key);
            } else {
                if (self.left_idx != NULL_IDX) {
                    const left = nodes.items[self.left_idx];
                    if (left.colour == .Red) {
                        rotate_right(nodes, self_idx, false);
                    }
                }

                if (compare == .eq and self.right_idx == NULL_IDX) {
                    if (self.parent_idx == NULL_IDX) return .{ .root_idx = NULL_IDX, .removed_idx = self_idx };
                    const parent = &nodes.items[self.parent_idx];
                    const branch_ptr = switch (self.parent_direction) {
                        .Left => left: {
                            assert(parent.*.left_idx == self_idx);
                            break :left &parent.*.left_idx;
                        },
                        .Right => right: {
                            assert(parent.*.right_idx == self_idx);
                            break :right &parent.*.right_idx;
                        },
                        else => @panic("root node with parent"),
                    };
                    branch_ptr.* = NULL_IDX;
                    const root_idx = fix_up(nodes, self.parent_idx);
                    return .{ .root_idx = root_idx, .removed_idx = self_idx };
                }

                var call_move_right_red = false;
                //if right is black and right.left is black
                const right = &nodes.items[self.right_idx];
                blk: { //if right is black and right.left is black
                    if (right.colour != .Black) break :blk;
                    if (right.left_idx == NULL_IDX) {
                        call_move_right_red = true;
                        break :blk;
                    }
                    const right_left = nodes.items[right.left_idx];
                    if (right_left.colour != .Black) break :blk;
                    call_move_right_red = true;
                }
                if (call_move_right_red) self.move_right_red(nodes, self_idx);

                if (compare == .eq) {
                    //find a minimum key in the node's right sub-tree(successor)
                    const rt = &nodes.items[self.right_idx]; //There was an earlier check to ensure that the right tree exists
                    var successor_idx = self.right_idx;

                    var successor: *Node = rt;
                    var successor_parent_direction: ParentDirection = .Right;
                    while (successor.*.left_idx != NULL_IDX) {
                        std.debug.print("key:{}\n", .{keys[successor.key_idx]});
                        const call_move_left_red =
                            blk: {
                                if (successor.left_idx == NULL_IDX) break :blk true;
                                const left = &nodes.items[successor.left_idx];
                                if (left.colour != .Black) break :blk false;

                                if (left.left_idx == NULL_IDX) break :blk true;
                                const left_left = &nodes.items[left.left_idx];
                                if (left_left.colour != .Black) break :blk false;
                                break :blk true;
                            };
                        if (call_move_left_red) successor.move_left_red(nodes, successor_idx);
                        successor_idx = successor.*.left_idx;
                        successor = &nodes.items[successor.*.left_idx];
                        successor_parent_direction = .Left;
                    }

                    //Now replace the deleted node with its successor
                    const successor_parent = &nodes.items[successor.parent_idx];
                    var balance_idx = successor.parent_idx;
                    replace: {
                        switch (successor_parent_direction) {
                            .Left => {
                                successor_idx = successor_parent.*.left_idx;
                                successor_parent.*.left_idx = NULL_IDX;
                                if (successor_parent.*.right_idx != NULL_IDX) balance_idx = successor_parent.*.right_idx;
                            },
                            .Right => {
                                successor_idx = successor_parent.*.right_idx;
                                successor_parent.*.right_idx = NULL_IDX;
                                if (successor_parent.*.right_idx != NULL_IDX) balance_idx = successor_parent.*.left_idx;
                            },
                            .Root => @panic("root cannot be the successor"),
                        }

                        successor.*.parent_direction = self.parent_direction;
                        successor.*.parent_idx = self.parent_idx;
                        successor.*.left_idx = self.left_idx;
                        successor.*.right_idx = self.right_idx;
                        successor.*.colour = self.colour;

                        if (successor.*.right_idx != NULL_IDX) {
                            const right_child = &nodes.items[successor.*.right_idx];
                            right_child.*.parent_idx = successor_idx;
                        }

                        if (successor.*.left_idx != NULL_IDX) {
                            const left_child = &nodes.items[successor.*.left_idx];
                            left_child.*.parent_idx = successor_idx;
                        }

                        if (self.parent_idx == NULL_IDX) {
                            assert(self.parent_direction == .Root);
                            break :replace;
                        }
                        const deleted_node_parent = &nodes.items[self.parent_idx];

                        switch (self.parent_direction) {
                            .Root => {
                                assert(self.parent_idx == NULL_IDX);
                            },
                            .Left => {
                                assert(deleted_node_parent.left_idx == self_idx);
                                deleted_node_parent.*.left_idx = successor_idx;
                                if (deleted_node_parent.*.right_idx != NULL_IDX) balance_idx = deleted_node_parent.*.right_idx;
                            },
                            .Right => {
                                assert(deleted_node_parent.right_idx == self_idx);
                                deleted_node_parent.*.right_idx = successor_idx;
                                if (deleted_node_parent.*.left_idx != NULL_IDX) balance_idx = deleted_node_parent.*.left_idx;
                            },
                        }
                    }
                    self.parent_idx = NULL_IDX;
                    self.right_idx = NULL_IDX;
                    self.left_idx = NULL_IDX;
                    // std.debug.print("tree state: {}\nkeys: {any}", .{ nodes, keys });
                    // std.process.exit(1);
                    const root_idx = fix_up(nodes, balance_idx);
                    return .{ .root_idx = root_idx, .removed_idx = self_idx };
                } else return right.delete(nodes, keys, self.right_idx, key);
            }
        }

        pub fn filter(self: *const Node, nodes: *const NodeList, self_idx: u32, keys: Keys, min: K, max: K, out_buffer: []K, index: usize) usize {
            if (index >= out_buffer.len) return index;

            var idx = index;
            const min_comp = compare_fn(min, keys[self_idx]);
            if (min_comp == .lt) {
                const left_idx = self.left_idx;
                if (left_idx != NULL_IDX) {
                    const left = &nodes.items[left_idx];
                    idx = left.filter(nodes, left_idx, keys, min, max, out_buffer, idx);
                    if (idx >= out_buffer.len) return idx; // Check after left traversal
                }
            }

            const max_comp = compare_fn(max, keys[self_idx]);

            if (min_comp != .gt and max_comp != .lt) {
                out_buffer[idx] = keys[self_idx];
                idx += 1;
                if (idx >= out_buffer.len) return idx; // Check after adding current node
            }

            if (max_comp == .gt) {
                const right_idx = self.right_idx;
                if (right_idx != NULL_IDX) {
                    const right = &nodes.items[right_idx];
                    idx = right.filter(nodes, right_idx, keys, min, max, out_buffer, idx);
                }
            }

            return idx;
        }

        pub fn move_left_red(self: *Node, nodes: *NodeList, self_idx: u32) void {
            colour_flip(self, nodes, self_idx, false);
            //if right.left is red
            if (self.right_idx == NULL_IDX) return;
            const right = nodes.items[self.right_idx];

            if (right.left_idx == NULL_IDX) return;
            const right_left = nodes.items[right.left_idx];
            if (right_left.colour == .Red) {
                rotate_right(nodes, self.right_idx, false);
                rotate_left(nodes, self_idx, false);
                const parent = &nodes.items[self.parent_idx];
                colour_flip(parent, nodes, self.parent_idx, false);
                if (parent.parent_direction == .Root) parent.colour = .Black;
            }

            return;
        }

        pub fn move_right_red(self: *Node, nodes: *NodeList, self_idx: u32) void {
            colour_flip(self, nodes, self_idx, false);

            //if left.left is red
            if (self.left_idx == NULL_IDX) return;
            const left = nodes.items[self.left_idx];

            if (left.left_idx == NULL_IDX) return;
            const left_left = nodes.items[left.left_idx];
            if (left_left.colour == .Black) return;

            rotate_right(nodes, self_idx, false);
            const parent = &nodes.items[self.parent_idx];
            colour_flip(parent, nodes, self.parent_idx, false);
            if (parent.parent_direction == .Root) parent.colour = .Black;
            return;
        }
        // ///Preconditions and Rules:
        //You can only rotate left on a node with a red right link
        // //Rotating left on the root node makes the child node the new root
        ///The safety_check flag indicates whether or not to add the assertions for inserts and balances
        pub fn rotate_left(nodes: *NodeList, node_idx: u32, safety_check: bool) void {
            const node = &nodes.items[node_idx];

            assert(node.right_idx != NULL_IDX);

            const right_child_idx = node.right_idx;
            const right_child = &nodes.items[right_child_idx];
            if (safety_check) assert(right_child.*.colour == .Red);

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

        //Preconditions and Rules:
        // You can only rotate right on a node with a red left link
        // Rotating right on the root node makes the child node the new root
        ///The safety_check flag indicates whether or not to add the assertions for inserts and balances
        pub fn rotate_right(nodes: *NodeList, node_idx: u32, safety_check: bool) void {
            const node = access(node_idx, nodes);

            assert(node.left_idx != NULL_IDX);
            const left_child = access(node.left_idx, nodes);

            if (safety_check) assert(left_child.colour == .Red);

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

            if (node.parent_idx == NULL_IDX) {
                @panic("Cannot balance the root node"); //The previous check should stop this from being triggered

            }

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
                    colour_flip(parent, nodes, parent_idx, true);

                    switch (parent.parent_direction) {
                        .Root => {
                            assert(parent.parent_idx == NULL_IDX);
                            parent.colour = .Black;
                            return parent_idx;
                        },
                        else => return balance_tree(nodes, parent_idx),
                    }
                }
                rotate_left(nodes, parent_idx, true);
                return balance_tree(nodes, node.left_idx);
            } else { //a left red child
                //Because of the earlier assertion, we are assured that the parent of this node is not the root node
                if (parent.colour == .Red) { //Double red left-links, we need to rotate

                    //This state should be impossible to reach, hence the assertion
                    if (parent.parent_idx == NULL_IDX) @panic("Cannot have double red links without a grandparent\n");
                    const grand_parent_idx = parent.parent_idx;

                    rotate_right(nodes, grand_parent_idx, true);
                    //After flipping, the grandparent is now the child of the parent, hence this code -- man, what is this family tree nonsense?
                    colour_flip(parent, nodes, node.parent_idx, true); //Rotating a double-left always requires a subsequent colour flip

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

        fn fix_up(nodes: *NodeList, node_idx: u32) u32 {
            assert(node_idx != NULL_IDX);
            const node = &nodes.items[node_idx];

            right_link: {
                if (node.right_idx == NULL_IDX) break :right_link;
                if (node.left_idx != NULL_IDX) {
                    const left = nodes.items[node.left_idx];
                    if (left.colour == .Red) break :right_link;
                }

                const right = &nodes.items[node.right_idx];
                if (right.colour != .Red) break :right_link;
                rotate_left(nodes, node_idx, true);
                return fix_up(nodes, node.parent_idx);
            }

            flip_check: {
                if (node.left_idx == NULL_IDX) break :flip_check;
                if (node.right_idx == NULL_IDX) break :flip_check;
                const left = &nodes.items[node.left_idx];
                const right = &nodes.items[node.right_idx];

                if (left.colour != .Red or right.colour != .Red) break :flip_check;
                colour_flip(node, nodes, node_idx, true);
            }

            left_left: {
                if (node.left_idx == NULL_IDX) break :left_left;
                const left = &nodes.items[node.left_idx];

                if (left.colour != .Red) break :left_left;
                if (left.left_idx == NULL_IDX) break :left_left;

                const left_left = &nodes.items[left.left_idx];
                if (left_left.colour != .Red) break :left_left;
                rotate_right(nodes, node_idx, true);
                colour_flip(node, nodes, node.parent_idx, true); //rotating right to fix a left-left always results in a colour flip
            }

            if (node.parent_direction == .Root) {
                assert(node.parent_idx == NULL_IDX);
                node.colour = .Black;
                return node_idx;
            }
            return fix_up(nodes, node.parent_idx);
        }

        ///NOTE TO SELF: The node_idx parameter here is useless. Remove it.
        ///The safety_check flag indicates whether or not to add the assertions for inserts and balances
        fn colour_flip(node: *Node, nodes: *NodeList, node_idx: u32, safety_check: bool) void {
            if (node.left_idx == NULL_IDX or node.right_idx == NULL_IDX) {
                std.debug.panic("Can't flip without two children.\nNodes:{}\t{}", .{ node.left_idx, node.right_idx });
            }
            assert(access(node_idx, nodes) == node);

            const left = access(node.left_idx, nodes);
            const right = access(node.right_idx, nodes);
            if (safety_check) assert(left.colour == .Red and right.colour == .Red);

            left.colour = @enumFromInt(~@intFromEnum(left.colour));
            right.colour = @enumFromInt(~@intFromEnum(right.colour));
            node.colour = @enumFromInt(~@intFromEnum(node.colour));
        }

        pub fn access(index: u32, nodes: *NodeList) *Node {
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
    var rb_tree = try Tree(i32, compareInt).init_with_capacity(allocator, @as(usize, num_elements_insert), numbers_to_insert[0]);
    defer rb_tree.deinit(allocator);

    for (numbers_to_insert[1..]) |value| {
        // The `insert` function can return `null` if value already exists or `!*Self` on error.
        // We'll assume for benchmark purposes that errors are fatal and duplicates are skipped.
        rb_tree.insert(value);
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
