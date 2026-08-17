const std = @import("std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const autoHash = std.hash.autoHash;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const Wyhash = std.hash.Wyhash;
const Alignment = std.mem.Alignment;

pub fn getAutoHashFn(comptime K: type, comptime Context: type) (fn (Context, K) u64) {
    comptime {
        assert(@hasDecl(std, "StringHashMap")); // detect when the following message needs updated
        if (K == []const u8) {
            @compileError("std.hash.autoHash does not allow slices here (" ++
                @typeName(K) ++
                ") because the intent is unclear. " ++
                "Consider using std.StringHashMap for hashing the contents of []const u8. " ++
                "Alternatively, consider using std.hash.autoHashStrat or providing your own hash function instead.");
        }
    }

    return struct {
        fn hash(ctx: Context, key: K) u64 {
            _ = ctx;
            if (std.meta.hasUniqueRepresentation(K)) {
                return Wyhash.hash(0, std.mem.asBytes(&key));
            } else {
                var hasher = Wyhash.init(0);
                autoHash(&hasher, key);
                return hasher.final();
            }
        }
    }.hash;
}

pub fn getAutoEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K) bool) {
    return struct {
        fn eql(ctx: Context, a: K, b: K) bool {
            _ = ctx;
            return std.meta.eql(a, b);
        }
    }.eql;
}

pub fn AutoHashMap(comptime K: type, comptime V: type) type {
    return HashMap(K, V, AutoContext(K), default_max_load_percentage);
}

pub fn AutoHashMapUnmanaged(comptime K: type, comptime V: type) type {
    return HashMapUnmanaged(K, V, AutoContext(K), default_max_load_percentage);
}

pub fn AutoContext(comptime K: type) type {
    return struct {
        pub const hash = getAutoHashFn(K, @This());
        pub const eql = getAutoEqlFn(K, @This());
    };
}

/// Builtin hashmap for strings as keys.
/// Key memory is managed by the caller.  Keys and values
/// will not automatically be freed.
pub fn StringHashMap(comptime V: type) type {
    return HashMap([]const u8, V, StringContext, default_max_load_percentage);
}

/// Key memory is managed by the caller.  Keys and values
/// will not automatically be freed.
pub fn StringHashMapUnmanaged(comptime V: type) type {
    return HashMapUnmanaged([]const u8, V, StringContext, default_max_load_percentage);
}

pub const StringContext = struct {
    pub fn hash(self: @This(), s: []const u8) u64 {
        _ = self;
        return hashString(s);
    }
    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        return eqlString(a, b);
    }
};

