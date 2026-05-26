//! A packed stack of `u1`s.
const BitStack = @This();

const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

bytes: []u8,
bit_len: usize,

pub const empty: BitStack = .{
    .bytes = &.{},
    .bit_len = 0,
};

/// Returns capacity in bits.
pub fn capacity(self: BitStack) usize {
    return self.bytes.len * 8;
}

/// Initialize with capacity to hold `num_bits` bits,
/// rounded to the next highest multiple of 8.
/// Deinitialize with `deinit`.
pub fn initCapacity(gpa: Allocator, num_bits: usize) Allocator.Error!BitStack {
    var self: BitStack = .empty;
    try self.ensureTotalCapacityPrecise(gpa, num_bits);
    return self;
}
/// Initialize with externally-managed memory. The buffer
/// determines the capacity.
///
/// When initialized this way, all functions that accept an Allocator
/// argument cause illegal behavior.
pub fn initBuffer(bytes: []u8) BitStack {
    return .{
        .bytes = bytes,
        .bit_len = 0,
    };
}
/// Creates a copy of `self`.
/// Deinitialize with `deinit`.
pub fn clone(self: BitStack, gpa: Allocator) Allocator.Error!BitStack {
    var cloned = try initCapacity(gpa, self.capacity());
    errdefer cloned.deinit(gpa);
    @memcpy(cloned.bytes, self.bytes);
    cloned.bit_len = self.bit_len;
    return cloned;
}
/// Release all allocated memory.
pub fn deinit(self: *BitStack, gpa: Allocator) void {
    gpa.free(self.bytes);
    self.* = undefined;
}

/// If the current capacity is less than `num_bits`,
/// expand capacity such that self can hold at least
/// `num_bits` bits.
pub fn ensureTotalCapacity(self: *BitStack, gpa: Allocator, num_bits: usize) Allocator.Error!void {
    const new_num_bytes = std.ArrayList(u8).growCapacity(numBitsToNumBytes(num_bits));
    const new_num_bits = std.math.mul(usize, new_num_bytes, 8) catch return error.OutOfMemory;
    return self.ensureTotalCapacityPrecise(gpa, new_num_bits);
}
/// If the current capacity is less than `num_bits`,
/// expand capacity such that self can hold `num_bits` bits.
/// Rounds to the next highest multiple of 8.
pub fn ensureTotalCapacityPrecise(self: *BitStack, gpa: Allocator, num_bits: usize) Allocator.Error!void {
    if (self.capacity() >= num_bits) return;

    const num_bytes = numBitsToNumBytes(num_bits);
    const old_bytes = self.bytes;
    if (gpa.remap(old_bytes, num_bytes)) |new_bytes| {
        self.bytes = new_bytes;
    } else {
        const new_bytes = try gpa.alloc(u8, num_bytes);
        @memcpy(new_bytes[0..old_bytes.len], old_bytes);
        gpa.free(old_bytes);
        self.bytes = new_bytes;
    }
}
/// Expand capacity such that `self` can hold up to
/// `additional_bits` more bits.
pub fn ensureUnusedCapacity(self: *BitStack, gpa: Allocator, additional_bits: usize) Allocator.Error!void {
    const num_bits = std.math.add(usize, self.bit_len, additional_bits) catch return error.OutOfMemory;
    return self.ensureTotalCapacity(gpa, num_bits);
}

pub fn push(self: *BitStack, gpa: Allocator, bit: u1) Allocator.Error!void {
    try self.ensureUnusedCapacity(gpa, 1);
    self.pushAssumeCapacity(bit);
}
/// If `self` cannot hold an additional bit, returns
/// `error.OutOfMemory`.
pub fn pushBounded(self: *BitStack, bit: u1) error{OutOfMemory}!void {
    return buffer.pushBounded(self.bytes, &self.bit_len, bit);
}
/// Asserts that `self` can hold an additional bit.
pub fn pushAssumeCapacity(self: *BitStack, bit: u1) void {
    return buffer.pushAssumeCapacity(self.bytes, &self.bit_len, bit);
}

