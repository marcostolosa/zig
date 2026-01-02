const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const mem = std.mem;

/// Describes how pointer and float types should be hashed.
pub const HashStrategy = struct {
    pointers: Pointers,
    floats: Floats,

    pub const Pointers = enum {
        /// Do not follow pointers, only hash their value.
        shallow,

        /// Follow pointers, hash the pointee content.
        /// Only dereferences one level, i.e. it is changed into .shallow when a
        /// pointer type is encountered.
        deep,

        /// Follow pointers, hash the pointee content.
        /// Dereferences all pointers encountered.
        /// Assumes no cycle.
        deep_recursive,
    };

    pub const Floats = enum {
        /// Results in a compile error. Choose a disambiguation strategy.
        unsupported,

        /// Automatically hash floats by mathematical value.
        /// -0.0 and 0.0 hash identically.
        /// Asserts that no key is NaN.
        normalized,
    };
};

/// Helper function to hash a pointer and mutate the strategy if needed.
fn hashPointer(hasher: anytype, key: anytype, comptime strat: HashStrategy) void {
    const info = @typeInfo(@TypeOf(key));

    switch (info.pointer.size) {
        .one => switch (strat.pointers) {
            .shallow => hash(hasher, @intFromPtr(key), .{ .pointers = .shallow, .floats = strat.floats }),
            .deep => hash(hasher, key.*, .{ .pointers = .shallow, .floats = strat.floats }),
            .deep_recursive => hash(hasher, key.*, .{ .pointers = .deep_recursive, .floats = strat.floats }),
        },

        .slice => {
            switch (strat.pointers) {
                .shallow => hashPointer(hasher, key.ptr, .{ .pointers = .shallow, .floats = strat.floats }),
                .deep => hashArray(hasher, key, .{ .pointers = .shallow, .floats = strat.floats }),
                .deep_recursive => hashArray(hasher, key, .{ .pointers = .deep_recursive, .floats = strat.floats }),
            }
            hash(hasher, key.len, .{ .pointers = .shallow, .floats = strat.floats });
        },

        .many,
        .c,
        => switch (strat.pointers) {
            .shallow => hash(hasher, @intFromPtr(key), .{ .pointers = .shallow, .floats = strat.floats }),
            else => @compileError(
                \\ unknown-length pointers and C pointers cannot be hashed deeply.
                \\ Consider providing your own hash function.
            ),
        },
    }
}

/// Helper function to hash a set of contiguous objects, from an array or slice.
fn hashArray(hasher: anytype, key: anytype, comptime strat: HashStrategy) void {
    for (key) |element| {
        hash(hasher, element, strat);
    }
}