pub fn eqlString(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

pub fn hashString(s: []const u8) u64 {
    return std.hash.Wyhash.hash(0, s);
}

pub const StringIndexContext = struct {
    bytes: *const std.ArrayList(u8),

    pub fn eql(_: @This(), a: u32, b: u32) bool {
        return a == b;
    }

    pub fn hash(ctx: @This(), key: u32) u64 {
        return hashString(mem.sliceTo(ctx.bytes.items[key..], 0));
    }
};

pub const StringIndexAdapter = struct {
    bytes: *const std.ArrayList(u8),

    pub fn eql(ctx: @This(), a: []const u8, b: u32) bool {
        return mem.eql(u8, a, mem.sliceTo(ctx.bytes.items[b..], 0));
    }

    pub fn hash(_: @This(), adapted_key: []const u8) u64 {
        assert(mem.findScalar(u8, adapted_key, 0) == null);
        return hashString(adapted_key);
    }
};

pub const default_max_load_percentage = 80;

/// General purpose hash table.
/// No order is guaranteed and any modification invalidates live iterators.
/// It provides fast operations (lookup, insertion, deletion) with quite high
/// load factors (up to 80% by default) for low memory usage.
/// For a hash map that can be initialized directly that does not store an Allocator
/// field, see `HashMapUnmanaged`.
/// If iterating over the table entries is a strong usecase and needs to be fast,
/// prefer the alternative `std.ArrayHashMap`.
/// Context must be a struct type with two member functions:
///   hash(self, K) u64
///   eql(self, K, K) bool
/// Adapted variants of many functions are provided.  These variants
/// take a pseudo key instead of a key.  Their context must have the functions:
///   hash(self, PseudoKey) u64
///   eql(self, PseudoKey, K) bool
pub fn HashMap(
    comptime K: type,
    comptime V: type,
    comptime Context: type,
    comptime max_load_percentage: u64,
) type {
    return struct {
        unmanaged: Unmanaged,
        allocator: Allocator,
        ctx: Context,

        /// The type of the unmanaged hash map underlying this wrapper
        pub const Unmanaged = HashMapUnmanaged(K, V, Context, max_load_percentage);
        /// An entry, containing pointers to a key and value stored in the map
        pub const Entry = Unmanaged.Entry;
        /// A copy of a key and value which are no longer in the map
        pub const KV = Unmanaged.KV;
        /// The integer type that is the result of hashing
        pub const Hash = Unmanaged.Hash;
        /// The iterator type returned by iterator()
        pub const Iterator = Unmanaged.Iterator;

        pub const KeyIterator = Unmanaged.KeyIterator;
        pub const ValueIterator = Unmanaged.ValueIterator;

        /// The integer type used to store the size of the map
        pub const Size = Unmanaged.Size;
        /// The type returned from getOrPut and variants
        pub const GetOrPutResult = Unmanaged.GetOrPutResult;

        const Self = @This();

        /// Create a managed hash map with an empty context.
        /// If the context is not zero-sized, you must use
        /// initContext(allocator, ctx) instead.
        pub fn init(allocator: Allocator) Self {
            if (@sizeOf(Context) != 0) {
                @compileError("Context must be specified! Call initContext(allocator, ctx) instead.");
            }
            return .{
                .unmanaged = .empty,
                .allocator = allocator,
                .ctx = undefined, // ctx is zero-sized so this is safe.
            };
        }

        /// Create a managed hash map with a context
        pub fn initContext(allocator: Allocator, ctx: Context) Self {
            return .{
                .unmanaged = .empty,
                .allocator = allocator,
                .ctx = ctx,
            };
        }

        /// Puts the hash map into a state where any method call that would
        /// cause an existing key or value pointer to become invalidated will
        /// instead trigger an assertion.
        ///
        /// An additional call to `lockPointers` in such state also triggers an
        /// assertion.
        ///
        /// `unlockPointers` returns the hash map to the previous state.
        pub fn lockPointers(self: *Self) void {
            self.unmanaged.lockPointers();
        }

        /// Undoes a call to `lockPointers`.
        pub fn unlockPointers(self: *Self) void {
            self.unmanaged.unlockPointers();
        }

        /// Release the backing array and invalidate this map.
        /// This does *not* deinit keys, values, or the context!
        /// If your keys or values need to be released, ensure
        /// that that is done before calling this function.
        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
            self.* = undefined;
        }

        /// Empty the map, but keep the backing allocation for future use.
        /// This does *not* free keys or values! Be sure to
        /// release them if they need deinitialization before
        /// calling this function.
        pub fn clearRetainingCapacity(self: *Self) void {
            return self.unmanaged.clearRetainingCapacity();
        }

        /// Empty the map and release the backing allocation.
        /// This does *not* free keys or values! Be sure to
        /// release them if they need deinitialization before
        /// calling this function.
        pub fn clearAndFree(self: *Self) void {
            return self.unmanaged.clearAndFree(self.allocator);
        }

        /// Return the number of items in the map.
        pub fn count(self: Self) Size {
            return self.unmanaged.count();
        }

        /// Create an iterator over the entries in the map.
        /// The iterator is invalidated if the map is modified.
        pub fn iterator(self: *const Self) Iterator {
            return self.unmanaged.iterator();
        }

        /// Create an iterator over the keys in the map.
        /// The iterator is invalidated if the map is modified.
        pub fn keyIterator(self: Self) KeyIterator {
            return self.unmanaged.keyIterator();
        }

        /// Create an iterator over the values in the map.
        /// The iterator is invalidated if the map is modified.
        pub fn valueIterator(self: Self) ValueIterator {
            return self.unmanaged.valueIterator();
        }

        /// If key exists this function cannot fail.
        /// If there is an existing item with `key`, then the result's
        /// `Entry` pointers point to it, and found_existing is true.
        /// Otherwise, puts a new item with undefined value, and
        /// the `Entry` pointers point to it. Caller should then initialize
        /// the value (but not the key).
        pub fn getOrPut(self: *Self, key: K) Allocator.Error!GetOrPutResult {
            return self.unmanaged.getOrPutContext(self.allocator, key, self.ctx);
        }

        /// If key exists this function cannot fail.
        /// If there is an existing item with `key`, then the result's
        /// `Entry` pointers point to it, and found_existing is true.
        /// Otherwise, puts a new item with undefined key and value, and
        /// the `Entry` pointers point to it. Caller must then initialize
        /// the key and value.
        pub fn getOrPutAdapted(self: *Self, key: anytype, ctx: anytype) Allocator.Error!GetOrPutResult {
            return self.unmanaged.getOrPutContextAdapted(self.allocator, key, ctx, self.ctx);
        }

        /// If there is an existing item with `key`, then the result's
        /// `Entry` pointers point to it, and found_existing is true.
        /// Otherwise, puts a new item with undefined value, and
        /// the `Entry` pointers point to it. Caller should then initialize
        /// the value (but not the key).
        /// If a new entry needs to be stored, this function asserts there
        /// is enough capacity to store it.
        pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            return self.unmanaged.getOrPutAssumeCapacityContext(key, self.ctx);
        }

        /// If there is an existing item with `key`, then the result's
        /// `Entry` pointers point to it, and found_existing is true.
        /// Otherwise, puts a new item with undefined value, and
        /// the `Entry` pointers point to it. Caller must then initialize
        /// the key and value.
        /// If a new entry needs to be stored, this function asserts there
        /// is enough capacity to store it.
        pub fn getOrPutAssumeCapacityAdapted(self: *Self, key: anytype, ctx: anytype) GetOrPutResult {
            return self.unmanaged.getOrPutAssumeCapacityAdapted(key, ctx);
        }

        pub fn getOrPutValue(self: *Self, key: K, value: V) Allocator.Error!Entry {
            return self.unmanaged.getOrPutValueContext(self.allocator, key, value, self.ctx);
        }

        /// Increases capacity, guaranteeing that insertions up until the
        /// `expected_count` will not cause an allocation, and therefore cannot fail.
        pub fn ensureTotalCapacity(self: *Self, expected_count: Size) Allocator.Error!void {
            return self.unmanaged.ensureTotalCapacityContext(self.allocator, expected_count, self.ctx);
        }

        /// Increases capacity, guaranteeing that insertions up until
        /// `additional_count` **more** items will not cause an allocation, and
        /// therefore cannot fail.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: Size) Allocator.Error!void {
            return self.unmanaged.ensureUnusedCapacityContext(self.allocator, additional_count, self.ctx);
        }

        /// Returns the number of total elements which may be present before it is
        /// no longer guaranteed that no allocations will be performed.
        pub fn capacity(self: Self) Size {
            return self.unmanaged.capacity();
        }

        /// Clobbers any existing data. To detect if a put would clobber
        /// existing data, see `getOrPut`.
        pub fn put(self: *Self, key: K, value: V) Allocator.Error!void {
            return self.unmanaged.putContext(self.allocator, key, value, self.ctx);
        }

        /// Inserts a key-value pair into the hash map, asserting that no previous
        /// entry with the same key is already present
        pub fn putNoClobber(self: *Self, key: K, value: V) Allocator.Error!void {
            return self.unmanaged.putNoClobberContext(self.allocator, key, value, self.ctx);
        }

        /// Asserts there is enough capacity to store the new key-value pair.
        /// Clobbers any existing data. To detect if a put would clobber
        /// existing data, see `getOrPutAssumeCapacity`.
        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            return self.unmanaged.putAssumeCapacityContext(key, value, self.ctx);
        }

        /// Asserts there is enough capacity to store the new key-value pair.
        /// Asserts that it does not clobber any existing data.
        /// To detect if a put would clobber existing data, see `getOrPutAssumeCapacity`.
        pub fn putAssumeCapacityNoClobber(self: *Self, key: K, value: V) void {
            return self.unmanaged.putAssumeCapacityNoClobberContext(key, value, self.ctx);
        }

        /// Inserts a new `Entry` into the hash map, returning the previous one, if any.
        pub fn fetchPut(self: *Self, key: K, value: V) Allocator.Error!?KV {
            return self.unmanaged.fetchPutContext(self.allocator, key, value, self.ctx);
        }

        /// Inserts a new `Entry` into the hash map, returning the previous one, if any.
        /// If insertion happens, asserts there is enough capacity without allocating.
        pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?KV {
            return self.unmanaged.fetchPutAssumeCapacityContext(key, value, self.ctx);
        }

        /// Removes a value from the map and returns the removed kv pair.
        pub fn fetchRemove(self: *Self, key: K) ?KV {
            return self.unmanaged.fetchRemoveContext(key, self.ctx);
        }

        pub fn fetchRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV {
            return self.unmanaged.fetchRemoveAdapted(key, ctx);
        }

        /// Finds the value associated with a key in the map
        pub fn get(self: Self, key: K) ?V {
            return self.unmanaged.getContext(key, self.ctx);
        }
        pub fn getAdapted(self: Self, key: anytype, ctx: anytype) ?V {
            return self.unmanaged.getAdapted(key, ctx);
        }

        pub fn getPtr(self: Self, key: K) ?*V {
            return self.unmanaged.getPtrContext(key, self.ctx);
        }
        pub fn getPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*V {
            return self.unmanaged.getPtrAdapted(key, ctx);
        }

        /// Finds the actual key associated with an adapted key in the map
        pub fn getKey(self: Self, key: K) ?K {
            return self.unmanaged.getKeyContext(key, self.ctx);
        }
        pub fn getKeyAdapted(self: Self, key: anytype, ctx: anytype) ?K {
            return self.unmanaged.getKeyAdapted(key, ctx);
        }

        pub fn getKeyPtr(self: Self, key: K) ?*K {
            return self.unmanaged.getKeyPtrContext(key, self.ctx);
        }
        pub fn getKeyPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*K {
            return self.unmanaged.getKeyPtrAdapted(key, ctx);
        }

        /// Finds the key and value associated with a key in the map
        pub fn getEntry(self: Self, key: K) ?Entry {
            return self.unmanaged.getEntryContext(key, self.ctx);
        }

        pub fn getEntryAdapted(self: Self, key: anytype, ctx: anytype) ?Entry {
            return self.unmanaged.getEntryAdapted(key, ctx);
        }

        /// Check if the map contains a key
        pub fn contains(self: Self, key: K) bool {
            return self.unmanaged.containsContext(key, self.ctx);
        }

        pub fn containsAdapted(self: Self, key: anytype, ctx: anytype) bool {
            return self.unmanaged.containsAdapted(key, ctx);
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the hash map, and this function returns true.  Otherwise this
        /// function returns false.
        ///
        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn remove(self: *Self, key: K) bool {
            return self.unmanaged.removeContext(key, self.ctx);
        }

        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn removeAdapted(self: *Self, key: anytype, ctx: anytype) bool {
            return self.unmanaged.removeAdapted(key, ctx);
        }

        /// Delete the entry with key pointed to by key_ptr from the hash map.
        /// key_ptr is assumed to be a valid pointer to a key that is present
        /// in the hash map.
        ///
        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn removeByPtr(self: *Self, key_ptr: *K) void {
            self.unmanaged.removeByPtr(key_ptr);
        }

        /// Creates a copy of this map, using the same allocator
        pub fn clone(self: Self) Allocator.Error!Self {
            var other = try self.unmanaged.cloneContext(self.allocator, self.ctx);
            return other.promoteContext(self.allocator, self.ctx);
        }

        /// Creates a copy of this map, using a specified allocator
        pub fn cloneWithAllocator(self: Self, new_allocator: Allocator) Allocator.Error!Self {
            var other = try self.unmanaged.cloneContext(new_allocator, self.ctx);
            return other.promoteContext(new_allocator, self.ctx);
        }

        /// Creates a copy of this map, using a specified context
        pub fn cloneWithContext(self: Self, new_ctx: anytype) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage) {
            var other = try self.unmanaged.cloneContext(self.allocator, new_ctx);
            return other.promoteContext(self.allocator, new_ctx);
        }

        /// Creates a copy of this map, using a specified allocator and context.
        pub fn cloneWithAllocatorAndContext(
            self: Self,
            new_allocator: Allocator,
            new_ctx: anytype,
        ) Allocator.Error!HashMap(K, V, @TypeOf(new_ctx), max_load_percentage) {
            var other = try self.unmanaged.cloneContext(new_allocator, new_ctx);
            return other.promoteContext(new_allocator, new_ctx);
        }

        /// Set the map to an empty state, making deinitialization a no-op, and
        /// returning a copy of the original.
        pub fn move(self: *Self) Self {
            self.unmanaged.pointer_stability.assertUnlocked();
            const result = self.*;
            self.unmanaged = .empty;
            return result;
        }

        /// Rehash the map, in-place.
        ///
        /// Over time, due to the current tombstone-based implementation, a
        /// HashMap could become fragmented due to the buildup of tombstone
        /// entries that causes a performance degradation due to excessive
        /// probing. The kind of pattern that might cause this is a long-lived
        /// HashMap with repeated inserts and deletes.
        ///
        /// After this function is called, there will be no tombstones in
        /// the HashMap, each of the entries is rehashed and any existing
        /// key/value pointers into the HashMap are invalidated.
        pub fn rehash(self: *Self) void {
            self.unmanaged.rehash(self.ctx);
        }
    };
}

pub const HashMapUnmanaged = Custom;

pub const MapSize = u32;

// Note: cap the group length at 16 bytes, values larger than that give diminishing returns
// and may end up performing *worse* because it may result in more straddling of cache line
// boundaries.
/// Length of a metadata group.
const group_len = @min(16, std.simd.suggestVectorLength(Metadata) orelse 16);

