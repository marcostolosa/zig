const RangeSet = @This();

// The final set of disjoint ranges, sorted by `Range.first`.
// It is empty during insertion and filled by `finalize`.
ranges: std.MultiArrayList(Range),
// Working set while inserting. Sorted only after `finalize`.
tree: Tree,
len: usize,
// Treap nodes are pointer-linked and must not move once inserted.
node_blocks: std.ArrayListUnmanaged([]Tree.Node),
free_nodes: []Tree.Node,

pub const Range = struct {
    first: Value,
    last: Value,
    src: LazySrcLoc,
};

const Key = struct {
    range: Range,
    zcu: *const Zcu, // value comparison needs this
};
const Tree = std.Treap(Key, compareKey);
fn compareKey(a: Key, b: Key) math.Order {
    return a.range.first.order(b.range.first, a.zcu);
}

pub const empty: RangeSet = .{
    .ranges = .empty,
    .tree = .{},
    .len = 0,
    .node_blocks = .empty,
    .free_nodes = &.{},
};

pub fn deinit(self: *RangeSet, allocator: Allocator) void {
    self.ranges.deinit(allocator);
    for (self.node_blocks.items) |block| allocator.free(block);
    self.node_blocks.deinit(allocator);
    self.* = undefined;
}

pub fn ensureUnusedCapacity(self: *RangeSet, allocator: Allocator, additional_count: usize) Allocator.Error!void {
    if (self.free_nodes.len >= additional_count) return;
    try self.node_blocks.ensureUnusedCapacity(allocator, 1);
    const block = try allocator.alloc(Tree.Node, additional_count);
    self.node_blocks.appendAssumeCapacity(block);
    self.free_nodes = block;
}

pub fn addAssumeCapacity(set: *RangeSet, new: Range, ty: Type, zcu: *Zcu) ?LazySrcLoc {
    assert(new.first.typeOf(zcu).eql(ty));
    assert(new.last.typeOf(zcu).eql(ty));
    assert(new.first.compareScalar(.lte, new.last, ty, zcu));

    var entry = set.tree.getEntryFor(.{ .range = new, .zcu = zcu });
    if (entry.node) |existing| {
        return existing.key.range.src;
    }

    const node = &set.free_nodes[0];
    set.free_nodes = set.free_nodes[1..];
    entry.set(node);

    // Disjoint ranges overlap only with a direct neighbor.
    if (node.prev()) |prev| {
        if (prev.key.range.last.compareScalar(.gte, new.first, ty, zcu)) {
            set.unlink(node);
            return prev.key.range.src;
        }
    }
    if (node.next()) |next| {
        if (new.last.compareScalar(.gte, next.key.range.first, ty, zcu)) {
            set.unlink(node);
            return next.key.range.src;
        }
    }

    set.len += 1;
    return null;
}

fn unlink(set: *RangeSet, node: *Tree.Node) void {
    var entry = set.tree.getEntryForExisting(node);
    entry.set(null);
}

pub fn add(set: *RangeSet, allocator: Allocator, new: Range, ty: Type, zcu: *Zcu) Allocator.Error!?LazySrcLoc {
    try set.ensureUnusedCapacity(allocator, 1);
    return set.addAssumeCapacity(new, ty, zcu);
}

/// Flatten `tree` into `ranges` sorted by `Range.first`.
/// Must run after the last insertion.
pub fn finalize(set: *RangeSet, allocator: Allocator) Allocator.Error!void {
    set.ranges.clearRetainingCapacity();
    try set.ranges.ensureTotalCapacity(allocator, set.len);
    var it = set.tree.inorderIterator();
    while (it.next()) |node| {
        set.ranges.appendAssumeCapacity(node.key.range);
    }
}

pub fn spans(
    set: *RangeSet,
    allocator: Allocator,
    first: Value,
    last: Value,
    ty: Type,
    zcu: *Zcu,
) Allocator.Error!bool {
    assert(first.typeOf(zcu).eql(ty));
    assert(last.typeOf(zcu).eql(ty));
    if (set.ranges.len == 0) return false;

    assert(std.sort.isSorted(Value, set.ranges.items(.first), @as(SortCtx, .{ .ty = ty, .zcu = zcu }), lessThan));
    assert(std.sort.isSorted(Value, set.ranges.items(.last), @as(SortCtx, .{ .ty = ty, .zcu = zcu }), lessThan));

    if (!set.ranges.items(.first)[0].eql(first, ty, zcu) or
        !set.ranges.items(.last)[set.ranges.len - 1].eql(last, ty, zcu))
    {
        return false;
    }

    const limbs = try allocator.alloc(
        math.big.Limb,
        math.big.int.calcTwosCompLimbCount(ty.intInfo(zcu).bits),
    );
    defer allocator.free(limbs);
    var counter: math.big.int.Mutable = .init(limbs, 0);

    var space: InternPool.Key.Int.Storage.BigIntSpace = undefined;

    // look for gaps
    for (
        set.ranges.items(.first)[1..],
        set.ranges.items(.last)[0 .. set.ranges.len - 1],
    ) |cur_first, prev_last| {
        // prev_last + 1 == cur_first
        counter.copy(prev_last.toBigInt(&space, zcu));
        counter.addScalar(counter.toConst(), 1);

        const cur_start_int = cur_first.toBigInt(&space, zcu);
        if (!cur_start_int.eql(counter.toConst())) {
            return false;
        }
    }

    return true;
}

const SortCtx = struct {
    ty: Type,
    zcu: *Zcu,
};
fn lessThan(ctx: SortCtx, a: Value, b: Value) bool {
    return a.compareScalar(.lt, b, ctx.ty, ctx.zcu);
}

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const InternPool = @import("InternPool.zig");
const Type = @import("Type.zig");
const Value = @import("Value.zig");
const Zcu = @import("Zcu.zig");
const LazySrcLoc = Zcu.LazySrcLoc;