/// Remove and return top-most bit from `self`.
/// If `self` is empty, returns `null`.
pub fn pop(self: *BitStack) ?u1 {
    return buffer.pop(self.bytes, &self.bit_len);
}
/// Return top-most bit from `self`.
/// If `self` is empty, returns `null`.
pub fn peek(self: BitStack) ?u1 {
    return buffer.peek(self.bytes, self.bit_len);
}

/// Standalone functions for working with buffers
/// that aren't `BitStack`s.
pub const buffer = struct {
    /// If `bytes` cannot hold an additional bit, returns
    /// `error.OutOfMemory`.
    pub fn pushBounded(bytes: []u8, bit_len: *usize, bit: u1) error{OutOfMemory}!void {
        if (bit_len.* >= bytes.len * 8) return error.OutOfMemory;
        buffer.pushAssumeCapacity(bytes, bit_len, bit);
    }
    /// Asserts that `bytes` can hold an additional bit.
    pub fn pushAssumeCapacity(bytes: []u8, bit_len: *usize, bit: u1) void {
        assert(bit_len.* < bytes.len * 8);

        const byte_idx, const bit_idx = bitIdxToByteIdx(bit_len.*);
        bytes[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        bytes[byte_idx] |= @as(u8, bit) << bit_idx;
        bit_len.* += 1;
    }
    /// Return the top-most bit and lower `bit_len` by one.
    /// Returns `null` if `bit_len` is zero.
    pub fn pop(bytes: []const u8, bit_len: *usize) ?u1 {
        const bit = buffer.peek(bytes, bit_len.*) orelse return null;
        bit_len.* -= 1;
        return bit;
    }
    /// Return the top-most bit.
    /// Returns `null` if `bit_len` is zero.
    pub fn peek(bytes: []const u8, bit_len: usize) ?u1 {
        if (bit_len <= 0) return null;
        const byte_idx, const bit_idx = bitIdxToByteIdx(bit_len - 1);
        const byte = bytes[byte_idx];
        const bit: u1 = @intCast((byte >> bit_idx) & 1);
        return bit;
    }
};

/// Returns the split byte and bit index based on a bit index.
fn bitIdxToByteIdx(bit_idx: usize) struct { usize, u3 } {
    return .{
        bit_idx >> 3,
        @intCast(bit_idx & 0b111),
    };
}
/// Returns the minimum number of bytes necessary
/// to represent a number of bits.
fn numBitsToNumBytes(num_bits: usize) usize {
    return (num_bits + 7) >> 3;
}
test numBitsToNumBytes {
    try testing.expectEqual(0, numBitsToNumBytes(0));
    for (1..9) |i| try testing.expectEqual(1, numBitsToNumBytes(i));
    for (9..17) |i| try testing.expectEqual(2, numBitsToNumBytes(i));
    for (17..25) |i| try testing.expectEqual(3, numBitsToNumBytes(i));
    try testing.expectEqual(187, numBitsToNumBytes(1495));
}

/// Deprecated in favor of `BitStack`.
pub const Managed = struct {
    bytes: std.array_list.Managed(u8),
    bit_len: usize = 0,

    pub fn init(allocator: Allocator) @This() {
        return .{
            .bytes = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.bytes.deinit();
        self.* = undefined;
    }

    pub fn ensureTotalCapacity(self: *@This(), bit_capacity: usize) Allocator.Error!void {
        const byte_capacity = (bit_capacity + 7) >> 3;
        try self.bytes.ensureTotalCapacity(byte_capacity);
    }

    pub fn push(self: *@This(), b: u1) Allocator.Error!void {
        const byte_index = self.bit_len >> 3;
        if (self.bytes.items.len <= byte_index) {
            try self.bytes.append(0);
        }

        pushWithStateAssumeCapacity(self.bytes.items, &self.bit_len, b);
    }

    pub fn peek(self: *const @This()) u1 {
        return peekWithState(self.bytes.items, self.bit_len);
    }

    pub fn pop(self: *@This()) u1 {
        return popWithState(self.bytes.items, &self.bit_len);
    }

    /// Deprecated in favor of `BitStack.buffer.pushAssumeCapacity`.
    pub fn pushWithStateAssumeCapacity(buf: []u8, bit_len: *usize, b: u1) void {
        buffer.pushAssumeCapacity(buf, bit_len, b);
    }

    /// Deprecated in favor of `BitStack.buffer.peek`.
    pub fn peekWithState(buf: []const u8, bit_len: usize) u1 {
        return buffer.peek(buf, bit_len).?;
    }

    /// Deprecated in favor of `BitStack.buffer.pop`.
    pub fn popWithState(buf: []const u8, bit_len: *usize) u1 {
        return buffer.pop(buf, bit_len).?;
    }
};

test Managed {
    var stack = Managed.init(testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(0);
    try stack.push(0);
    try stack.push(1);

    try testing.expectEqual(@as(u1, 1), stack.peek());
    try testing.expectEqual(@as(u1, 1), stack.pop());
    try testing.expectEqual(@as(u1, 0), stack.peek());
    try testing.expectEqual(@as(u1, 0), stack.pop());
    try testing.expectEqual(@as(u1, 0), stack.pop());
    try testing.expectEqual(@as(u1, 1), stack.pop());
}

test "basic usage" {
    const gpa = testing.allocator;

    var stack: BitStack = .empty;
    defer stack.deinit(gpa);

    try testing.expectError(error.OutOfMemory, stack.pushBounded(1));

    try stack.ensureUnusedCapacity(gpa, 6);
    stack.pushAssumeCapacity(1);
    try stack.push(gpa, 0);
    try stack.pushBounded(1);
    try stack.push(gpa, 1);
    stack.pushAssumeCapacity(0);
    try stack.pushBounded(0);

    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(null, stack.pop());

    stack.pushAssumeCapacity(1);
    try testing.expectEqual(1, stack.peek());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(null, stack.peek());
}
test initCapacity {
    const gpa = testing.allocator;
    {
        var stack = try BitStack.initCapacity(gpa, 5);
        defer stack.deinit(gpa);
        try testing.expectEqual(8, stack.capacity());
        try testing.expectEqual(0, stack.bit_len);
    }
    { // Doesn't allocate on zero capacity.
        var stack = try BitStack.initCapacity(testing.failing_allocator, 0);
        defer stack.deinit(testing.failing_allocator);
        try testing.expectEqual(0, stack.capacity());
        try testing.expectEqual(0, stack.bit_len);
    }
}
test initBuffer {
    const gpa = testing.allocator;

    const bytes = try gpa.alloc(u8, 1);
    defer gpa.free(bytes);

    var stack: BitStack = .initBuffer(bytes);

    try testing.expectEqual(8, stack.capacity());
    try stack.pushBounded(1);
    try stack.pushBounded(1);
    try stack.pushBounded(0);
    try stack.pushBounded(0);
    try stack.pushBounded(1);
    try stack.pushBounded(0);
    try stack.pushBounded(1);
    try stack.pushBounded(0);
    try testing.expectError(error.OutOfMemory, stack.pushBounded(0));
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(0, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(1, stack.pop());
    try testing.expectEqual(null, stack.pop());
}
test clone {
    const gpa = testing.allocator;

    var stack: BitStack = .empty;
    defer stack.deinit(gpa);
    try stack.push(gpa, 1);
    try stack.push(gpa, 0);
    try stack.push(gpa, 0);

    var cpy = try stack.clone(gpa);
    defer cpy.deinit(gpa);

    try testing.expectEqual(stack.capacity(), cpy.capacity());
    try testing.expectEqual(stack.bit_len, cpy.bit_len);

    try cpy.push(gpa, 1);
    try testing.expectEqual(1, cpy.pop());
    try testing.expectEqual(0, cpy.pop());
    try testing.expectEqual(0, cpy.pop());
    try testing.expectEqual(1, cpy.pop());
    try testing.expectEqual(null, cpy.pop());

    // Ensure the original wasn't modified.
    try testing.expectEqual(0, stack.pop());
}
test "passes through allocation failure" {
    var stack: BitStack = .empty;
    try testing.expectError(error.OutOfMemory, stack.push(testing.failing_allocator, 1));
}