const Vec = @Vector(group_len, u8);

const uvec = @Int(.unsigned, group_len);

/// Metadata is packed in 'control words' that are byte-sized. The first bit indicates
/// whether the element at that position is a marker (empty or deleted) or a genuine element.
/// The rest of the 7 bits are a hash fragment for the element, or magic marker values.
/// The hash fragment or 'fingerprint' is used as a quick way to compare two elements
/// without doing a full key comparison.
/// One consequence of the layout is that the bit indicating the kind of element is the sign bit,
/// which we can exploit efficiently in SIMD instructions.
const Metadata = packed struct(u8) {
    // 7 bit hash fragment.
    fingerprint: u7,
    // 1 if empty, 0 if full.
    control: u1,

    const empty_data: Metadata = .{
        .control = 1,
        .fingerprint = 0,
    };

    const empty_vec: Vec = @splat(@bitCast(empty_data));

    const deleted: Metadata = .{
        .control = 1,
        .fingerprint = 0x7E,
    };

    const deleted_vec: Vec = @splat(@bitCast(deleted));

    fn make(fingerprint: u7) Metadata {
        return .{
            .control = 0,
            .fingerprint = fingerprint,
        };
    }

    fn makeVec(fingerprint: u7) Vec {
        return @splat(@bitCast(make(fingerprint)));
    }

    fn asByte(m: Metadata) u8 {
        return @bitCast(m);
    }

    fn isFull(m: Metadata) bool {
        return m.control == 0;
    }

    fn isEmpty(m: Metadata) bool {
        return m.asByte() == empty_data.asByte();
    }

    fn isDeleted(m: Metadata) bool {
        return m.asByte() == deleted.asByte();
    }
};

/// Represents a group of metadata control words. As metadata fits in only one byte,
/// we can use vectorized operations to process a bunch (`group_len`) of them in parallel.
/// This struct contains helper functions for manipulating the underlying `Vec`.
const Group = struct {
    vec: Vec,

    fn load(metadata: [*]Metadata, index: MapSize) Group {
        return .{ .vec = @bitCast(metadata[index..][0..group_len].*) };
    }
    fn store(self: Group, metadata: [*]Metadata, index: MapSize) void {
        metadata[index..][0..group_len].* = @bitCast(self.vec);
    }

    fn match(self: Group, fp: u7) Match {
        return Match.init(self.vec == Metadata.makeVec(fp));
    }

    fn matchEmpty(self: Group) Match {
        return Match.init(self.vec == Metadata.empty_vec);
    }

    fn matchEmptyOrDeleted(self: Group) Match {
        const signed: @Vector(group_len, i8) = @bitCast(self.vec);

        // Note: we can do this since the control bit is the sign bit.
        return Match.init(signed < @as(@Vector(group_len, i8), @splat(0)));
    }

    fn convertDeletedToEmptyAndFullToDeleted(self: Group) Group {
        // Keep every control bit only:
        // full:     0xxxxxxx & 10000000 = 00000000
        // empty:    10000000 & 10000000 = 10000000
        // deleted:  11111110 & 10000000 = 10000000
        // Now, each byte of x is either 0x00 (full) or 0x80 (special)
        const x = self.vec & @as(Vec, @splat(0x80));

        // full (0x00):
        // ~x             = 0xFF
        // x >> 7         = 0x00
        // ~x + (x >> 7)  = 0xFF
        // special (0x80):
        // ~x             = 0x7F
        // x >> 7         = 0x01
        // ~x + (x >> 7)  = 0x80
        //
        // Then, finally mask off the low bit with & 0xFE:
        // 0xFF & 0xFE = 0xFE (deleted)
        // 0x80 & 0xFE = 0x80 (empty)
        const shift: @Vector(group_len, u3) = @splat(7);
        return .{ .vec = (~x +% (x >> shift)) & @as(Vec, @splat(0xFE)) };
    }
};

const SplitHash = packed struct(u64) {
    h2: u7,
    h1: u57,
};

/// Represents a conditional test over `group_len` bits. The bits indicate whether the test
/// was true or false at their respective index.
const Match = struct {
    bits: uvec,

    const MatchIter = struct {
        mask: uvec,

        fn next(self: *MatchIter) ?MapSize {
            if (self.mask == 0) return null;
            const idx = @ctz(self.mask);
            self.mask &= (self.mask - 1);
            return idx;
        }
    };

    fn init(vec: @Vector(group_len, bool)) Match {
        return .{
            .bits = @bitCast(vec),
        };
    }

    /// Return an iterator walking over every set bit in the match.
    fn iter(self: *const Match) MatchIter {
        return .{
            .mask = self.bits,
        };
    }

    /// Return the first bit that is set.
    fn firstSet(self: *const Match) ?MapSize {
        if (self.bits == 0) return null;
        return @ctz(self.bits);
    }
    /// Return whether any match was successful.
    inline fn any(self: Match) bool {
        return self.bits != 0;
    }
};

/// Represents a probing state.
/// We make use of quadratic probing with triangular numbers, i.e we follow the sequence
/// h(k), h(k)+1, h(k)+3, h(k)+6, ...; Since the table size is a power of two, we visit
/// every slot of the table exactly once, guaranteeing that we'll eventually find an empty
/// slot.
const Probe = struct {
    index: MapSize,
    stride: MapSize,
    cap_mask: MapSize,

    pub fn init(index: MapSize, cap_mask: MapSize) Probe {
        return .{
            .index = index,
            .stride = 0,
            .cap_mask = cap_mask,
        };
    }

    fn next(self: *Probe) void {
        self.stride += group_len;
        self.index = (self.index + self.stride) & self.cap_mask;
    }

    fn slot(self: Probe, offset: MapSize) MapSize {
        return (self.index + offset) & self.cap_mask;
    }
    fn group(self: Probe, metadata: [*]Metadata) Group {
        return Group.load(metadata, self.index);
    }
};