/// Provides generic hashing for any eligible type.
pub fn hash(hasher: anytype, key: anytype, comptime strat: HashStrategy) void {
    const Key = @TypeOf(key);
    const Hasher = switch (@typeInfo(@TypeOf(hasher))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(hasher),
    };

    if (strat.pointers == .shallow and std.meta.hasUniqueRepresentation(Key)) {
        @call(.always_inline, Hasher.update, .{ hasher, mem.asBytes(&key) });
        return;
    }

    switch (@typeInfo(Key)) {
        .noreturn,
        .@"opaque",
        .spirv,
        .undefined,
        .null,
        .comptime_float,
        .comptime_int,
        .type,
        .enum_literal,
        .frame,
        => @compileError("unable to hash type " ++ @typeName(Key)),

        .void => return,

        // Help the optimizer see that hashing an int is easy by inlining!
        // TODO Check if the situation is better after #561 is resolved.
        .int => |int| switch (int.signedness) {
            .signed => hash(hasher, @as(@Int(.unsigned, int.bits), @bitCast(key)), strat),
            .unsigned => {
                if (std.meta.hasUniqueRepresentation(Key)) {
                    @call(.always_inline, Hasher.update, .{ hasher, std.mem.asBytes(&key) });
                } else {
                    // Take only the part containing the key value, the remaining
                    // bytes are undefined and must not be hashed!
                    const byte_size = @divCeil(@bitSizeOf(Key), 8);
                    @call(.always_inline, Hasher.update, .{ hasher, std.mem.asBytes(&key)[0..byte_size] });
                }
            },
        },

        .float => switch (strat.floats) {
            .unsupported => @compileError("std.hash.autoHash does not allow hashing floats because the possible methods for doing so involve restrictions/tradeoffs. Consider using std.hash.autoHashStrat or providing your own hash function instead."),
            .normalized => hashFloat(hasher, key, strat.floats),
        },

        .bool => hash(hasher, @intFromBool(key), strat),
        .@"enum" => hash(hasher, @backingInt(key), strat),
        .error_set => hash(hasher, @intFromError(key), strat),
        .@"anyframe", .@"fn" => hash(hasher, @intFromPtr(key), strat),

        .pointer => @call(.always_inline, hashPointer, .{ hasher, key, strat }),

        .optional => if (key) |k| hash(hasher, k, strat),

        .array => hashArray(hasher, key, strat),

        .vector => |info| {
            if (std.meta.hasUniqueRepresentation(Key)) {
                hasher.update(mem.asBytes(&key));
            } else {
                comptime var i = 0;
                inline while (i < info.len) : (i += 1) {
                    hash(hasher, key[i], strat);
                }
            }
        },

        .@"struct" => |info| {
            inline for (info.field_names) |field_name| {
                // We reuse the hash of the previous field as the seed for the
                // next one so that they're dependant.
                hash(hasher, @field(key, field_name), strat);
            }
        },

        .@"union" => |info| blk: {
            if (info.tag_type) |tag_type| {
                const tag = std.meta.activeTag(key);
                hash(hasher, tag, strat);
                inline for (info.field_names, info.field_types) |field_name, field_type| {
                    if (@field(tag_type, field_name) == tag) {
                        if (field_type != void) {
                            hash(hasher, @field(key, field_name), strat);
                        }
                        break :blk;
                    }
                }
                unreachable;
            } else @compileError("cannot hash untagged union type: " ++ @typeName(Key) ++ ", provide your own hash function");
        },

        .error_union => blk: {
            const payload = key catch |err| {
                hash(hasher, err, strat);
                break :blk;
            };
            hash(hasher, payload, strat);
        },
    }
}

inline fn typeContainsSlice(comptime K: type) bool {
    return switch (@typeInfo(K)) {
        .pointer => |info| info.size == .slice,

        inline .@"struct", .@"union" => |info| {
            inline for (info.field_types) |field_type| {
                if (typeContainsSlice(field_type)) {
                    return true;
                }
            }
            return false;
        },

        else => false,
    };
}

/// Provides generic hashing for any eligible type.
/// Only hashes `key` itself, pointers are not followed.
/// Slices as well as unions and structs containing slices are rejected to avoid
/// ambiguity on the user's intention.
pub fn autoHash(hasher: anytype, key: anytype) void {
    const Key = @TypeOf(key);
    if (comptime typeContainsSlice(Key)) {
        @compileError("std.hash.autoHash does not allow slices as well as unions and structs containing slices here (" ++ @typeName(Key) ++
            ") because the intent is unclear. Consider using std.hash.autoHashStrat or providing your own hash function instead.");
    }

    hash(hasher, key, .{ .pointers = .shallow, .floats = .unsupported });
}

/// Provides either bit-level hashing for floating point numbers or
/// normalized floating point values (asserts NaN).
/// This is not a general purpose hashing function, it is only
/// intended for use with floating point numbers.
fn hashFloat(hasher: anytype, key: anytype, comptime strat: HashStrategy.Floats) void {
    const Key = @TypeOf(key);

    if (@typeInfo(Key) != .float) {
        @compileError("hashFloat only supports floating point numbers, found " ++ @typeName(Key));
    }

    const norm_key = switch (strat) {
        .unsupported => unreachable,
        .normalized => blk: {
            assert(!math.isNan(key));
            break :blk if (key == 0.0) 0.0 else key;
        },
    };
    const U = @Int(.unsigned, @bitSizeOf(Key));
    hash(hasher, @as(U, @bitCast(norm_key)), .{ .pointers = .shallow, .floats = .unsupported });
}

const testing = std.testing;
const Wyhash = std.hash.Wyhash;