/// A HashMap based on open-addressing and quadratic probing, based on Google's Swiss Table design.
/// No order is guaranteed and any modification invalidates live iterators.
/// It achieves good performance with quite high load factors (by default,
/// grow is triggered at 88% full) and only one byte of overhead per element.
pub fn Custom(
    comptime K: type,
    comptime V: type,
    comptime Context: type,
    comptime max_load_percentage: u8,
) type {
    // Brief Overview:
    // The Swiss Table design relies on SIMD operations for very fast probing; logically, the
    // table is organized into groups of `group_len` slots, where `group_len` is the processor's
    // SIMD size (in reality, we cap it to 16 bytes, see comment above).
    //
    // At any given point, there are N slots, where N is a power-of-two capacity, and N+group_len-1
    // bytes of metadata. The [N,N+group_len-1] range is mirrored metadata from the low `group_len`
    // slots of the table as to make SIMD operation more efficient (i.e we always have `group_len`
    // valid bytes to operate on.)
    //
    // Each metadata byte has the following layout: |C|HHHHHHH|, where C is a 'control' bit,
    // denoting the entry's type, and H is a 7-bit hash fragment. An entry is always either
    // 'full' (c=0), 'empty' (c=1, H=0) or 'deleted' (c=1, H=all ones).
    //
    // Probing is done by taking the top 57 bits of the hash and using them to select a
    // group. Then, SIMD is leveraged to compare all the bytes of the group simultaneously for
    // a match in the low 7 bits of the hash. If no suitable member is found, probing is done
    // quadratically using triangular numbers, ensuring every entry is walked exactly once.
    //
    // Resources:
    // - https://faultlore.com/blah/hashbrown-tldr/
    // - https://abseil.io/about/design/swisstables
    // - https://github.com/cockroachdb/swiss/blob/main/map.go
    if (max_load_percentage <= 0 or max_load_percentage >= 100)
        @compileError("max_load_percentage must be between 0 and 100.");
    return struct {
        const Self = @This();

        table: ?[*]u8 = null,

        /// Current number of elements in the hashmap.
        size: Size = 0,
        /// Allocated capacity.
        capacity_: Size = 0,

        // Having a countdown to grow reduces the number of instructions to
        // execute when determining if the hashmap has enough capacity already.
        /// Number of available slots before a grow is needed to satisfy the
        /// `max_load_percentage`.
        available: Size = 0,

        /// Used to detect memory safety violations.
        pointer_stability: std.debug.SafetyLock = .{},

        /// Capacity of the first grow when bootstrapping the hashmap.
        const minimal_capacity = 8;

        comptime {
            std.debug.assert(capacityToGrowth(minimal_capacity) < minimal_capacity);
            std.debug.assert(capacityToGrowth(minimal_capacity) >= 1);
        }

        /// A map containing no keys or values.
        pub const empty: Self = .{
            .table = null,
            .size = 0,
            .capacity_ = 0,
            .available = 0,
        };

        // u64 hashes guarantee us that the fingerprint bits will never be used
        // to compute the index of a slot, maximizing the use of entropy.
        pub const Hash = u64;

        // This hashmap is specially designed for sizes that fit in a u32.
        pub const Size = MapSize;

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const KV = struct {
            key: K,
            value: V,
        };

        /// Number of metadata bytes.
        /// There is one byte per slot, plus a mirrored section of `group_len-1` bytes that mirrors
        /// the first indicies of the array. This is used to make the code simpler and assume we
        /// can always do a SIMD operation without running off into KV storage.
        /// The table ends up in one contiguous allocation like so:
        /// ----------------------------
        /// |metadata|mirror padding|KV|
        /// ---------------------------
        fn metadataLen(cap: Size) Size {
            return cap + group_len - 1;
        }

        /// Offset of the start of KV entries in the contiguous allocation.
        /// This is aligned with KV.
        fn entriesOffset(cap: Size) Size {
            return std.mem.alignForward(Size, metadataLen(cap), @alignOf(KV));
        }

        /// Total allocated length of the table.
        fn tableLen(cap: Size) Size {
            return entriesOffset(cap) + @sizeOf(KV) * cap;
        }

        pub const Iterator = struct {
            hm: *const Self,
            index: Size = 0,

            pub fn next(it: *Iterator) ?Entry {
                std.debug.assert(it.index <= it.hm.capacity_);
                if (it.hm.size == 0) return null;

                const cap = it.hm.capacity_;
                const entries = it.hm.entriesPtr();
                const metadata = it.hm.metadataPtr();

                while (it.index < cap) : (it.index += 1) {
                    if (metadata[it.index].isFull()) {
                        const entry = &entries[it.index];
                        it.index += 1;
                        return .{ .key_ptr = &entry.key, .value_ptr = &entry.value };
                    }
                }

                return null;
            }
        };

        pub const KeyIterator = FieldIterator(K, "key");

        pub const ValueIterator = FieldIterator(V, "value");

        fn FieldIterator(comptime T: type, comptime field: []const u8) type {
            return struct {
                len: usize,
                metadata: [*]const Metadata,
                items: [*]KV,

                pub fn next(self: *@This()) ?*T {
                    while (self.len > 0) {
                        self.len -= 1;
                        const used = self.metadata[0].isFull();
                        const item = &@field(self.items[0], field);
                        self.metadata += 1;
                        self.items += 1;
                        if (used) return item;
                    }
                    return null;
                }
            };
        }

        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        pub const Managed = HashMap(K, V, Context, max_load_percentage);

        pub fn promote(self: Self, allocator: Allocator) Managed {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call promoteContext instead.");
            return promoteContext(self, allocator, undefined);
        }

        pub fn promoteContext(self: Self, allocator: Allocator, ctx: Context) Managed {
            return .{
                .unmanaged = self,
                .allocator = allocator,
                .ctx = ctx,
            };
        }

        /// Puts the hash map into a state where any method call that would
        /// cause an existing key or value pointer to become invalidated will
        /// instead trigger an assertion.
        ///
        /// An additional call to `lockPointers` in such state also triggers an
        /// assertion.
        ///
        /// `unlockPointers` returns the hash map to the previous state.
        pub fn lockPointers(self: *Self) void {
            self.pointer_stability.lock();
        }

        /// Undoes a call to `lockPointers`.
        pub fn unlockPointers(self: *Self) void {
            self.pointer_stability.unlock();
        }

        /// The number of live elements `cap` slots may hold before a grow is
        /// required.
        fn capacityToGrowth(cap: Size) Size {
            return (cap * max_load_percentage) / 100;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.pointer_stability.assertUnlocked();
            if (self.table) |table| {
                allocator.free(@as([*]align(@alignOf(KV)) u8, @alignCast(table))[0..tableLen(self.capacity_)]);
            }
            self.* = undefined;
        }

        fn capacityForSize(size: Size) Size {
            const min_cap = (@as(u64, size) * 100) / max_load_percentage + 1;
            const new_cap = std.math.ceilPowerOfTwo(u64, min_cap) catch unreachable;
            return @max(minimal_capacity, @as(Size, @intCast(new_cap)));
        }

        pub fn ensureTotalCapacity(self: *Self, allocator: Allocator, new_size: Size) Allocator.Error!void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call ensureTotalCapacityContext instead.");
            return ensureTotalCapacityContext(self, allocator, new_size, undefined);
        }

        pub fn ensureTotalCapacityContext(self: *Self, allocator: Allocator, new_size: Size, ctx: Context) Allocator.Error!void {
            self.pointer_stability.lock();
            defer self.pointer_stability.unlock();
            if (new_size > self.size)
                try self.growIfNeeded(allocator, new_size - self.size, ctx);
        }

        pub fn ensureUnusedCapacity(self: *Self, allocator: Allocator, additional_size: Size) Allocator.Error!void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call ensureUnusedCapacityContext instead.");
            return ensureUnusedCapacityContext(self, allocator, additional_size, undefined);
        }

        pub fn ensureUnusedCapacityContext(self: *Self, allocator: Allocator, additional_size: Size, ctx: Context) Allocator.Error!void {
            return ensureTotalCapacityContext(self, allocator, self.count() + additional_size, ctx);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.pointer_stability.lock();
            defer self.pointer_stability.unlock();
            if (self.table) |_| {
                const metadata = self.metadataPtr()[0..metadataLen(self.capacity_)];
                @memset(metadata, Metadata.empty_data);

                self.size = 0;
                self.available = capacityToGrowth(self.capacity_);
            }
        }

        pub fn clearAndFree(self: *Self, allocator: Allocator) void {
            self.pointer_stability.lock();
            defer self.pointer_stability.unlock();
            if (self.table) |table| {
                allocator.free(@as([*]align(@alignOf(KV)) u8, @alignCast(table))[0..tableLen(self.capacity_)]);
            }
            self.table = null;
            self.capacity_ = 0;
            self.size = 0;
            self.available = 0;
        }

        pub fn count(self: Self) Size {
            return self.size;
        }

        fn metadataPtr(self: *const Self) [*]Metadata {
            return @ptrCast(&self.table.?[0]);
        }

        fn entriesPtr(self: *const Self) [*]KV {
            return @ptrCast(@alignCast(&self.table.?[entriesOffset(self.capacity_)]));
        }

        pub fn capacity(self: Self) Size {
            return self.capacity_;
        }

        pub fn iterator(self: *const Self) Iterator {
            return .{ .hm = self };
        }

        pub fn keyIterator(self: Self) KeyIterator {
            if (self.table) |_| {
                return .{
                    .len = self.capacity_,
                    .metadata = self.metadataPtr(),
                    .items = self.entriesPtr(),
                };
            } else {
                return .{ .len = 0, .metadata = undefined, .items = undefined };
            }
        }

        pub fn valueIterator(self: Self) ValueIterator {
            if (self.table) |_| {
                return .{
                    .len = self.capacity_,
                    .metadata = self.metadataPtr(),
                    .items = self.entriesPtr(),
                };
            } else {
                return .{ .len = 0, .metadata = undefined, .items = undefined };
            }
        }

        /// Insert an entry in the map. Assumes it is not already present.
        pub fn putNoClobber(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call putNoClobberContext instead.");
            return self.putNoClobberContext(allocator, key, value, undefined);
        }

        pub fn putNoClobberContext(self: *Self, allocator: Allocator, key: K, value: V, ctx: Context) Allocator.Error!void {
            {
                self.pointer_stability.lock();
                defer self.pointer_stability.unlock();
                try self.growIfNeeded(allocator, 1, ctx);
            }
            self.putAssumeCapacityNoClobberContext(key, value, ctx);
        }

        /// Asserts there is enough capacity to store the new key-value pair.
        /// Clobbers any existing data. To detect if a put would clobber
        /// existing data, see `getOrPutAssumeCapacity`.
        pub fn putAssumeCapacity(self: *Self, key: K, value: V) void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call putAssumeCapacityContext instead.");
            return self.putAssumeCapacityContext(key, value, undefined);
        }

        pub fn putAssumeCapacityContext(self: *Self, key: K, value: V, ctx: Context) void {
            const gop = self.getOrPutAssumeCapacityContext(key, ctx);
            gop.value_ptr.* = value;
        }

        /// Insert an entry in the map. Assumes it is not already present,
        /// and that no allocation is needed.
        pub fn putAssumeCapacityNoClobber(self: *Self, key: K, value: V) void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call putAssumeCapacityNoClobberContext instead.");
            return self.putAssumeCapacityNoClobberContext(key, value, undefined);
        }

        pub fn putAssumeCapacityNoClobberContext(self: *Self, key: K, value: V, ctx: Context) void {
            const result = self.getOrPutAssumeCapacityContext(key, ctx);
            std.debug.assert(!result.found_existing);
            result.value_ptr.* = value;
        }

        /// Inserts a new `Entry` into the hash map, returning the previous one, if any.
        pub fn fetchPut(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!?KV {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call fetchPutContext instead.");
            return self.fetchPutContext(allocator, key, value, undefined);
        }

        pub fn fetchPutContext(self: *Self, allocator: Allocator, key: K, value: V, ctx: Context) Allocator.Error!?KV {
            const gop = try self.getOrPutContext(allocator, key, ctx);
            var result: ?KV = null;
            if (gop.found_existing) {
                result = KV{
                    .key = gop.key_ptr.*,
                    .value = gop.value_ptr.*,
                };
            }
            gop.value_ptr.* = value;
            return result;
        }

        /// Inserts a new `Entry` into the hash map, returning the previous one, if any.
        /// If insertion happens, asserts there is enough capacity without allocating.
        pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?KV {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call fetchPutAssumeCapacityContext instead.");
            return self.fetchPutAssumeCapacityContext(key, value, undefined);
        }

        pub fn fetchPutAssumeCapacityContext(self: *Self, key: K, value: V, ctx: Context) ?KV {
            const gop = self.getOrPutAssumeCapacityContext(key, ctx);
            var result: ?KV = null;
            if (gop.found_existing) {
                result = KV{
                    .key = gop.key_ptr.*,
                    .value = gop.value_ptr.*,
                };
            }
            gop.value_ptr.* = value;
            return result;
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the hash map, and then returned from this function.
        pub fn fetchRemove(self: *Self, key: K) ?KV {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call fetchRemoveContext instead.");
            return self.fetchRemoveContext(key, undefined);
        }

        pub fn fetchRemoveContext(self: *Self, key: K, ctx: Context) ?KV {
            return self.fetchRemoveAdapted(key, ctx);
        }

        pub fn fetchRemoveAdapted(self: *Self, key: anytype, ctx: anytype) ?KV {
            const idx = self.getIndex(key, ctx) orelse return null;
            const result = self.entriesPtr()[idx];
            self.removeByIndex(idx);
            return result;
        }

        fn getIndex(self: Self, key: anytype, ctx: anytype) ?Size {
            if (self.size == 0) {
                @branchHint(.cold);
                return null;
            }
            const hash: Hash = ctx.hash(key);
            const split: SplitHash = @bitCast(hash);
            return switch (self.findSlot(key, split, ctx, .read)) {
                .found => |s| s,
                .vacant => null,
            };
        }

        pub fn getEntry(self: Self, key: K) ?Entry {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getEntryContext instead.");
            return self.getEntryContext(key, undefined);
        }

        pub fn getEntryContext(self: Self, key: K, ctx: Context) ?Entry {
            return self.getEntryAdapted(key, ctx);
        }

        pub fn getEntryAdapted(self: Self, key: anytype, ctx: anytype) ?Entry {
            const idx = self.getIndex(key, ctx) orelse return null;
            const entry = &self.entriesPtr()[idx];
            return .{ .key_ptr = &entry.key, .value_ptr = &entry.value };
        }

        /// Insert an entry if the associated key is not already present, otherwise update preexisting value.
        pub fn put(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call putContext instead.");
            return self.putContext(allocator, key, value, undefined);
        }

        pub fn putContext(self: *Self, allocator: Allocator, key: K, value: V, ctx: Context) Allocator.Error!void {
            const result = try self.getOrPutContext(allocator, key, ctx);
            result.value_ptr.* = value;
        }

        /// Get an optional pointer to the actual key associated with adapted key, if present.
        pub fn getKeyPtr(self: Self, key: K) ?*K {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getKeyPtrContext instead.");
            return self.getKeyPtrContext(key, undefined);
        }

        pub fn getKeyPtrContext(self: Self, key: K, ctx: Context) ?*K {
            return self.getKeyPtrAdapted(key, ctx);
        }

        pub fn getKeyPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*K {
            const idx = self.getIndex(key, ctx) orelse return null;
            return &self.entriesPtr()[idx].key;
        }

        /// Get a copy of the actual key associated with adapted key, if present.
        pub fn getKey(self: Self, key: K) ?K {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getKeyContext instead.");
            return self.getKeyContext(key, undefined);
        }

        pub fn getKeyContext(self: Self, key: K, ctx: Context) ?K {
            return self.getKeyAdapted(key, ctx);
        }

        pub fn getKeyAdapted(self: Self, key: anytype, ctx: anytype) ?K {
            const idx = self.getIndex(key, ctx) orelse return null;
            return self.entriesPtr()[idx].key;
        }

        /// Get an optional pointer to the value associated with key, if present.
        pub fn getPtr(self: Self, key: K) ?*V {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getPtrContext instead.");
            return self.getPtrContext(key, undefined);
        }

        pub fn getPtrContext(self: Self, key: K, ctx: Context) ?*V {
            return self.getPtrAdapted(key, ctx);
        }

        pub fn getPtrAdapted(self: Self, key: anytype, ctx: anytype) ?*V {
            const idx = self.getIndex(key, ctx) orelse return null;
            return &self.entriesPtr()[idx].value;
        }

        /// Get a copy of the value associated with key, if present.
        pub fn get(self: Self, key: K) ?V {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getContext instead.");
            return self.getContext(key, undefined);
        }

        pub fn getContext(self: Self, key: K, ctx: Context) ?V {
            return self.getAdapted(key, ctx);
        }

        pub fn getAdapted(self: Self, key: anytype, ctx: anytype) ?V {
            const idx = self.getIndex(key, ctx) orelse return null;
            return self.entriesPtr()[idx].value;
        }

        pub fn getOrPut(self: *Self, allocator: Allocator, key: K) Allocator.Error!GetOrPutResult {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getOrPutContext instead.");
            return self.getOrPutContext(allocator, key, undefined);
        }

        pub fn getOrPutContext(self: *Self, allocator: Allocator, key: K, ctx: Context) Allocator.Error!GetOrPutResult {
            const gop = try self.getOrPutContextAdapted(allocator, key, ctx, ctx);
            if (!gop.found_existing) {
                gop.key_ptr.* = key;
            }
            return gop;
        }

        pub fn getOrPutAdapted(self: *Self, allocator: Allocator, key: anytype, key_ctx: anytype) Allocator.Error!GetOrPutResult {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getOrPutContextAdapted instead.");
            return self.getOrPutContextAdapted(allocator, key, key_ctx, undefined);
        }

        pub fn getOrPutContextAdapted(self: *Self, allocator: Allocator, key: anytype, key_ctx: anytype, ctx: Context) Allocator.Error!GetOrPutResult {
            if (self.table != null) {
                const hash: Hash = key_ctx.hash(key);
                const split: SplitHash = @bitCast(hash);
                const entries = self.entriesPtr();
                const metadata = self.metadataPtr();

                switch (self.findSlot(key, split, key_ctx, .write)) {
                    .found => |s| return .{
                        .key_ptr = &entries[s].key,
                        .value_ptr = &entries[s].value,
                        .found_existing = true,
                    },
                    .vacant => |s| if (self.available != 0 or !metadata[s].isEmpty())
                        return self.claimSlot(metadata, entries, s, split.h2),
                }
            }

            {
                self.pointer_stability.lock();
                defer self.pointer_stability.unlock();
                self.growIfNeeded(allocator, 1, ctx) catch |err| {
                    const idx = self.getIndex(key, key_ctx) orelse return err;
                    const entry = &self.entriesPtr()[idx];
                    return .{
                        .key_ptr = &entry.key,
                        .value_ptr = &entry.value,
                        .found_existing = true,
                    };
                };
            }
            return self.getOrPutAssumeCapacityAdapted(key, key_ctx);
        }

        pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getOrPutAssumeCapacityContext instead.");
            return self.getOrPutAssumeCapacityContext(key, undefined);
        }

        pub fn getOrPutAssumeCapacityContext(self: *Self, key: K, ctx: Context) GetOrPutResult {
            const result = self.getOrPutAssumeCapacityAdapted(key, ctx);
            if (!result.found_existing) {
                result.key_ptr.* = key;
            }
            return result;
        }

        pub fn getOrPutAssumeCapacityAdapted(self: *Self, key: anytype, ctx: anytype) GetOrPutResult {
            std.debug.assert(self.table != null);

            const hash: Hash = ctx.hash(key);
            const split: SplitHash = @bitCast(hash);
            const entries = self.entriesPtr();
            const metadata = self.metadataPtr();

            return switch (self.findSlot(key, split, ctx, .write)) {
                .found => |s| .{
                    .key_ptr = &entries[s].key,
                    .value_ptr = &entries[s].value,
                    .found_existing = true,
                },
                .vacant => |s| self.claimSlot(metadata, entries, s, split.h2),
            };
        }

        fn claimSlot(self: *Self, metadata: [*]Metadata, entries: [*]KV, slot: Size, fp: u7) GetOrPutResult {
            if (metadata[slot].isEmpty()) {
                std.debug.assert(self.available > 0);
                self.available -= 1;
            }
            self.setMetadata(metadata, slot, Metadata.make(fp));
            self.size += 1;

            return .{
                .key_ptr = &entries[slot].key,
                .value_ptr = &entries[slot].value,
                .found_existing = false,
            };
        }

        pub fn getOrPutValue(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!Entry {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call getOrPutValueContext instead.");
            return self.getOrPutValueContext(allocator, key, value, undefined);
        }

        pub fn getOrPutValueContext(self: *Self, allocator: Allocator, key: K, value: V, ctx: Context) Allocator.Error!Entry {
            const res = try self.getOrPutContext(allocator, key, ctx);
            if (!res.found_existing) res.value_ptr.* = value;
            return .{ .key_ptr = res.key_ptr, .value_ptr = res.value_ptr };
        }

        /// Return true if there is a value associated with key in the map.
        pub fn contains(self: Self, key: K) bool {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call containsContext instead.");
            return self.containsContext(key, undefined);
        }

        pub fn containsContext(self: Self, key: K, ctx: Context) bool {
            return self.containsAdapted(key, ctx);
        }

        pub fn containsAdapted(self: Self, key: anytype, ctx: anytype) bool {
            return self.getIndex(key, ctx) != null;
        }

        fn removeByIndex(self: *Self, idx: Size) void {
            const metadata = self.metadataPtr();
            if (self.canMarkEmpty(idx)) {
                self.setMetadata(metadata, idx, Metadata.empty_data);
                self.available += 1;
            } else {
                self.setMetadata(metadata, idx, Metadata.deleted);
            }
            self.entriesPtr()[idx] = undefined;
            self.size -= 1;
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the hash map, and this function returns true.  Otherwise this
        /// function returns false.
        ///
        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn remove(self: *Self, key: K) bool {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call removeContext instead.");
            return self.removeContext(key, undefined);
        }

        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn removeContext(self: *Self, key: K, ctx: Context) bool {
            return self.removeAdapted(key, ctx);
        }

        /// TODO: answer the question in these doc comments, does this
        /// increase the unused capacity by one?
        pub fn removeAdapted(self: *Self, key: anytype, ctx: anytype) bool {
            if (self.getIndex(key, ctx)) |idx| {
                self.removeByIndex(idx);
                return true;
            }

            return false;
        }

        pub fn removeByPtr(self: *Self, key_ptr: *K) void {
            const idx = if (@sizeOf(KV) > 0)
                (@intFromPtr(key_ptr) - @intFromPtr(self.entriesPtr())) / @sizeOf(KV)
            else
                0;
            self.removeByIndex(@truncate(idx));
        }

        fn setMetadata(self: *Self, metadata: [*]Metadata, index: Size, value: Metadata) void {
            setMetadataWith(metadata, self.capacity_ - 1, index, value);
        }

        fn setMetadataWith(metadata: [*]Metadata, cap_mask: Size, index: Size, value: Metadata) void {
            const cloned = group_len - 1;
            metadata[index] = value;
            // Put cloned metadata for the cloned slots at the end of the array.
            metadata[((index -% cloned) & cap_mask) + cloned] = value;
        }

        /// Whether the tombstones in the table can be reclaimed in place
        /// instead of doubling.
        fn shouldRehashInPlace(self: *const Self) bool {
            return self.capacity_ > group_len and
                self.size * 8 <= capacityToGrowth(self.capacity_) * 7;
        }

        /// Make room for `additional` more live elements, if needed.
        fn growIfNeeded(self: *Self, allocator: Allocator, additional: Size, ctx: Context) Allocator.Error!void {
            if (additional <= self.available) return;

            const needed = self.size + additional;

            if (needed <= capacityToGrowth(self.capacity_) and self.shouldRehashInPlace()) {
                // Try to rehash in place first.
                self.rehash(ctx);
            } else {
                try self.grow(allocator, capacityForSize(needed), ctx);
            }
        }

        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Self {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call cloneContext instead.");
            return self.cloneContext(allocator, @as(Context, undefined));
        }

        pub fn cloneContext(self: Self, allocator: Allocator, new_ctx: anytype) Allocator.Error!Custom(K, V, @TypeOf(new_ctx), max_load_percentage) {
            var other: Custom(K, V, @TypeOf(new_ctx), max_load_percentage) = .empty;
            if (self.size == 0) return other;

            try other.ensureTotalCapacityContext(allocator, self.size, new_ctx);
            errdefer other.deinit(allocator);

            var it = self.iterator();
            while (it.next()) |entry|
                other.putAssumeCapacityNoClobberContext(entry.key_ptr.*, entry.value_ptr.*, new_ctx);

            return other;
        }

        /// Set the map to an empty state, making deinitialization a no-op, and
        /// returning a copy of the original.
        pub fn move(self: *Self) Self {
            self.pointer_stability.assertUnlocked();
            const result = self.*;
            self.* = .empty;
            return result;
        }

        pub fn rehash(self: *Self, ctx: anytype) void {
            const cap = self.capacity_;
            const cap_mask = cap - 1;
            const cloned = group_len - 1;
            const metadata = self.metadataPtr();
            const entries = self.entriesPtr();

            var i: Size = 0;

            // First, convert all deleted entries to empty, and all full entries to deleted.
            while (i < cap) : (i += group_len) {
                Group.load(metadata, i)
                    .convertDeletedToEmptyAndFullToDeleted()
                    .store(metadata, i);
            }

            @memcpy(metadata[cap..][0..cloned], metadata[0..cloned]);

            i = 0;

            // Then, we need to go through every non-finalized entry and process it according
            // to its state.
            while (i < cap) {
                if (!metadata[i].isDeleted()) {
                    i += 1;
                    continue;
                }

                const split: SplitHash = @bitCast(ctx.hash(entries[i].key));
                const start = split.h1 & cap_mask;

                // Find the first non-processed slot.
                const target = findFirstNonFull(metadata, @truncate(start), cap_mask);

                if (probeGroup(cap_mask, @truncate(start), i) == probeGroup(cap_mask, @truncate(start), target)) {
                    @branchHint(.likely);

                    // Already in the right group.
                    // Position within the group doesn't affect lookup cost, so leave it.
                    self.setMetadata(metadata, i, Metadata.make(split.h2));
                    i += 1;
                    continue;
                }

                const target_was_empty = metadata[target].isEmpty();
                self.setMetadata(metadata, target, Metadata.make(split.h2));

                if (target_was_empty) {
                    // Target slot is empty, claim it and set our previous slot as empty.
                    entries[target] = entries[i];
                    self.setMetadata(metadata, i, Metadata.empty_data);
                    i += 1;
                } else {
                    // Target slot is deleted, this means it holds an unplaced element we haven't
                    // got to yet, swap positions and don't increment i so that the next iteration
                    // can deal with it.
                    std.mem.swap(KV, &entries[i], &entries[target]);
                }
            }

            self.available = capacityToGrowth(cap) - self.size;
        }

        /// Grow the table to the desired `new_cap`.
        noinline fn grow(self: *Self, allocator: Allocator, new_cap: Size, ctx: Context) !void {
            const cap = self.capacity_;
            const prev_size = tableLen(cap);

            const new_mask = new_cap - 1;
            const new_table = (try allocator.alignedAlloc(
                u8,
                .fromByteUnits(@alignOf(KV)),
                tableLen(new_cap),
            )).ptr;

            const nentries: [*]KV = @ptrCast(@alignCast(&new_table[entriesOffset(new_cap)]));
            const nmetadata: [*]Metadata = @ptrCast(&new_table[0]);

            @memset(nmetadata[0..metadataLen(new_cap)], Metadata.empty_data);

            if (self.table == null) {
                @branchHint(.unlikely);
                self.table = new_table;
                self.capacity_ = new_cap;
                self.available = capacityToGrowth(new_cap) - self.size;
                return;
            }

            const metadata = self.metadataPtr();
            const entries = self.entriesPtr();

            // Re-hash and re-insert all elements.
            for (metadata[0..cap], 0..) |m, i| {
                if (!m.isFull()) continue;

                const entry = entries[i];
                const split: SplitHash = @bitCast(ctx.hash(entry.key));
                const slot = findFirstNonFull(nmetadata, @truncate(split.h1 & new_mask), new_mask);

                setMetadataWith(nmetadata, new_mask, slot, Metadata.make(split.h2));
                nentries[slot] = entry;
            }

            allocator.free(@as([*]align(@alignOf(KV)) u8, @alignCast(self.table.?))[0..prev_size]);
            self.table = new_table;
            self.capacity_ = new_cap;
            self.available = capacityToGrowth(new_cap) - self.size;
        }

        fn probeGroup(cap_mask: Size, start: Size, pos: Size) Size {
            return ((pos -% start) & cap_mask) / group_len;
        }

        /// empty but mask back onto real slots, so a match there can point to an
        /// occupied slot. Rescan from 0, where the load factor guarantees a
        /// vacancy before those trailing bytes.
        fn fixVacant(metadata: [*]Metadata, slot: Size) Size {
            if (metadata[slot].isFull()) {
                @branchHint(.unlikely);
                return Group.load(metadata, 0).matchEmptyOrDeleted().firstSet().?;
            }
            return slot;
        }

        fn findFirstNonFull(metadata: [*]Metadata, start: Size, cap_mask: Size) Size {
            var probe = Probe.init(start, cap_mask);
            while (true) {
                if (probe.group(metadata).matchEmptyOrDeleted().firstSet()) |bit|
                    return fixVacant(metadata, probe.slot(bit));
                probe.next();
            }
        }

        const Search = union(enum) {
            found: Size,
            vacant: Size,
        };

        /// Find the slot mapping to `key`, returns `vacant` if the slot is empty, or `found` if
        /// it exists already.
        fn findSlot(self: *const Self, key: anytype, split: SplitHash, ctx: anytype, comptime rw: std.builtin.PrefetchOptions.Rw) Search {
            const cap_mask = self.capacity_ - 1;
            var probe = Probe.init(@truncate(split.h1 & cap_mask), cap_mask);
            var vacant: ?Size = null;
            const entries = self.entriesPtr();
            const metadata = self.metadataPtr();

            while (true) {
                @prefetch(&entries[probe.index], .{ .rw = rw, .locality = 3, .cache = .data });
                const g = probe.group(metadata);

                var iter = g.match(split.h2).iter();
                while (iter.next()) |idx| {
                    const s = probe.slot(idx);
                    if (ctx.eql(key, entries[s].key)) return .{ .found = s };
                }

                const special = g.matchEmptyOrDeleted();
                if (special.any()) {
                    if (vacant == null) vacant = probe.slot(special.firstSet().?);
                    if (g.matchEmpty().any()) return .{ .vacant = fixVacant(metadata, vacant.?) };
                }

                probe.next();
            }
        }

        /// Return whether `slot` can be marked empty after a deletion.
        fn canMarkEmpty(self: *const Self, slot: Size) bool {
            // Safe to mark empty only if every window covering `slot` already contains an
            // empty, since probing stops in those windows regardless. That holds exactly
            // when the run of non-empty (full or deleted) slots around `slot` is shorter
            // than a group, which is what @clz and @ctz count.
            const cap_mask = self.capacity_ - 1;
            const metadata = self.metadataPtr();
            const before = Group.load(metadata, (slot -% group_len) & cap_mask).matchEmpty().bits;
            const after = Group.load(metadata, slot).matchEmpty().bits;
            return before != 0 and after != 0 and @clz(before) + @ctz(after) < group_len;
        }
    };
}

const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "basic usage" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    const count = 5;
    var i: u32 = 0;
    var total: u32 = 0;
    while (i < count) : (i += 1) {
        try map.put(i, i);
        total += i;
    }

    var sum: u32 = 0;
    var it = map.iterator();
    while (it.next()) |kv| {
        sum += kv.key_ptr.*;
    }
    try expectEqual(total, sum);

    i = 0;
    sum = 0;
    while (i < count) : (i += 1) {
        try expectEqual(i, map.get(i).?);
        sum += map.get(i).?;
    }
    try expectEqual(total, sum);
}

test "ensureTotalCapacity" {
    var map = AutoHashMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    try map.ensureTotalCapacity(20);
    const initial_capacity = map.capacity();
    try testing.expect(initial_capacity >= 20);
    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        try testing.expect(map.fetchPutAssumeCapacity(i, i + 10) == null);
    }
    // shouldn't resize from putAssumeCapacity
    try testing.expect(initial_capacity == map.capacity());
}

test "ensureUnusedCapacity with tombstones" {
    var map = AutoHashMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try map.ensureUnusedCapacity(1);
        map.putAssumeCapacity(i, i);
        _ = map.remove(i);
    }
}

test "clearRetainingCapacity" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    map.clearRetainingCapacity();

    try map.put(1, 1);
    try expectEqual(map.get(1).?, 1);
    try expectEqual(map.count(), 1);

    map.clearRetainingCapacity();
    map.putAssumeCapacity(1, 1);
    try expectEqual(map.get(1).?, 1);
    try expectEqual(map.count(), 1);

    const cap = map.capacity();
    try expect(cap > 0);

    map.clearRetainingCapacity();
    map.clearRetainingCapacity();
    try expectEqual(map.count(), 0);
    try expectEqual(map.capacity(), cap);
    try expect(!map.contains(1));
}

test "grow" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    const growTo = 12456;

    var i: u32 = 0;
    while (i < growTo) : (i += 1) {
        try map.put(i, i);
    }
    try expectEqual(map.count(), growTo);

    i = 0;
    var it = map.iterator();
    while (it.next()) |kv| {
        try expectEqual(kv.key_ptr.*, kv.value_ptr.*);
        i += 1;
    }
    try expectEqual(i, growTo);

    i = 0;
    while (i < growTo) : (i += 1) {
        try expectEqual(map.get(i).?, i);
    }
}