fn testHash(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .{ .pointers = .shallow, .floats = .unsupported });
    return hasher.final();
}

fn testHashShallow(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .{ .pointers = .shallow, .floats = .unsupported });
    return hasher.final();
}

fn testHashDeep(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .{ .pointers = .deep, .floats = .unsupported });
    return hasher.final();
}

fn testHashDeepRecursive(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hash(&hasher, key, .{ .pointers = .deep_recursive, .floats = .unsupported });
    return hasher.final();
}

fn testHashFloats(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    hashFloat(&hasher, key, .normalized);
    return hasher.final();
}

test "typeContainsSlice" {
    comptime {
        try testing.expect(!typeContainsSlice(std.meta.Tag(std.lang.Type)));

        try testing.expect(typeContainsSlice([]const u8));
        try testing.expect(!typeContainsSlice(u8));
        const A = struct { x: []const u8 };
        const B = struct { a: A };
        const C = struct { b: B };
        const D = struct { x: u8 };
        try testing.expect(typeContainsSlice(A));
        try testing.expect(typeContainsSlice(B));
        try testing.expect(typeContainsSlice(C));
        try testing.expect(!typeContainsSlice(D));
    }
}

test "hash pointer" {
    const array = [_]u32{ 123, 123, 123 };
    const a = &array[0];
    const b = &array[1];
    const c = &array[2];
    const d = a;

    try testing.expect(testHashShallow(a) == testHashShallow(d));
    try testing.expect(testHashShallow(a) != testHashShallow(c));
    try testing.expect(testHashShallow(a) != testHashShallow(b));

    try testing.expect(testHashDeep(a) == testHashDeep(a));
    try testing.expect(testHashDeep(a) == testHashDeep(c));
    try testing.expect(testHashDeep(a) == testHashDeep(b));

    try testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(a));
    try testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(c));
    try testing.expect(testHashDeepRecursive(a) == testHashDeepRecursive(b));
}

test "hash slice shallow" {
    // Allocate one array dynamically so that we're assured it is not merged
    // with the other by the optimization passes.
    const array1 = try std.testing.allocator.create([6]u32);
    defer std.testing.allocator.destroy(array1);
    array1.* = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const array2 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    // TODO audit deep/shallow - maybe it has the wrong behavior with respect to array pointers and slices
    var runtime_zero: usize = 0;
    _ = &runtime_zero;
    const a = array1[runtime_zero..];
    const b = array2[runtime_zero..];
    const c = array1[runtime_zero..3];
    try testing.expect(testHashShallow(a) == testHashShallow(a));
    try testing.expect(testHashShallow(a) != testHashShallow(array1));
    try testing.expect(testHashShallow(a) != testHashShallow(b));
    try testing.expect(testHashShallow(a) != testHashShallow(c));
}

test "hash slice deep" {
    // Allocate one array dynamically so that we're assured it is not merged
    // with the other by the optimization passes.
    const array1 = try std.testing.allocator.create([6]u32);
    defer std.testing.allocator.destroy(array1);
    array1.* = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const array2 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    const a = array1[0..];
    const b = array2[0..];
    const c = array1[0..3];
    try testing.expect(testHashDeep(a) == testHashDeep(a));
    try testing.expect(testHashDeep(a) == testHashDeep(array1));
    try testing.expect(testHashDeep(a) == testHashDeep(b));
    try testing.expect(testHashDeep(a) != testHashDeep(c));
}

test "hash struct deep" {
    const Foo = struct {
        a: u32,
        b: u16,
        c: *bool,

        const Self = @This();

        pub fn init(allocator: mem.Allocator, a_: u32, b_: u16, c_: bool) !Self {
            const ptr = try allocator.create(bool);
            ptr.* = c_;
            return Self{ .a = a_, .b = b_, .c = ptr };
        }
    };

    const allocator = std.testing.allocator;
    const foo = try Foo.init(allocator, 123, 10, true);
    const bar = try Foo.init(allocator, 123, 10, true);
    const baz = try Foo.init(allocator, 123, 10, false);
    defer allocator.destroy(foo.c);
    defer allocator.destroy(bar.c);
    defer allocator.destroy(baz.c);

    try testing.expect(testHashDeep(foo) == testHashDeep(bar));
    try testing.expect(testHashDeep(foo) != testHashDeep(baz));
    try testing.expect(testHashDeep(bar) != testHashDeep(baz));

    var hasher = Wyhash.init(0);
    const h = testHashDeep(foo);
    autoHash(&hasher, foo.a);
    autoHash(&hasher, foo.b);
    autoHash(&hasher, foo.c.*);
    try testing.expectEqual(h, hasher.final());

    const h2 = testHashDeepRecursive(&foo);
    try testing.expect(h2 != testHashDeep(&foo));
    try testing.expect(h2 == testHashDeep(foo));
}