test "clone" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var a = try map.clone();
    defer a.deinit();

    try expectEqual(a.count(), 0);

    try a.put(1, 1);
    try a.put(2, 2);
    try a.put(3, 3);

    var b = try a.clone();
    defer b.deinit();

    try expectEqual(b.count(), 3);
    try expectEqual(b.get(1).?, 1);
    try expectEqual(b.get(2).?, 2);
    try expectEqual(b.get(3).?, 3);

    var original = AutoHashMap(i32, i32).init(std.testing.allocator);
    defer original.deinit();

    var i: u8 = 0;
    while (i < 10) : (i += 1) {
        try original.putNoClobber(i, i * 10);
    }

    var copy = try original.clone();
    defer copy.deinit();

    i = 0;
    while (i < 10) : (i += 1) {
        try testing.expect(copy.get(i).? == i * 10);
    }
}

test "ensureTotalCapacity with existing elements" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    try map.put(0, 0);
    try expectEqual(map.count(), 1);
    try expectEqual(map.capacity(), @TypeOf(map).Unmanaged.minimal_capacity);

    try map.ensureTotalCapacity(65);
    try expectEqual(map.count(), 1);
    try expectEqual(map.capacity(), 128);
}

test "ensureTotalCapacity satisfies max load factor" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    try map.ensureTotalCapacity(127);
    try expectEqual(map.capacity(), 256);
}

test "remove" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        try map.put(i, i);
    }

    i = 0;
    while (i < 16) : (i += 1) {
        if (i % 3 == 0) {
            _ = map.remove(i);
        }
    }
    try expectEqual(map.count(), 10);
    var it = map.iterator();
    while (it.next()) |kv| {
        try expectEqual(kv.key_ptr.*, kv.value_ptr.*);
        try expect(kv.key_ptr.* % 3 != 0);
    }

    i = 0;
    while (i < 16) : (i += 1) {
        if (i % 3 == 0) {
            try expect(!map.contains(i));
        } else {
            try expectEqual(map.get(i).?, i);
        }
    }
}

test "reverse removes" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        try map.putNoClobber(i, i);
    }

    i = 16;
    while (i > 0) : (i -= 1) {
        _ = map.remove(i - 1);
        try expect(!map.contains(i - 1));
        var j: u32 = 0;
        while (j < i - 1) : (j += 1) {
            try expectEqual(map.get(j).?, j);
        }
    }

    try expectEqual(map.count(), 0);
}

test "multiple removes on same metadata" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        try map.put(i, i);
    }

    _ = map.remove(7);
    _ = map.remove(15);
    _ = map.remove(14);
    _ = map.remove(13);
    try expect(!map.contains(7));
    try expect(!map.contains(15));
    try expect(!map.contains(14));
    try expect(!map.contains(13));

    i = 0;
    while (i < 13) : (i += 1) {
        if (i == 7) {
            try expect(!map.contains(i));
        } else {
            try expectEqual(map.get(i).?, i);
        }
    }

    try map.put(15, 15);
    try map.put(13, 13);
    try map.put(14, 14);
    try map.put(7, 7);
    i = 0;
    while (i < 16) : (i += 1) {
        try expectEqual(map.get(i).?, i);
    }
}

test "put and remove loop in random order" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var keys = std.array_list.Managed(u32).init(std.testing.allocator);
    defer keys.deinit();

    const size = 32;
    const iterations = 100;

    var i: u32 = 0;
    while (i < size) : (i += 1) {
        try keys.append(i);
    }
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const random = prng.random();

    while (i < iterations) : (i += 1) {
        random.shuffle(u32, keys.items);

        for (keys.items) |key| {
            try map.put(key, key);
        }
        try expectEqual(map.count(), size);

        for (keys.items) |key| {
            _ = map.remove(key);
        }
        try expectEqual(map.count(), 0);
    }
}

test "remove many elements in random order" {
    const Map = AutoHashMap(u32, u32);
    const n = 1000 * 100;
    var map = Map.init(std.heap.page_allocator);
    defer map.deinit();

    var keys = std.array_list.Managed(u32).init(std.heap.page_allocator);
    defer keys.deinit();

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        keys.append(i) catch unreachable;
    }

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const random = prng.random();
    random.shuffle(u32, keys.items);

    for (keys.items) |key| {
        map.put(key, key) catch unreachable;
    }

    random.shuffle(u32, keys.items);
    i = 0;
    while (i < n) : (i += 1) {
        const key = keys.items[i];
        _ = map.remove(key);
    }
}

test "put" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        try map.put(i, i);
    }

    i = 0;
    while (i < 16) : (i += 1) {
        try expectEqual(map.get(i).?, i);
    }

    i = 0;
    while (i < 16) : (i += 1) {
        try map.put(i, i * 16 + 1);
    }

    i = 0;
    while (i < 16) : (i += 1) {
        try expectEqual(map.get(i).?, i * 16 + 1);
    }
}