test "testHash optional" {
    const a: ?u32 = 123;
    const b: ?u32 = null;
    try testing.expectEqual(testHash(a), testHash(@as(u32, 123)));
    try testing.expect(testHash(a) != testHash(b));
    try testing.expectEqual(testHash(b), 0x409638ee2bde459); // wyhash empty input hash
}

test "testHash array" {
    const a = [_]u32{ 1, 2, 3 };
    const h = testHash(a);
    var hasher = Wyhash.init(0);
    autoHash(&hasher, @as(u32, 1));
    autoHash(&hasher, @as(u32, 2));
    autoHash(&hasher, @as(u32, 3));
    try testing.expectEqual(h, hasher.final());
}

test "testHash multi-dimensional array" {
    const a = [_][]const u32{ &.{ 1, 2, 3 }, &.{ 4, 5 } };
    const b = [_][]const u32{ &.{ 1, 2 }, &.{ 3, 4, 5 } };
    try testing.expect(testHash(a) != testHash(b));
}

test "testHash struct" {
    const Foo = struct {
        a: u32 = 1,
        b: u32 = 2,
        c: u32 = 3,
    };
    const f = Foo{};
    const h = testHash(f);
    var hasher = Wyhash.init(0);
    autoHash(&hasher, @as(u32, 1));
    autoHash(&hasher, @as(u32, 2));
    autoHash(&hasher, @as(u32, 3));
    try testing.expectEqual(h, hasher.final());
}

test "testHash union" {
    const Foo = union(enum) {
        A: u32,
        B: bool,
        C: u32,
        D: void,
    };

    const a = Foo{ .A = 18 };
    var b = Foo{ .B = true };
    const c = Foo{ .C = 18 };
    const d: Foo = .D;
    try testing.expect(testHash(a) == testHash(a));
    try testing.expect(testHash(a) != testHash(b));
    try testing.expect(testHash(a) != testHash(c));
    try testing.expect(testHash(a) != testHash(d));

    b = Foo{ .A = 18 };
    try testing.expect(testHash(a) == testHash(b));

    b = .D;
    try testing.expect(testHash(d) == testHash(b));
}

test "testHash vector" {
    const a: @Vector(4, u32) = [_]u32{ 1, 2, 3, 4 };
    const b: @Vector(4, u32) = [_]u32{ 1, 2, 3, 5 };
    try testing.expect(testHash(a) == testHash(a));
    try testing.expect(testHash(a) != testHash(b));

    const c: @Vector(4, u31) = [_]u31{ 1, 2, 3, 4 };
    const d: @Vector(4, u31) = [_]u31{ 1, 2, 3, 5 };
    try testing.expect(testHash(c) == testHash(c));
    try testing.expect(testHash(c) != testHash(d));
}

test "testHash error union" {
    const Errors = error{Test};
    const Foo = struct {
        a: u32 = 1,
        b: u32 = 2,
        c: u32 = 3,
    };
    const f = Foo{};
    const g: Errors!Foo = Errors.Test;
    try testing.expect(testHash(f) != testHash(g));
    try testing.expect(testHash(f) == testHash(Foo{}));
    try testing.expect(testHash(g) == testHash(Errors.Test));
}

test "testHash float" {
    inline for (.{
        f16,
        f32,
        f64,
        f80,
        f128,
    }) |F| {
        const neg: F = -0.0;
        const pos: F = 0.0;
        try testing.expect(math.signbit(neg) and !math.signbit(pos));
        try testing.expect(testHashFloats(neg) == testHashFloats(pos));
    }
}