test "putAssumeCapacity" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    try map.ensureTotalCapacity(20);
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        map.putAssumeCapacityNoClobber(i, i);
    }

    i = 0;
    var sum = i;
    while (i < 20) : (i += 1) {
        sum += map.getPtr(i).?.*;
    }
    try expectEqual(sum, 190);

    i = 0;
    while (i < 20) : (i += 1) {
        map.putAssumeCapacity(i, 1);
    }

    i = 0;
    sum = i;
    while (i < 20) : (i += 1) {
        sum += map.get(i).?;
    }
    try expectEqual(sum, 20);
}

test "repeat putAssumeCapacity/remove" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    try map.ensureTotalCapacity(20);
    const limit = map.unmanaged.available;

    var i: u32 = 0;
    while (i < limit) : (i += 1) {
        map.putAssumeCapacityNoClobber(i, i);
    }

    // Repeatedly delete/insert an entry without resizing the map.
    // Put to different keys so entries don't land in the just-freed slot.
    i = 0;
    while (i < 10 * limit) : (i += 1) {
        try testing.expect(map.remove(i));
        if (i % 2 == 0) {
            map.putAssumeCapacityNoClobber(limit + i, i);
        } else {
            map.putAssumeCapacity(limit + i, i);
        }
    }

    i = 9 * limit;
    while (i < 10 * limit) : (i += 1) {
        try expectEqual(map.get(limit + i), i);
    }
    try expectEqual(map.unmanaged.available, 0);
    try expectEqual(map.unmanaged.count(), limit);
}

test "getOrPut" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try map.put(i * 2, 2);
    }

    i = 0;
    while (i < 20) : (i += 1) {
        _ = try map.getOrPutValue(i, 1);
    }

    i = 0;
    var sum = i;
    while (i < 20) : (i += 1) {
        sum += map.get(i).?;
    }

    try expectEqual(sum, 30);
}

test "basic hash map usage" {
    var map = AutoHashMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    try testing.expect((try map.fetchPut(1, 11)) == null);
    try testing.expect((try map.fetchPut(2, 22)) == null);
    try testing.expect((try map.fetchPut(3, 33)) == null);
    try testing.expect((try map.fetchPut(4, 44)) == null);

    try map.putNoClobber(5, 55);
    try testing.expect((try map.fetchPut(5, 66)).?.value == 55);
    try testing.expect((try map.fetchPut(5, 55)).?.value == 66);

    const gop1 = try map.getOrPut(5);
    try testing.expect(gop1.found_existing == true);
    try testing.expect(gop1.value_ptr.* == 55);
    gop1.value_ptr.* = 77;
    try testing.expect(map.getEntry(5).?.value_ptr.* == 77);

    const gop2 = try map.getOrPut(99);
    try testing.expect(gop2.found_existing == false);
    gop2.value_ptr.* = 42;
    try testing.expect(map.getEntry(99).?.value_ptr.* == 42);

    const gop3 = try map.getOrPutValue(5, 5);
    try testing.expect(gop3.value_ptr.* == 77);

    const gop4 = try map.getOrPutValue(100, 41);
    try testing.expect(gop4.value_ptr.* == 41);

    try testing.expect(map.contains(2));
    try testing.expect(map.getEntry(2).?.value_ptr.* == 22);
    try testing.expect(map.get(2).? == 22);

    const rmv1 = map.fetchRemove(2);
    try testing.expect(rmv1.?.key == 2);
    try testing.expect(rmv1.?.value == 22);
    try testing.expect(map.fetchRemove(2) == null);
    try testing.expect(map.remove(2) == false);
    try testing.expect(map.getEntry(2) == null);
    try testing.expect(map.get(2) == null);

    try testing.expect(map.remove(3) == true);
}

test "getOrPutAdapted" {
    const AdaptedContext = struct {
        fn eql(self: @This(), adapted_key: []const u8, test_key: u64) bool {
            _ = self;
            return std.fmt.parseInt(u64, adapted_key, 10) catch unreachable == test_key;
        }
        fn hash(self: @This(), adapted_key: []const u8) u64 {
            _ = self;
            const key = std.fmt.parseInt(u64, adapted_key, 10) catch unreachable;
            return (AutoContext(u64){}).hash(key);
        }
    };
    var map = AutoHashMap(u64, u64).init(testing.allocator);
    defer map.deinit();

    const keys = [_][]const u8{
        "1231",
        "4564",
        "7894",
        "1132",
        "65235",
        "95462",
        "0112305",
        "00658",
        "0",
        "2",
    };

    var real_keys: [keys.len]u64 = undefined;

    inline for (keys, 0..) |key_str, i| {
        const result = try map.getOrPutAdapted(key_str, AdaptedContext{});
        try testing.expect(!result.found_existing);
        real_keys[i] = std.fmt.parseInt(u64, key_str, 10) catch unreachable;
        result.key_ptr.* = real_keys[i];
        result.value_ptr.* = i * 2;
    }

    try testing.expectEqual(map.count(), keys.len);

    inline for (keys, 0..) |key_str, i| {
        const result = map.getOrPutAssumeCapacityAdapted(key_str, AdaptedContext{});
        try testing.expect(result.found_existing);
        try testing.expectEqual(real_keys[i], result.key_ptr.*);
        try testing.expectEqual(@as(u64, i) * 2, result.value_ptr.*);
        try testing.expectEqual(real_keys[i], map.getKeyAdapted(key_str, AdaptedContext{}).?);
    }
}

test "ensureUnusedCapacity" {
    var map = AutoHashMap(u64, u64).init(testing.allocator);
    defer map.deinit();

    try map.ensureUnusedCapacity(32);
    const capacity = map.capacity();
    try map.ensureUnusedCapacity(32);

    // Repeated ensureUnusedCapacity() calls with no insertions between
    // should not change the capacity.
    try testing.expectEqual(capacity, map.capacity());
}

test "removeByPtr" {
    var map = AutoHashMap(i32, u64).init(testing.allocator);
    defer map.deinit();

    var i: i32 = undefined;

    i = 0;
    while (i < 10) : (i += 1) {
        try map.put(i, 0);
    }

    try testing.expect(map.count() == 10);

    i = 0;
    while (i < 10) : (i += 1) {
        const key_ptr = map.getKeyPtr(i);
        try testing.expect(key_ptr != null);

        if (key_ptr) |ptr| {
            map.removeByPtr(ptr);
        }
    }

    try testing.expect(map.count() == 0);
}

test "removeByPtr 0 sized key" {
    var map = AutoHashMap(u0, u64).init(testing.allocator);
    defer map.deinit();

    try map.put(0, 0);

    try testing.expect(map.count() == 1);

    const key_ptr = map.getKeyPtr(0);
    try testing.expect(key_ptr != null);

    if (key_ptr) |ptr| {
        map.removeByPtr(ptr);
    }

    try testing.expect(map.count() == 0);
}

test "repeat fetchRemove" {
    var map: AutoHashMapUnmanaged(u64, void) = .empty;
    defer map.deinit(testing.allocator);

    try map.ensureTotalCapacity(testing.allocator, 4);

    map.putAssumeCapacity(0, {});
    map.putAssumeCapacity(1, {});
    map.putAssumeCapacity(2, {});
    map.putAssumeCapacity(3, {});

    // fetchRemove() should make slots available.
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try testing.expect(map.fetchRemove(3) != null);
        map.putAssumeCapacity(3, {});
    }

    try testing.expect(map.get(0) != null);
    try testing.expect(map.get(1) != null);
    try testing.expect(map.get(2) != null);
    try testing.expect(map.get(3) != null);
}

test "getOrPut allocation failure" {
    var map: std.StringHashMapUnmanaged(void) = .empty;
    try testing.expectError(error.OutOfMemory, map.getOrPut(std.testing.failing_allocator, "hello"));
}

test "rehash" {
    var map = AutoHashMap(usize, usize).init(std.testing.allocator);
    defer map.deinit();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    const count = 4 * random.intRangeLessThan(u32, 100_000, 500_000);

    for (0..count) |i| {
        try map.put(i, i);
        if (i % 3 == 0) {
            try expectEqual(map.remove(i), true);
        }
    }

    map.rehash();

    try expectEqual(map.count(), count * 2 / 3);

    for (0..count) |i| {
        if (i % 3 == 0) {
            try expectEqual(map.get(i), null);
        } else {
            try expectEqual(map.get(i).?, i);
        }
    }
}

test "removeByPtr, key is array" {
    const gpa = testing.allocator;

    var map: AutoHashMapUnmanaged([2]u32, u32) = .empty;
    defer map.deinit(gpa);

    const key: [2]u32 = .{ 1, 2 };
    try map.put(gpa, key, 3);

    try expectEqual(1, map.count());
    try expectEqual(3, map.get(key));

    const key_ptr = map.getKeyPtr(key).?;
    map.removeByPtr(key_ptr);

    try expectEqual(0, map.count());
    try expectEqual(null, map.get(key));
}
