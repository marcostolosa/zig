//! Provides the following guarantees:
//! * `deinit` reports all leaks and frees all backing memory.
//! * All allocation mismatches result in either a panic or segmentation fault.
//! * Allocations from other `SafeAllocator` instances cause a panic (if `Options.canary` differ).
//! * Double frees and operation (resize, remap, and free) races panic or segmentation fault.
//!
//! Given the backing allocator does not reuse memory, this does not reuse memory either and
//! * Most writes after free will segmentation fault or are eventually detected and panic.
//!
//! Thread-safe

// General Design:
//
// Every allocation is trailed by an `AllocFooter` which contains metadata for the allocation and
// stack traces. It is protected by a checksum to catch corruption from allocation overwrites and
// report canary mismatches. An allocation's memory has a minimum alignment of `AllocFooter` so
// that the footer is at a fixed offset determined from the allocation size. An allocation's memory
// is stored either:
// * Inside linearly-filled buckets for small allocations.
// * Inside an allocation directly from the backing allocator.
//
// To track allocations, each thread maintains a table of backing allocations. The table may be
// modified by other threads in the case of a producer-consumer operation, so the table is a linked
// list only expanded by creating new segments. Each thread maintains a linked list of free
// entries, which may contain entries from other threads' tables.
//
// In the case of producer-consumer operations, acquire/release ordering is assumed to be provided
// externally. This is also assumed by all other thread-safe allocators that reuse memory as
// otherwise there would be data races on reuse of allocated memory.

const std = @import("../std.zig");
const math = std.math;
const mem = std.mem;
const Alignment = mem.Alignment;
const assert = std.debug.assert;
const panic = std.debug.panic;

const SafeAllocator = @This();
const scoped_log = std.log.scoped(.SafeAllocator);

pub const Options = struct {
    const is_debug = @import("builtin").mode == .debug;
    const page_size_log2 = @max(math.log2_int(usize, std.heap.page_size_max), 8);

    stack_trace_frames: usize = if (is_debug and std.debug.sys_can_stack_trace) 7 else 0,
    check_write_after_free: bool = is_debug,
    no_resize: bool = is_debug,
    /// A unique value used to check that allocations created by other
    /// `SafeAllocator` instances are not passed to this one.
    canary: u32 = 0x85dff10f,

    /// Controls the block size and alignment of allocation buckets.
    ///
    /// Changing this is useful to save memory if the backing allocator offers better granuality,
    /// or if the backing allocator has a limit on active allocations, however decreasing this
    /// can harm performance.
    ///
    /// Asserted to be >= 8
    bucket_size_log2: u5 = @max(page_size_log2, 13),
    /// Controls the block size of internal metadata.
    ///
    /// Changing this is useful to save memory if the backing allocator offers better granuality,
    /// or if the backing allocator has a limit on active allocations, however decreasing this
    /// can harm performance.
    ///
    /// Asserted to be >= 8
    block_size_log2: u5 = page_size_log2,
};

var n_threads: usize = 0;
threadlocal var thread_index: usize = 0;

backing: mem.Allocator,
// Needs to be a fixed size so the max `n_threads` value is agreed upon by all instances.
threads: [128]Thread,

bucket_size_log2: u5,
block_size_log2: u5,
/// In `usize`s
stack_trace_size: usize,
/// In `usize`s
allocs_entry_count: usize,
large_alloc_threshold: usize,

canary: u32,
check_write_after_free: bool,
no_resize: bool,

fn bucketSize(s: *SafeAllocator) u32 {
    return @as(u32, 1) << s.bucket_size_log2;
}

fn bucketMask(s: *SafeAllocator) u32 {
    return s.bucketSize() - 1;
}

const Thread = struct {
    /// Avoid false sharing.
    _: void align(std.atomic.cache_line) = {},

    mutex: std.atomic.Mutex,
    fill_bucket: ?*Bucket,
    free_entry: ?*Allocs.Entry,
    allocs_next: usize,
    allocs_first: ?*Allocs,
};

/// Trailed by `[allocs_entry_count]Entry`
const Allocs = extern struct {
    next: ?*Allocs,

    comptime {
        assert(@alignOf(@This()) == @alignOf(usize));
        assert(@sizeOf(@This()) == @sizeOf(usize));
    }

    fn usizes(a: *Allocs, s: *SafeAllocator) []usize {
        return @as([*]usize, @ptrCast(a))[0 .. 1 + s.allocs_entry_count];
    }

    fn entries(a: *Allocs, s: *SafeAllocator) []Entry {
        return @as([*]Entry, @ptrCast(a))[1..][0..s.allocs_entry_count];
    }

    const Entry = packed struct(usize) {
        kind: Kind,
        ptr_high: @Int(.unsigned, @bitSizeOf(usize) - 2),

        const Kind = enum(u2) { free, bucket, large_alloc };

        comptime {
            assert(@alignOf(Entry) >= 4);
            assert(@alignOf(Bucket) >= 4);
            assert(@alignOf(AllocFooter) >= 4);
        }

        fn fromFree(ptr: ?*Entry) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .free,
            };
        }

        fn fromBucket(ptr: *Bucket) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .bucket,
            };
        }

        fn fromLargeAlloc(ptr: *AllocFooter) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .large_alloc,
            };
        }

        fn toFree(ent: Entry) ?*Entry {
            assert(ent.kind == .free);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }

        fn toBucket(ent: Entry) *Bucket {
            assert(ent.kind == .bucket);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }

        fn toLargeAlloc(ent: Entry) *AllocFooter {
            assert(ent.kind == .large_alloc);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }
    };
};

/// This struct contains the header for a bucket. It is always part of a larger
/// allocations of length and alignment `bucketSize()`.
///
/// All allocations inside buckets have a minimum of 8-byte alignment (including length)
/// so that allocations with 8-byte alignment or less do not need to store the location
/// of the previous footer since it is directly before it. This property is used by non-
/// extended footers to omit the offset of the previous footer.
const Bucket = struct {
    entry: *Allocs.Entry,
    /// Accesed atomically with `.acquire` / `.release` ordering to
    /// provide memory ordering for allocation footers, **expect for
    /// the `modify` field**. This needs `.acquire` fenced every time
    /// footer data is updated (`AllocCount.fenceAcqRel`).
    alloc_count: AllocCount,
    /// Accesed atomically with `.monotonic` ordering. Alternatively,
    /// this is also synchronized by `alloc_count`.
    fill: Fill,

    /// So that `@sizeOf(Bucket)` is the start of first allocation if it is 8-byte aligned or less.
    _: void align(8) = {},
    comptime {
        assert(@alignOf(@This()) >= 8);
    }

    const AllocCount = packed struct(u32) {
        n: u31,
        /// If `true`, this bucket cannot be freed yet.
        filling: bool,

        fn fenceAcqRel(a: *AllocCount) void {
            _ = @atomicRmw(AllocCount, a, .Or, .{ .n = 0, .filling = false }, .acq_rel);
        }
    };

    const Fill = packed struct(u32) {
        at: u31,
        last_is_extended: bool,
    };

    fn of(s: *SafeAllocator, ptr: [*]u8) *Bucket {
        const size_log2 = s.bucket_size_log2;
        return @ptrFromInt(@intFromPtr(ptr) >> @intCast(size_log2) << @intCast(size_log2));
    }

    fn fillAt(s: *SafeAllocator, ptr: [*]const u8) u32 {
        return @intCast(@intFromPtr(ptr) & s.bucketMask());
    }

    fn bytes(b: *Bucket, s: *SafeAllocator) []u8 {
        assert(@intFromPtr(b) & s.bucketMask() == 0);
        return @as([*]u8, @ptrCast(b))[0..s.bucketSize()];
    }

    fn lastAlloc(b: *Bucket, s: *SafeAllocator, fill: Fill) ?*AllocFooter {
        return b.allocFooterBefore(s, fill.at, fill.last_is_extended);
    }

    fn allocFooterBefore(b: *Bucket, s: *SafeAllocator, at: u32, is_extended: bool) ?*AllocFooter {
        if (at - @sizeOf(Bucket) == 0) return null;
        const off = at - AllocFooter.lenBucket(is_extended, s.stack_trace_size);
        assert(off >= @sizeOf(Bucket));
        return @ptrCast(@alignCast(b.bytes(s)[off..]));
    }

    fn allocFooterPrev(b: *Bucket, s: *SafeAllocator, f: *AllocFooter) ?*AllocFooter {
        if (f.isExtended()) return f.extended().container.toBucketPrev();
        return b.allocFooterBefore(s, Bucket.fillAt(s, f.userMemory().ptr), f.data.prev_extended);
    }

    /// Checks that no writes after frees were performed.
    ///
    /// Assumes `b.alloc_count` has been loaded with `.acquire` ordering.
    fn check(b: *Bucket, s: *SafeAllocator) void {
        var footer = b.lastAlloc(s, b.fill).?;
        while (true) {
            const modify = @atomicLoad(
                AllocFooter.Modify,
                &footer.modify,
                // The only possible value should be `.freed` since `b.alloc_count`
                // has been loaded with `.acquire`. However, another thread may be trying to
                // modify the allocation after it is freed and so the other thread is going
                // to panic even if this thread still sees `.freed`.
                .unordered,
            ).storedXor(&footer.modify);
            if (modify != .freed or footer.actualChecksum() != footer.checksum ^ s.canary) {
                panic("corrupted footer metadata in bucket at *{x}", .{@intFromPtr(&footer)});
            }

            if (s.check_write_after_free) checkFreed(footer, s.stack_trace_size);
            footer = b.allocFooterPrev(s, footer) orelse break;
        }
    }
};

/// Trails the allocation, which has the following advantages:
/// * For buckets, the footer of the last allocation is always at the current fill.
/// * Aligning the allocation is simpler and wastes less space.
/// * Allocation overwrites are more likely to be caught by the footer getting corrupted.
/// For bucket allocs, this is trailed by `[2][stack_trace_size]usize`.
/// For large allocs, this is trailed by `[1][stack_trace_size]usize`.
const AllocFooter = struct {
    /// Hash of `data` with the seed as the hash of its address so that memcpys of allocation
    /// metadata are detected or are at least caught across runs.
    ///
    /// This stored value is xored with the canary value so that canary mismatches are detected.
    checksum: u32,
    /// Accesed atomically with `.monotonic` ordering to catch operation races.
    ///
    /// This stored value is xored with the hash of its address so that memcpys of allocation
    /// metadata are detected or are at least caught across runs.
    modify: Modify,
    data: Data,

    /// `8`: minimum alignment for `Bucket` allocations
    /// `@alignOf(usize)`: so that the offset of trailing data is at `@sizeOf(@This())`
    _: void align(@max(8, @alignOf(usize))) = {},

    comptime {
        assert(@alignOf(@This()) >= @max(8, @alignOf(usize)));
    }

    const Data = packed struct(u16) {
        len: Len,
        /// Low bits of the alignment.
        ///
        /// For non-extended headers, this is the entire alignment. The location of the previous
        /// header is directly before this allocation since footers in `Bucket` are gauraunteed to
        /// have at least 8-byte alignment.
        alignment: u2,
        /// Used only for bucket allocations.
        prev_extended: bool,

        const Len = enum(u13) {
            _,

            /// This footer is trailed (before the traces) by `Extended`.
            /// The high bits of the alignment are encoded as the offset from `extended_start`.
            ///
            /// This may be set even if `Extended` is not strictly necesary
            /// as a result of resizes and remaps.
            const extended_start: u13 = math.maxInt(u13) - ((@bitSizeOf(usize) - 1) >> 2);
        };
    };

    const Extended = struct {
        len: usize,
        container: Container,

        /// Cannot be a plain union since another instance may access the wrong field when
        /// calculating the footer's checksum which is used to report the canary mismatch.
        const Container = enum(usize) {
            _,

            fn toBucketPrev(c: Container) ?*AllocFooter {
                return @ptrFromInt(@backingInt(c));
            }

            fn fromBucketPrev(prev: ?*AllocFooter) Container {
                return @fromBackingInt(@intFromPtr(prev));
            }

            fn toLargeEntry(c: Container) *Allocs.Entry {
                return @ptrFromInt(@backingInt(c));
            }

            fn fromLargeEntry(ent: *Allocs.Entry) Container {
                return @fromBackingInt(@intFromPtr(ent));
            }
        };

        comptime {
            // Exactly `usize` so this is directly after the regular footer
            // and so that traces start directly after `@sizeOf(@This())`.
            assert(@alignOf(@This()) == @alignOf(usize));
        }
    };

    const Modify = enum(u16) {
        // Random non-linear enum values to decrease the chance of undetected corruption.
        none = 0x2962,
        resized = 0x0030,
        remaped = 0x9068,
        freed = 0xb98b,
        _,

        fn setNone(m: *Modify) void {
            _ = @atomicRmw(Modify, m, .Xchg, .storedXor(.none, m), .monotonic);
        }

        fn opName(m: Modify) []const u8 {
            return switch (m) {
                .resized => "resize",
                .remaped => "remap",
                .freed => "free",
                _, .none => unreachable,
            };
        }

        fn stateName(m: Modify) []const u8 {
            return switch (m) {
                .resized => "after resize",
                .remaped => "after remap",
                .freed => "after free",
                _, .none => unreachable,
            };
        }

        fn storedXor(m: Modify, ptr: *Modify) Modify {
            const addr_hash: u16 = @truncate(std.hash.int(@intFromPtr(ptr)));
            return @fromBackingInt(@backingInt(m) ^ addr_hash);
        }
    };

    fn isExtended(f: *AllocFooter) bool {
        return @backingInt(f.data.len) >= Data.Len.extended_start;
    }

    fn extended(f: *AllocFooter) *Extended {
        assert(f.isExtended());
        return @ptrFromInt(@intFromPtr(f) + @sizeOf(AllocFooter));
    }

    fn userMemory(f: *AllocFooter) []u8 {
        const memory_addr = @intFromPtr(f) - allocOffset(f.userLen());
        assert(f.userAlign().check(memory_addr));
        const memory_ptr: [*]u8 = @ptrFromInt(memory_addr);
        return memory_ptr[0..f.userLen()];
    }

    fn userLen(f: *AllocFooter) usize {
        const len_int = @backingInt(f.data.len);
        return if (len_int < Data.Len.extended_start) len_int else f.extended().len;
    }

    fn userAlign(f: *AllocFooter) Alignment {
        const high = (@backingInt(f.data.len) -| Data.Len.extended_start) << 2;
        return @fromBackingInt(@intCast(high | f.data.alignment));
    }

    fn tracesPtr(f: *AllocFooter) [*]usize {
        const off_footer = @divExact(@sizeOf(AllocFooter), @sizeOf(usize));
        const off_extended = @as(usize, @divExact(@sizeOf(Extended), @sizeOf(usize))) *
            @intFromBool(f.isExtended());
        return @as([*]usize, @ptrCast(f))[off_footer + off_extended ..];
    }

    fn allocTrace(f: *AllocFooter, stack_trace_size: usize) []usize {
        return f.tracesPtr()[0..stack_trace_size];
    }

    fn freeTrace(f: *AllocFooter, stack_trace_size: usize) []usize {
        return f.tracesPtr()[stack_trace_size..][0..stack_trace_size];
    }

    fn actualChecksum(f: *AllocFooter) u32 {
        if (f.isExtended()) {
            const regular_bytes: [@sizeOf(Data)]u8 = @bitCast(f.data);
            const len_bytes: [@sizeOf(usize)]u8 = @bitCast(f.extended().len);
            const container: [@sizeOf(usize)]u8 = @bitCast(f.extended().container);
            const data_bytes = regular_bytes ++ len_bytes ++ container;

            return @truncate(std.hash.Wyhash.hash(@truncate(@intFromPtr(f)), &data_bytes));
        }
        return @truncate(std.hash.int(@as(u16, @bitCast(f.data)) ^ @intFromPtr(f)));
    }

    fn allocOffset(len: usize) usize {
        return Alignment.of(AllocFooter).forward(len);
    }

    fn allocAlign(a: Alignment) Alignment {
        return a.max(.of(AllocFooter));
    }

    /// Assumes the footer is in a bucket allocation; all
    /// large allocations require an extended header.
    fn requiresExtended(len: usize, alignment: Alignment) bool {
        return len >= Data.Len.extended_start or @backingInt(alignment) > math.maxInt(u2);
    }

    fn lenBucket(is_extended: bool, stack_trace_size: usize) usize {
        return Alignment.forward(.@"8", @sizeOf(AllocFooter) +
            @as(usize, @sizeOf(Extended)) * @intFromBool(is_extended) +
            stack_trace_size * @sizeOf(usize) * 2);
    }

    fn lenLarge(stack_trace_size: usize) usize {
        return @sizeOf(AllocFooter) + @sizeOf(Extended) + stack_trace_size * @sizeOf(usize);
    }

    fn allocLenBucket(user_len: usize, is_extended: bool, stack_trace_size: usize) usize {
        return allocOffset(user_len) + lenBucket(is_extended, stack_trace_size);
    }

    fn allocLenLarge(user_len: usize, stack_trace_size: usize) usize {
        return allocOffset(user_len) + lenLarge(stack_trace_size);
    }

    fn allocOffsetOrOom(user_len: usize) error{OutOfMemory}!usize {
        return alignForwardOrOom(.of(AllocFooter), user_len);
    }

    fn allocLenBucketOrOom(
        len: usize,
        is_extended: bool,
        stack_trace_size: usize,
    ) error{OutOfMemory}!usize {
        return addOrOom(try allocOffsetOrOom(len), lenBucket(is_extended, stack_trace_size));
    }

    fn of(user_memory: []u8) *AllocFooter {
        // Avoid panicing now if `memory.ptr` is not correctly aligned since a more
        // useful panic will be provided later by a mismatch or invalid footer.
        const aligned_start = Alignment.backward(.of(AllocFooter), @intFromPtr(user_memory.ptr));
        return @ptrFromInt(aligned_start + allocOffset(user_memory.len));
    }

    fn startModify(
        f: *AllocFooter,
        m: Modify,
        mem_fmt: FormatMemory,
        canary: u32,
        stack_trace_size: usize,
    ) void {
        const prev = @atomicRmw(
            Modify,
            &f.modify,
            .Xchg,
            .storedXor(m, &f.modify),
            .monotonic,
        ).storedXor(&f.modify);

        if (prev != .none) {
            @branchHint(.cold);
            const op_name = m.opName();
            switch (prev) {
                .none => unreachable,
                .resized, .remaped => panic(
                    \\{s} {s} of {f}
                    \\alloc: {f}
                    \\{s}:
                    // (panic stack trace)
                , .{
                    op_name,
                    prev.stateName(),
                    mem_fmt,
                    // The stack trace may have been overwritten, but at least give it a try
                    formatStackTrace(f.allocTrace(stack_trace_size)),
                    op_name,
                }),
                .freed => if (m == .freed) {
                    panic(
                        \\double free of {f}
                        \\alloc: {f}
                        \\first free: {f}
                        \\second free:
                        // (panic stack trace)
                    , .{
                        mem_fmt,
                        formatStackTrace(f.allocTrace(stack_trace_size)),
                        formatStackTrace(f.freeTrace(stack_trace_size)),
                    });
                } else {
                    panic(
                        \\{s} {s} of {f}
                        \\alloc: {f}
                        \\free: {f}
                        \\{s}:
                        // (panic stack trace)
                    , .{
                        op_name,
                        prev.stateName(),
                        mem_fmt,
                        formatStackTrace(f.allocTrace(stack_trace_size)),
                        formatStackTrace(f.freeTrace(stack_trace_size)),
                        op_name,
                    });
                },
                _ => panic(
                    "{s} of invalid memory {f} or corrupted metadata",
                    .{ op_name, mem_fmt },
                ),
            }
            comptime unreachable;
        }

        const expected_checksum = f.actualChecksum();
        if (f.checksum ^ canary != expected_checksum) {
            @branchHint(.cold);
            const other_canary = f.checksum ^ expected_checksum;
            panic(
                "{s} of invalid memory {f}, corrupted metadata, or foreign allocation from canary 0x{x}",
                .{ m.opName(), mem_fmt, other_canary },
            );
        }

        if (f.userLen() != mem_fmt.memory.len or f.userAlign() != mem_fmt.alignment) {
            const op_name = m.opName();
            panic(
                \\{s} of {f} mismatches allocation of {f}
                \\alloc: {f}
                \\{s}:
                // (panic stack trace)
            , .{ op_name, mem_fmt, FormatMemory{
                .memory = f.userMemory(),
                .alignment = f.userAlign(),
            }, formatStackTrace(f.allocTrace(stack_trace_size)), op_name });
        }
    }

    const PopulateOptions = struct {
        canary: u32,
        is_extended: bool,
        stack_trace_size: usize,

        user_len: usize,
        user_align: Alignment,
        ra: usize,

        prev_extended: bool,
        container: Extended.Container,
    };

    /// It is the caller's responsibility to `.acquire` fence the respective `Bucket.alloc_count`.
    fn populate(memory: []align(@alignOf(AllocFooter)) u8, p: PopulateOptions) *AllocFooter {
        const footer: *AllocFooter = @ptrCast(@alignCast(memory[allocOffset(p.user_len)..].ptr));

        if (!p.is_extended) {
            footer.data = .{
                .len = @fromBackingInt(@intCast(p.user_len)),
                .alignment = @intCast(@backingInt(p.user_align)),
                .prev_extended = p.prev_extended,
            };
            assert(!footer.isExtended());
        } else {
            footer.data = .{
                .len = @fromBackingInt(Data.Len.extended_start + (@backingInt(p.user_align) >> 2)),
                .alignment = @truncate(@backingInt(p.user_align)),
                .prev_extended = p.prev_extended,
            };
            assert(footer.isExtended());
            footer.extended().* = .{
                .len = p.user_len,
                .container = p.container,
            };
        }

        captureStackTrace(footer.allocTrace(p.stack_trace_size), p.ra);
        footer.checksum = footer.actualChecksum() ^ p.canary;
        footer.modify.setNone();

        return footer;
    }
};

pub fn init(
    /// Must be thread-safe for this allocator to be thread-safe
    backing: mem.Allocator,
    options: Options,
) SafeAllocator {
    assert(options.block_size_log2 >= 8);
    assert(options.bucket_size_log2 >= 8);

    const allocs_entry_count = (@as(usize, 1) << options.block_size_log2) / @sizeOf(usize);
    return .{
        .backing = backing,
        .threads = @splat(.{
            .mutex = .unlocked,
            .fill_bucket = null,
            .free_entry = null,
            .allocs_next = allocs_entry_count,
            .allocs_first = null,
        }),

        .bucket_size_log2 = options.bucket_size_log2,
        .block_size_log2 = options.block_size_log2,
        .stack_trace_size = options.stack_trace_frames +
            @intFromBool(options.stack_trace_frames != 0),
        .allocs_entry_count = allocs_entry_count,
        .large_alloc_threshold = (@as(usize, 1) << options.bucket_size_log2) * 3 / 4,

        .canary = options.canary,
        .check_write_after_free = options.check_write_after_free,
        .no_resize = options.no_resize,
    };
}

/// Returns the number of leaks
pub fn deinit(s: *SafeAllocator) usize {
    return s.deinitLog(true);
}

/// Same as `deinit`, expect if `log` is `false`, it will not log leaks.
pub fn deinitLog(s: *SafeAllocator, log: bool) usize {
    var leaks: usize = 0;
    const thread_count = @atomicRmw(usize, &n_threads, .Or, 0, .monotonic);
    for (s.threads[0..@max(1, thread_count)]) |*t| {
        assert(t.mutex == .unlocked); // use of allocator during `deinit`

        var maybe_allocs = t.allocs_first;
        var n_entries = t.allocs_next;
        while (maybe_allocs) |allocs| {
            for (allocs.entries(s)[0..n_entries]) |*ent| {
                switch (ent.kind) {
                    .free => {
                        @branchHint(.likely);
                    },
                    .bucket => leaks += s.deinitLeakedBucket(ent.toBucket(), log),
                    .large_alloc => {
                        leaks += 1;
                        s.deinitLargeAlloc(ent.toLargeAlloc(), log);
                    },
                }
            }
            maybe_allocs = allocs.next;
            n_entries = s.allocs_entry_count;
            s.backing.rawFree(@ptrCast(allocs.usizes(s)), .of(usize), 0);
        }
    }
    return leaks;
}

/// Returns the true count of leaks
fn deinitLeakedBucket(s: *SafeAllocator, b: *Bucket, log: bool) usize {
    var leaks: usize = 0;

    const expected = @atomicLoad(Bucket.AllocCount, &b.alloc_count, .acquire);
    if (expected.n == 0) assert(expected.filling);

    var footer = b.lastAlloc(s, b.fill).?;
    while (true) {
        const modify = @atomicRmw(
            AllocFooter.Modify,
            &footer.modify,
            .Xchg,
            undefined,
            .monotonic,
        ).storedXor(&footer.modify);

        const bad_modify = modify != .none and modify != .freed;
        if (bad_modify or footer.actualChecksum() != footer.checksum ^ s.canary) {
            panic("corrupted footer metadata in bucket at *{x}", .{@intFromPtr(&footer)});
        }

        switch (modify) {
            .none => {
                leaks += 1;
                if (log) scoped_log.err("leaked {f} allocated at: {f}", .{ FormatMemory{
                    .memory = footer.userMemory(),
                    .alignment = footer.userAlign(),
                }, formatStackTrace(footer.allocTrace(s.stack_trace_size)) });
            },
            .freed => if (s.check_write_after_free) checkFreed(footer, s.stack_trace_size),
            else => unreachable,
        }

        footer = b.allocFooterPrev(s, footer) orelse break;
    }
    s.backing.rawFree(b.bytes(s), @fromBackingInt(@intCast(s.bucket_size_log2)), 0);

    assert(leaks == expected.n);
    return leaks;
}

fn deinitLargeAlloc(s: *SafeAllocator, footer: *AllocFooter, log: bool) void {
    const modify = footer.modify.storedXor(&footer.modify);
    if (modify != .none or footer.checksum ^ s.canary != footer.actualChecksum()) {
        panic("corrupted footer metadata at *{x}", .{@intFromPtr(&footer)});
    }

    const memory = footer.userMemory();
    if (log) scoped_log.err("leaked {f} allocated at {f}", .{ FormatMemory{
        .memory = memory,
        .alignment = footer.userAlign(),
    }, formatStackTrace(footer.allocTrace(s.stack_trace_size)) });

    s.backing.rawFree(
        memory.ptr[0..AllocFooter.allocLenLarge(memory.len, s.stack_trace_size)],
        AllocFooter.allocAlign(footer.userAlign()),
        0,
    );
}

/// Returned allocator is thread-safe
pub fn allocator(s: *SafeAllocator) mem.Allocator {
    return .{ .ptr = s, .vtable = &vtable };
}

fn acquireThread(s: *SafeAllocator) *Thread {
    while (true) {
        const t = &s.threads[thread_index];
        if (t.mutex.tryLock()) {
            @branchHint(.likely);
            return t;
        }

        var max = @atomicLoad(usize, &n_threads, .unordered);
        if (max == 0) {
            @branchHint(.unlikely);
            max = @min(std.Thread.getCpuCount() catch s.threads.len, s.threads.len);
            max = @cmpxchgStrong(usize, &n_threads, 0, max, .monotonic, .monotonic) orelse max;
        }

        thread_index += 1;
        // thread_index may be greater than max if the zero is returned by getCpuCount
        thread_index *= @intFromBool(thread_index < max);
    }
}

fn alignForwardOrOom(a: Alignment, addr: usize) error{OutOfMemory}!usize {
    const x = a.toByteUnits() - 1;
    return try addOrOom(addr, x) & ~x;
}

fn addOrOom(a: usize, b: usize) error{OutOfMemory}!usize {
    return math.add(usize, a, b) catch error.OutOfMemory;
}

fn isLarge(s: *SafeAllocator, len: usize, alignment: Alignment) bool {
    const max_align_waste = alignment.toByteUnits() - 1;
    const max_use = max_align_waste + AllocFooter.allocLenBucket(len, true, s.stack_trace_size);
    return max_use >= s.large_alloc_threshold;
}

fn isLargeOrOom(s: *SafeAllocator, len: usize, alignment: Alignment) error{OutOfMemory}!bool {
    const max_align_waste = alignment.toByteUnits() - 1;
    const max_use = try addOrOom(
        max_align_waste,
        try AllocFooter.allocLenBucketOrOom(len, true, s.stack_trace_size),
    );
    return max_use >= s.large_alloc_threshold;
}

fn newAllocEntry(s: *SafeAllocator, t: *Thread, ra: usize) error{OutOfMemory}!*Allocs.Entry {
    if (t.free_entry) |ent| {
        @branchHint(.likely);
        t.free_entry = ent.toFree();
        return ent;
    }

    if (s.allocs_entry_count - t.allocs_next != 0) {
        @branchHint(.likely);
        const ent = &t.allocs_first.?.entries(s)[t.allocs_next];
        t.allocs_next += 1;
        return ent;
    }

    const new_segment: *Allocs = @ptrCast(@alignCast(s.backing.rawAlloc(
        (1 + s.allocs_entry_count) * @sizeOf(usize),
        .of(usize),
        ra,
    ) orelse return error.OutOfMemory));
    new_segment.next = t.allocs_first;
    t.allocs_first = new_segment;
    t.allocs_next = 1;
    return &new_segment.entries(s)[0];
}

fn freeAllocEntry(t: *Thread, ent: *Allocs.Entry) void {
    ent.* = .fromFree(t.free_entry);
    t.free_entry = ent;
}

fn overwriteFreed(bytes: []u8) void {
    // 0x55 is used so that undefined writes of 0xaa are still caught. Another option would be a
    // stream of random bytes seeded by the address, however that makes debugging reads after frees
    // more difficult and has a performance penalty and so is not worth catching slightly more
    // writes after frees.
    @memset(bytes, 0x55);
}

/// Returns the first address of a write after free
fn checkFreed(footer: *AllocFooter, stack_trace_size: usize) void {
    const memory = footer.userMemory();
    for (memory) |*b| if (b.* != 0x55) {
        panic(
            \\write after free at *{x}
            \\original alloc of {f}: {f}
            \\free: {f}
            \\stack trace:
            // (panic stack trace)
        , .{
            @intFromPtr(b),
            FormatMemory{ .memory = memory, .alignment = footer.userAlign() },
            formatStackTrace(footer.allocTrace(stack_trace_size)),
            formatStackTrace(footer.freeTrace(stack_trace_size)),
        });
    };
}

const FormatMemory = struct {
    memory: []const u8,
    alignment: Alignment,

    pub fn format(m: FormatMemory, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return w.print(
            "[addr: {x}, len: {} (0x{x}) align: {}]",
            .{ @intFromPtr(m.memory.ptr), m.memory.len, m.memory.len, m.alignment.toByteUnits() },
        );
    }
};

/// The first element stores the length of the stack trace including skipped frames.
/// The remaining elements store the return addresses.
fn captureStackTrace(trace_buf: []usize, ra: usize) void {
    if (trace_buf.len == 0) return;

    if (ra == 0) { // No return address provided
        @branchHint(.unlikely);
        trace_buf[0] = 0;
        return;
    }

    const t = std.debug.captureCurrentStackTrace(.{ .first_address = ra }, trace_buf[1..]);
    const skipped = @backingInt(t.skipped) *
        @intFromBool(t.return_addresses.len == trace_buf[1..].len);
    trace_buf[0] = t.return_addresses.len +| skipped;
}

fn formatStackTrace(trace_buf: []usize) std.debug.FormatStackTrace {
    return .{
        .stack_trace = if (trace_buf.len != 0) trace: {
            const frames = trace_buf[0];
            const addrs = trace_buf[1..];
            break :trace .{
                .return_addresses = addrs[0..@min(frames, addrs.len)],
                .skipped = switch (frames) {
                    else => @fromBackingInt(@intCast(frames -| addrs.len)),
                    0, math.maxInt(usize) => .unknown,
                },
            };
        } else .{
            .return_addresses = &.{},
            .skipped = .unknown,
        },
        .terminal_mode = std.log.terminalMode(),
    };
}

/// If this fails, future allocations to the bucket are illegal
fn allocBucket(
    s: *SafeAllocator,
    t: *Thread,
    b: *Bucket,
    len: usize,
    alignment: Alignment,
    ra: usize,
) ?[*]u8 {
    const fill = &b.fill;
    const is_extended = AllocFooter.requiresExtended(len, alignment);
    const alloc_len: u32 = @intCast(AllocFooter.allocLenBucket(len, is_extended, s.stack_trace_size));
    const alloc_align = AllocFooter.allocAlign(alignment);

    var prev_fill = @atomicLoad(Bucket.Fill, fill, .monotonic);
    var start: u32 = undefined;
    var end: u32 = undefined;
    while (true) {
        start = @intCast(alloc_align.forward(prev_fill.at));
        end = start + alloc_len;

        if (end > s.bucketSize()) {
            @branchHint(.unlikely);

            const prev_count = @atomicRmw(
                Bucket.AllocCount,
                &b.alloc_count,
                .Sub,
                .{ .filling = true, .n = 0 },
                .acq_rel,
            );
            assert(prev_count.filling);

            if (prev_count.n == 0) {
                @branchHint(.unlikely);
                freeAllocEntry(t, b.entry);
                b.check(s);
                s.backing.rawFree(b.bytes(s), @fromBackingInt(@intCast(s.bucket_size_log2)), ra);
            }

            return null;
        }

        prev_fill = @cmpxchgWeak(
            Bucket.Fill,
            fill,
            prev_fill,
            .{ .at = @intCast(end), .last_is_extended = is_extended },
            .monotonic,
            .monotonic,
        ) orelse {
            @branchHint(.likely);
            break;
        };
        // b.fill was changed during a resize (or a sporadic cmpxchgWeak failure)
    }

    const memory = b.bytes(s)[start..end];
    _ = AllocFooter.populate(@alignCast(memory), .{
        .canary = s.canary,
        .is_extended = is_extended,
        .stack_trace_size = s.stack_trace_size,

        .user_len = len,
        .user_align = alignment,
        .ra = ra,

        .prev_extended = prev_fill.last_is_extended,
        .container = .fromBucketPrev(b.lastAlloc(s, prev_fill)),
    });

    assert(@atomicRmw(
        Bucket.AllocCount,
        &b.alloc_count,
        .Add,
        .{ .filling = false, .n = 1 },
        .acq_rel,
    ).filling);

    return memory.ptr;
}

fn growingResizeBucket(
    s: *SafeAllocator,
    f: *AllocFooter,
    memory: []const u8,
    alignment: Alignment,
    new_len: usize,
    ra: usize,
) bool {
    assert(new_len >= memory.len);
    return s.advanceBucketAlloc(f, Bucket.fillAt(s, memory.ptr), false, alignment, new_len, ra);
}

fn advanceBucketAlloc(
    s: *SafeAllocator,
    old: *AllocFooter,
    new_start: u32,
    start_moved: bool,
    alignment: Alignment,
    new_len: usize,
    ra: usize,
) bool {
    assert(AllocFooter.allocAlign(alignment).check(new_start));
    const b: *Bucket = .of(s, @ptrCast(old));

    const old_is_extended = old.isExtended();
    const old_footer_len = AllocFooter.lenBucket(old_is_extended, s.stack_trace_size);
    const old_fill: u32 = @intCast(Bucket.fillAt(s, @ptrCast(old)) + old_footer_len);

    const new_is_extended = old_is_extended or start_moved or
        AllocFooter.requiresExtended(new_len, alignment);
    const new_footer_len = AllocFooter.lenBucket(new_is_extended, s.stack_trace_size);
    const new_fill: u32 = @intCast(new_start + AllocFooter.allocOffset(new_len) + new_footer_len);

    assert(old_fill <= new_fill);
    if (new_fill > s.bucketSize()) {
        return false;
    }

    if (old_fill == new_fill or @cmpxchgStrong(
        Bucket.Fill,
        &b.fill,
        .{ .last_is_extended = old_is_extended, .at = @intCast(old_fill) },
        .{ .last_is_extended = new_is_extended, .at = @intCast(new_fill) },
        .monotonic,
        .monotonic,
    ) != null) {
        return false;
    }

    _ = AllocFooter.populate(@alignCast(b.bytes(s)[new_start..new_fill]), .{
        .canary = s.canary,
        .is_extended = new_is_extended,
        .stack_trace_size = s.stack_trace_size,

        .user_len = new_len,
        .user_align = alignment,
        .ra = ra,

        .prev_extended = old.data.prev_extended,
        .container = .fromBucketPrev(b.allocFooterPrev(s, old)),
    });
    b.alloc_count.fenceAcqRel();
    return true;
}

const vtable: mem.Allocator.VTable = .{
    .alloc = alloc,
    .free = free,
    .resize = resize,
    .remap = remap,
};

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    assert(len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const t = s.acquireThread();
    defer t.mutex.unlock();

    if (s.isLargeOrOom(len, alignment) catch return null) {
        @branchHint(.unlikely);

        const entry = s.newAllocEntry(t, ra) catch return null;
        const alloc_len = AllocFooter.allocLenLarge(len, s.stack_trace_size);
        const alloc_align = AllocFooter.allocAlign(alignment);
        const alloc_ptr = s.backing.rawAlloc(alloc_len, alloc_align, ra) orelse {
            freeAllocEntry(t, entry);
            return null;
        };

        const footer = AllocFooter.populate(@alignCast(alloc_ptr[0..alloc_len]), .{
            .canary = s.canary,
            .is_extended = true,
            .stack_trace_size = s.stack_trace_size,

            .user_len = len,
            .user_align = alignment,
            .ra = ra,

            .prev_extended = false,
            .container = .fromLargeEntry(entry),
        });
        entry.* = .fromLargeAlloc(footer);

        return alloc_ptr;
    }

    if (t.fill_bucket) |bucket| {
        @branchHint(.likely);
        if (s.allocBucket(t, bucket, len, alignment, ra)) |ptr| {
            @branchHint(.likely);
            return ptr;
        }
    }
    t.fill_bucket = null; // In case of OOM below, this bucket will still be unusable for future
    // allocations.

    const entry = s.newAllocEntry(t, ra) catch return null;
    const bucket: *Bucket = @ptrCast(@alignCast(s.backing.rawAlloc(
        s.bucketSize(),
        @fromBackingInt(@intCast(s.bucket_size_log2)),
        ra,
    ) orelse {
        freeAllocEntry(t, entry);
        return null;
    }));
    bucket.* = .{
        .entry = entry,
        // No atomic stores necessary because this thread is the
        // first to atomically update these below in allocBucket.
        .alloc_count = .{ .filling = true, .n = 0 },
        .fill = .{ .at = @sizeOf(Bucket), .last_is_extended = false },
    };
    entry.* = .fromBucket(bucket);

    t.fill_bucket = bucket;
    return s.allocBucket(t, bucket, len, alignment, ra);
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(
        .freed,
        .{ .memory = memory, .alignment = alignment },
        s.canary,
        s.stack_trace_size,
    );

    if (s.isLarge(memory.len, alignment)) {
        @branchHint(.unlikely);

        const t = s.acquireThread();
        freeAllocEntry(t, f.extended().container.toLargeEntry());
        t.mutex.unlock();
        s.backing.rawFree(
            memory.ptr[0..AllocFooter.allocLenLarge(memory.len, s.stack_trace_size)],
            AllocFooter.allocAlign(alignment),
            ra,
        );
        return;
    }

    const b: *Bucket = .of(s, memory.ptr);
    if (s.check_write_after_free) overwriteFreed(memory);
    captureStackTrace(f.freeTrace(s.stack_trace_size), ra);

    const prev_count = @atomicRmw(
        Bucket.AllocCount,
        &b.alloc_count,
        .Sub,
        .{ .filling = false, .n = 1 },
        .acq_rel,
    );

    if (prev_count.n - 1 == 0 and !prev_count.filling) {
        @branchHint(.unlikely);
        const t = s.acquireThread();
        freeAllocEntry(t, b.entry);
        t.mutex.unlock();
        b.check(s);
        s.backing.rawFree(b.bytes(s), @fromBackingInt(@intCast(s.bucket_size_log2)), ra);
    }
}

fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    assert(new_len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(
        .resized,
        .{ .memory = memory, .alignment = alignment },
        s.canary,
        s.stack_trace_size,
    );

    if (s.no_resize) {
        f.modify.setNone();
        return false;
    }

    // Check that the allocation is not moving between a bucket and large allocation. This is
    // done after the above so that it is still checked that valid memory is passed and there
    // is no double modify.
    const from_large_alloc = s.isLarge(memory.len, alignment);
    const to_large_alloc = s.isLargeOrOom(new_len, alignment) catch {
        f.modify.setNone();
        return false;
    };
    if (from_large_alloc != to_large_alloc) {
        @branchHint(.unlikely);
        f.modify.setNone();
        return false;
    }

    if (from_large_alloc) {
        @branchHint(.unlikely);

        const entry = f.extended().container.toLargeEntry();
        const new_alloc_len = AllocFooter.allocLenLarge(new_len, s.stack_trace_size);
        if (!s.backing.rawResize(
            memory.ptr[0..AllocFooter.allocLenLarge(memory.len, s.stack_trace_size)],
            AllocFooter.allocAlign(alignment),
            new_alloc_len,
            ra,
        )) {
            f.modify.setNone();
            return false;
        }

        const new_footer = AllocFooter.populate(@alignCast(memory.ptr[0..new_alloc_len]), .{
            .canary = s.canary,
            .is_extended = true,
            .stack_trace_size = s.stack_trace_size,

            .user_len = new_len,
            .user_align = alignment,
            .ra = ra,

            .prev_extended = false,
            .container = .fromLargeEntry(entry),
        });
        assert(entry.kind == .large_alloc);
        entry.* = .fromLargeAlloc(new_footer);
        return true;
    }

    if (new_len < memory.len) {
        // Resize shrinks are disallowed in all cases since the linked list would be broken. Even
        // if this footer is the final one, the fill value would need decreased which would allow
        // memory to be reused.
        f.modify.setNone();
        return false;
    }

    if (s.growingResizeBucket(f, memory, alignment, new_len, ra)) {
        @branchHint(.likely);
        return true;
    } else {
        f.modify.setNone();
        return false;
    }
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    assert(new_len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(
        .remaped,
        .{ .memory = memory, .alignment = alignment },
        s.canary,
        s.stack_trace_size,
    );

    if (s.no_resize) {
        f.modify.setNone();
        return null;
    }

    // Check that the allocation is not moving between a bucket and large allocation. This is
    // done after the above so that it is still checked that valid memory is passed and there
    // is no double modify.
    const from_large_alloc = s.isLarge(memory.len, alignment);
    const to_large_alloc = s.isLargeOrOom(new_len, alignment) catch {
        f.modify.setNone();
        return null;
    };
    if (from_large_alloc != to_large_alloc) {
        @branchHint(.unlikely);
        f.modify.setNone();
        return null;
    }

    if (from_large_alloc) {
        @branchHint(.unlikely);

        const entry = f.extended().container.toLargeEntry();
        const new_alloc_len = AllocFooter.allocLenLarge(new_len, s.stack_trace_size);
        const new_memory = s.backing.rawRemap(
            memory.ptr[0..AllocFooter.allocLenLarge(memory.len, s.stack_trace_size)],
            AllocFooter.allocAlign(alignment),
            new_alloc_len,
            ra,
        ) orelse {
            f.modify.setNone();
            return null;
        };

        const new_footer = AllocFooter.populate(@alignCast(new_memory[0..new_alloc_len]), .{
            .canary = s.canary,
            .is_extended = true,
            .stack_trace_size = s.stack_trace_size,

            .user_len = new_len,
            .user_align = alignment,
            .ra = ra,

            .prev_extended = false,
            .container = .fromLargeEntry(entry),
        });
        assert(entry.kind == .large_alloc);
        entry.* = .fromLargeAlloc(new_footer);
        return new_memory;
    }

    if (new_len < memory.len) {
        // Move the allocation forward to avoid bucket reuse

        const fixed_start = Bucket.fillAt(s, @ptrCast(f)) - AllocFooter.allocOffset(new_len);
        const moved_start = alignment.forward(fixed_start);
        if (moved_start != fixed_start or !f.isExtended()) {
            @branchHint(.unlikely);
            // For `moved_start != fixed_start`: the footer needs moved forward as well to
            // maintain the correct allocOffset.
            //
            // For `!f.isExtended()`: since the memory will no longer be directly after the
            // previous footer, the footer needs promoted to an extended one to encode the
            // location of the previous footer.
            if (!s.advanceBucketAlloc(f, @intCast(moved_start), true, alignment, new_len, ra)) {
                @branchHint(.unlikely);
                f.modify.setNone();
                return null;
            }
            const new_memory = Bucket.bytes(.of(s, @ptrCast(f)), s)[moved_start..][0..new_len];
            @memmove(new_memory, memory[0..new_memory.len]);
            return new_memory.ptr;
        }

        // The footer can be modified in place
        const b: *Bucket = .of(s, @ptrCast(f));
        f.extended().len = new_len;
        f.checksum = f.actualChecksum() ^ s.canary;
        captureStackTrace(f.allocTrace(s.stack_trace_size), ra);

        const new_memory = f.userMemory();
        @memmove(new_memory, memory[0..new_memory.len]);

        f.modify.setNone();
        b.alloc_count.fenceAcqRel();
        return new_memory.ptr;
    }

    if (s.growingResizeBucket(f, memory, alignment, new_len, ra)) {
        @branchHint(.likely);
        return memory.ptr;
    } else {
        f.modify.setNone();
        return null;
    }
}

const Smith = std.testing.Smith;

/// Shared between single-threaded and multi-threaded fuzzing.
const fuzz_probs = struct {
    const alignment: []const Smith.Weight = &.{
        .rangeAtMost(Alignment, .@"1", .@"16", 32), // ~75%
        .rangeAtMost(Alignment, .@"16", @fromBackingInt(@intCast(@bitSizeOf(usize) - 1)), 1),
        .value(Alignment, @fromBackingInt(@intCast(@bitSizeOf(usize) - 1)), 32), // More likely overflow cases
    };

    const eos: []const Smith.Weight = &.{
        // Very high false weight so that expanding allocation tables, OOM cases,
        // and multi-threaded consumer-producer cases get tested thoroughly.
        .value(bool, false, 255),
        .value(bool, true, 1),
    };

    fn generateFixedBufferOptions(smith: *Smith) FixedBuffer.Options {
        return .{
            .stack_trace_frames = smith.valueWeighted(u16, &.{
                .value(u16, 0, 1 << 18), // 4x - stack traces have no tested properties except I.B.
                .rangeAtMost(u16, 0, math.maxInt(u16), 1),
            }),
            // If set, it is aimed to allocate much fewer bytes since freeing becomes O(n).
            // Without this, it is O(1) since mem.Allocator is bypassed so there is no memsets
            // of the data.
            .check_write_after_free = smith.valueWeighted(bool, &.{
                .value(bool, false, 31),
                .value(bool, false, 1),
            }),
            .no_resize = smith.boolWeighted(1, 3),
            .canary = smith.value(u32),
        };
    }

    fn generateOptions(smith: *Smith) Options {
        @disableInstrumentation();

        const size_log2_weights: []const Smith.Weight = &.{
            .value(u5, 8, 1024), // 8x odds of below
            .rangeAtMost(u5, 8, 16, 16),
            .rangeAtMost(u5, 17, 31, 1), // 1/32 odds of above since these just OOM with the fixed buffer
        };

        const fixed_options = generateFixedBufferOptions(smith);
        return .{
            .stack_trace_frames = fixed_options.stack_trace_frames,
            .check_write_after_free = fixed_options.check_write_after_free,
            .no_resize = fixed_options.no_resize,
            .canary = fixed_options.canary,

            .block_size_log2 = smith.valueWeighted(u5, size_log2_weights),
            .bucket_size_log2 = smith.valueWeighted(u5, size_log2_weights),
        };
    }

    const Op = enum(u8) { alloc, free, resize, remap };
    fn generateOp(smith: *Smith, any_allocs: bool) Op {
        @disableInstrumentation();
        return if (any_allocs) smith.valueWeighted(Op, &.{
            .rangeAtMost(Op, .alloc, .free, 4),
            .rangeAtMost(Op, .resize, .remap, 1),
        }) else .alloc;
    }

    fn generateSplat(smith: *Smith) ?u8 {
        @disableInstrumentation();

        // Same rationale for `check_write_after_free`
        const n = smith.valueWeighted(u16, &.{
            .value(u16, 256, 256 * 31),
            .rangeAtMost(u16, 0, 255, 1),
        });
        return if (n == 256) null else @intCast(n);
    }

    fn generateLen(smith: *Smith, will_memset: bool) usize {
        @disableInstrumentation();

        // 1 << 24 indicates to generate an unweighted usize.
        // 1 << 25 indicates to provide a value relative to the maximum usize.
        const len = smith.valueWeightedWithHash(
            u32,
            if (!will_memset) comptime &.{
                // zig fmt: off
                .rangeLessThan(u32, 1      , 1 << 6 , 1 << 15), // 2^21 - 2^4 times below so 16x odds
                .rangeLessThan(u32, 1 <<  6, 1 << 17, 1      ), // 2^17 - 2^4 times below so 16x odds
                .value        (u32, 1 << 24,          1 << 12), // 2^12
                .value        (u32, 1 << 25,          1 << 12), // 2^12
                // zig fmt: on
            } else comptime &.{
                // zig fmt: off
                .rangeLessThan(u32, 1      , 1 <<  6, 1 << 17), // 2^23 - 2^6 times below so 64x odds
                .rangeLessThan(u32, 1 <<  6, 1 << 17, 1      ), // 2^17 - 2^6 times below so 64x odds
                .value        (u32, 1 << 24,          1 << 10), // 2^10
                .value        (u32, 1 << 25,          1 << 10), // 2^10
                // zig fmt: on
            },
            // Give the fuzzer different hashes when the weights used differ
            // so that it does not reuse values from other probabilities.
            if (!will_memset) 0x38a74424 else 0xec581ff0,
        );

        if (len == 1 << 24) return @max(1, smith.value(usize));
        if (len == 1 << 25) return @as(usize, math.maxInt(usize)) - smith.value(u16);
        return len;
    }

    fn checkSplat(splat: ?u8, bytes: []const u8) void {
        @disableInstrumentation();

        const byte = splat orelse return;
        for (bytes) |*b| if (b.* != byte) {
            panic("SafeAllocator corrupted allocation data at *{x}", .{@intFromPtr(b)});
        };
    }
};

const AnySafeAllocator = struct {
    interface: mem.Allocator,
    check_write_after_free: bool,
};

test "fuzz single threaded" {
    // This single threaded fuzz test has the following advantages:
    // * Higher throughput and deterministic, which helps the fuzzer.
    // * Easier debugging of single-threaded reproducable bugs.
    const testing_buf = try std.testing.allocator.alloc(u8, 65536);
    defer std.testing.allocator.free(testing_buf);
    const backing_buf = try std.testing.allocator.alloc(u8, 1 << 17);
    defer std.testing.allocator.free(backing_buf);
    try std.testing.fuzz(FuzzSingleThreadedContext{
        .testing_buf = testing_buf,
        .backing_buf = backing_buf,
    }, fuzzSingleThreaded, .{});
}

const FuzzSingleThreadedContext = struct {
    testing_buf: []u8,
    backing_buf: []u8,
};

/// Guarantees memory will not be reused.
const FuzzSingleThreadedAllocator = struct {
    gpa: mem.Allocator,
    smith: *std.testing.Smith,

    buf: []u8,
    fill: usize,
    allocs: std.MultiArrayList(AllocInfo),

    const AllocInfo = struct {
        ptr: [*]u8,
        len: usize,
        alignment: Alignment,
    };

    fn allocator(f: *FuzzSingleThreadedAllocator) mem.Allocator {
        @disableInstrumentation();
        return .{ .ptr = f, .vtable = &.{
            .alloc = FuzzSingleThreadedAllocator.alloc,
            .free = FuzzSingleThreadedAllocator.free,
            .resize = FuzzSingleThreadedAllocator.resize,
            .remap = FuzzSingleThreadedAllocator.remap,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        f.allocs.ensureUnusedCapacity(f.gpa, 1) catch return null;

        const ptr = f.allocInner(len, alignment) orelse return null;
        f.allocs.appendAssumeCapacity(.{
            .ptr = ptr,
            .len = len,
            .alignment = alignment,
        });
        return ptr;
    }

    fn allocInner(f: *FuzzSingleThreadedAllocator, len: usize, alignment: Alignment) ?[*]u8 {
        @disableInstrumentation();

        const start_addr = alignment.forward(@intFromPtr(f.buf[f.fill..].ptr));
        const start = @as([*]u8, @ptrFromInt(start_addr)) - f.buf.ptr;
        if (start +| len > f.buf.len or f.smith.boolWeighted(31, 1)) return null;
        f.fill = start + len;
        return f.buf[start..][0..len].ptr;
    }

    fn allocIndex(f: *FuzzSingleThreadedAllocator, memory: []u8, alignment: Alignment) usize {
        @disableInstrumentation();

        const allocs_slice = f.allocs.slice();
        const i = mem.findScalar([*]u8, allocs_slice.items(.ptr), memory.ptr) orelse panic(
            "invalid SafeAllocator free of {f}",
            .{FormatMemory{ .memory = memory, .alignment = alignment }},
        );
        const expected_len = allocs_slice.items(.len)[i];
        const expected_align = allocs_slice.items(.alignment)[i];
        if (memory.len != expected_len or allocs_slice.items(.alignment)[i] != expected_align) {
            panic("SafeAllocator free {f} mismatches alloc {f}", .{
                FormatMemory{ .memory = memory, .alignment = alignment },
                FormatMemory{ .memory = memory.ptr[0..expected_len], .alignment = expected_align },
            });
        }
        return i;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        f.allocs.swapRemove(f.allocIndex(memory, alignment));
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        const i = f.allocIndex(memory, alignment);

        const start = memory.ptr - f.buf.ptr;
        const old_end = start + memory.len;
        const new_end = start +| new_len;
        if (new_end > f.buf.len or f.smith.value(bool)) {
            return false;
        }

        if (new_len <= memory.len) {
            // The fill is not decreased so memory is not reused.
        } else if (f.fill == old_end) {
            f.fill = new_end;
        } else {
            return false;
        }
        f.allocs.items(.len)[i] = new_len;
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        if (f.smith.value(bool)) {
            const resized = FuzzSingleThreadedAllocator.resize(
                ctx,
                memory,
                alignment,
                new_len,
                undefined,
            );
            return if (resized) memory.ptr else null;
        }

        const i = f.allocIndex(memory, alignment);
        if (f.smith.value(bool)) return null;

        const new_ptr = f.allocInner(new_len, alignment) orelse return null;
        const copy_len = @min(memory.len, new_len);
        @memcpy(new_ptr[0..copy_len], memory[0..copy_len]);

        f.allocs.set(i, .{
            .ptr = new_ptr,
            .len = new_len,
            .alignment = alignment,
        });
        return new_ptr;
    }
};

fn fuzzSingleThreaded(ctx: FuzzSingleThreadedContext, smith: *Smith) !void {
    @disableInstrumentation();

    var gpa_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
    const gpa = gpa_instance.allocator();
    var backing_gpa_instance: FuzzSingleThreadedAllocator = .{
        .gpa = gpa,
        .smith = smith,

        .buf = ctx.backing_buf,
        .fill = 0,
        .allocs = .empty,
    };
    const backing_gpa = backing_gpa_instance.allocator();

    const options = fuzz_probs.generateOptions(smith);
    var s: SafeAllocator = .init(backing_gpa, options);
    const expected_leaks = try fuzzSingleThreadedInner(.{
        .interface = s.allocator(),
        .check_write_after_free = options.check_write_after_free,
    }, gpa, smith);
    try std.testing.expectEqual(expected_leaks, s.deinitLog(false));

    const leaks_slice = backing_gpa_instance.allocs.slice();
    for (0..leaks_slice.len) |i| {
        const leak = leaks_slice.get(i);
        std.log.err("SafeAllocator leaked {f}", .{FormatMemory{
            .memory = leak.ptr[0..leak.len],
            .alignment = leak.alignment,
        }});
    }
    try std.testing.expectEqual(0, leaks_slice.len); // no leaks
}

fn fuzzSingleThreadedInner(s: AnySafeAllocator, gpa: mem.Allocator, smith: *Smith) !usize {
    @disableInstrumentation();
    const no_ra: usize = 0;

    var allocs: std.MultiArrayList(struct {
        memory: []u8,
        alignment: Alignment,
        splat: ?u8,
    }) = .empty;
    var used_memory: std.ArrayList(struct {
        start: usize,
        end: usize,
    }) = .empty;

    while (!smith.eosWeighted(fuzz_probs.eos)) {
        const op = fuzz_probs.generateOp(smith, allocs.len != 0);
        const new_mem: []const u8, const old_mem: ?[]const u8 = new_alloc: switch (op) {
            .alloc => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                allocs.ensureUnusedCapacity(gpa, 1) catch break;

                const splat = fuzz_probs.generateSplat(smith);
                const will_memset = s.check_write_after_free or splat != null;
                const len = fuzz_probs.generateLen(smith, will_memset);
                const alignment = smith.valueWeighted(Alignment, fuzz_probs.alignment);

                const ptr = s.interface.rawAlloc(len, alignment, no_ra) orelse continue;
                if (!alignment.check(@intFromPtr(ptr))) @panic("bad returned alignment");
                const memory = ptr[0..len];
                if (splat) |b| @memset(memory, b);

                allocs.appendAssumeCapacity(.{
                    .memory = memory,
                    .alignment = alignment,
                    .splat = splat,
                });
                break :new_alloc .{ memory, null };
            },
            .free => {
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const alloc_info = allocs.get(i);
                allocs.swapRemove(i);

                fuzz_probs.checkSplat(alloc_info.splat, alloc_info.memory);
                s.interface.rawFree(alloc_info.memory, alloc_info.alignment, no_ra);
                continue;
            },
            .resize => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const allocs_slice = allocs.slice();

                const prev_alloc = allocs_slice.get(i);
                const old_len = prev_alloc.memory.len;

                const alloc_memory = &allocs_slice.items(.memory)[i];
                const splat = prev_alloc.splat;
                const will_memset = s.check_write_after_free or splat != null;

                const new_len = fuzz_probs.generateLen(smith, will_memset);
                if (!s.interface.rawResize(prev_alloc.memory, prev_alloc.alignment, new_len, no_ra)) {
                    fuzz_probs.checkSplat(prev_alloc.splat, prev_alloc.memory);
                    continue;
                }
                alloc_memory.len = new_len;

                fuzz_probs.checkSplat(prev_alloc.splat, alloc_memory.*[0..@min(old_len, new_len)]);
                if (splat) |b| @memset(alloc_memory.*[@min(old_len, new_len)..], b);

                break :new_alloc .{ alloc_memory.*, prev_alloc.memory };
            },
            .remap => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const allocs_slice = allocs.slice();

                const prev_alloc = allocs_slice.get(i);
                const old_len = prev_alloc.memory.len;

                const alloc_memory = &allocs_slice.items(.memory)[i];
                const alignment = prev_alloc.alignment;
                const splat = prev_alloc.splat;
                const will_memset = s.check_write_after_free or splat != null;

                const new_len = fuzz_probs.generateLen(smith, will_memset);
                const new_ptr = s.interface.rawRemap(
                    prev_alloc.memory,
                    prev_alloc.alignment,
                    new_len,
                    no_ra,
                ) orelse {
                    fuzz_probs.checkSplat(prev_alloc.splat, prev_alloc.memory);
                    continue;
                };
                alloc_memory.* = new_ptr[0..new_len];

                if (!alignment.check(@intFromPtr(new_ptr))) @panic("bad returned alignment");
                fuzz_probs.checkSplat(prev_alloc.splat, alloc_memory.*[0..@min(old_len, new_len)]);
                if (splat) |b| @memset(alloc_memory.*[@min(old_len, new_len)..], b);

                break :new_alloc .{ alloc_memory.*, prev_alloc.memory };
            },
        };

        const new_start = @intFromPtr(new_mem.ptr);
        const new_end = new_start + new_mem.len;
        const old_start = if (old_mem) |old| @intFromPtr(old.ptr) else 0;
        const old_end = new_start + if (old_mem) |old| old.len else 0;
        for (used_memory.items) |used| {
            if (old_start <= used.end and used.start <= old_end) {
                continue;
            }
            if (new_start <= used.end and used.start <= new_end) {
                panic(
                    "memory reuse between [addr: {x}, len: {}] and new [addr: {x}, len: {}]",
                    .{ used.start, used.end, new_start, new_end },
                );
            }
        }
        used_memory.appendAssumeCapacity(.{ .start = new_start, .end = new_end });
    }

    return allocs.len;
}

test "fuzz multi threaded" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const testing_buf = try std.testing.allocator.alloc(u8, 65536);
    defer std.testing.allocator.free(testing_buf);
    const backing_buf = try std.testing.allocator.alloc(u8, 1 << 17);
    defer std.testing.allocator.free(backing_buf);

    // `std.testing` instances are overwritten during `std.testing.fuzz` so
    // it is necessary to use our own io and gpa instances.
    var threaded_io: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    defer threaded_io.deinit();

    var ops: FuzzMultiThreadedContext.ThreadOps = .{
        .io = threaded_io.io(),
        .run = .{ .n = false },
        .running = undefined,

        .instance = undefined,
        .items = undefined,
        .i = undefined,
    };

    var group: std.Io.Group = .init;
    defer group.cancel(ops.io);
    for (0..FuzzMultiThreadedContext.n_threads) |_| {
        try group.concurrent(ops.io, fuzzMultiThreadedWorker, .{&ops});
    }

    try std.testing.fuzz(FuzzMultiThreadedContext{
        .testing_buf = testing_buf,
        .backing_buf = backing_buf,
        .ops = &ops,
    }, fuzzMultiThreaded, .{});
}

const FuzzMultiThreadedContext = struct {
    testing_buf: []u8,
    backing_buf: []u8,
    ops: *ThreadOps,

    const n_threads = 4;

    const ThreadOps = struct {
        io: std.Io,
        /// Switches between two values for each time a run starts.
        run: Run,
        /// While this can be calculated as `n_threads - (i -| ops.items.len)`,
        /// this also serves as `.release` synchronization for each thread.
        running: u32,

        instance: mem.Allocator,
        items: []Op,
        i: usize,

        const Run = packed struct(u32) {
            n: bool,
            pad: u31 = 0,

            fn wait(ptr: *Run, val: Run, io: std.Io) error{Canceled}!void {
                assert(val.pad == 0);
                while (true) {
                    // This cannot load a previous value since this thread previously loaded the
                    // latest value.
                    const prev = @atomicLoad(Run, ptr, .acquire);
                    assert(prev.pad == 0);
                    if (prev == val) break;

                    try io.futexWait(Run, ptr, prev);
                }
            }

            fn next(r: Run) Run {
                assert(r.pad == 0);
                return .{ .n = !r.n };
            }
        };

        const Op = union(fuzz_probs.Op) {
            alloc: struct {
                len: usize,
                alignment: Alignment,

                splat: ?u8,
                /// Not embeded directly in the struct as a workaround for tsan since a
                /// switch directly on `Op` loads the entire value non-atomically.
                result: *MemoryDependency,
            },
            free: struct {
                memory: *MemoryDependency,
                alignment: Alignment,

                splat: ?u8,
            },
            resize: Realloc,
            remap: Realloc,

            const Realloc = struct {
                memory: *MemoryDependency,
                alignment: Alignment,
                new_len: usize,

                splat: ?u8,
                /// Not embeded directly in the struct as a workaround for tsan since a
                /// switch directly on `Op` loads the entire value non-atomically.
                result: *MemoryDependency,
            };

            const MemoryDependency = struct {
                ready: std.Io.Event,
                /// Null if the memory failed to be allocated
                memory: ?[]u8,

                const init: MemoryDependency = .{
                    .ready = .unset,
                    .memory = undefined,
                };

                fn get(dep: *MemoryDependency, io: std.Io) ?[]u8 {
                    dep.ready.waitUncancelable(io);
                    return dep.memory;
                }
            };
        };

        const Generated = struct {
            items: []Op,
            results: []Op.MemoryDependency,
            leaked_allocs: []Alloc,
            expected_remaps: usize,

            const Alloc = struct {
                memory: *Op.MemoryDependency,
                alignment: Alignment,
                splat: ?u8,
            };
        };
    };
};

/// Guarantees memory will not be reused.
const FuzzMultiThreadedAllocator = struct {
    gpa: mem.Allocator,

    fill: usize,
    active_allocs: usize,
    fail_i: usize,
    fixed_remap_i: usize,

    // The below are assumed to be externally synchronized
    // i.e. each thread has an acquire fence before **first** using the allocator
    buf: []u8,
    fails: []const bool,
    fixed_remaps: []const bool,

    fn allocator(f: *FuzzMultiThreadedAllocator) mem.Allocator {
        @disableInstrumentation();
        return .{ .ptr = f, .vtable = &.{
            .alloc = FuzzMultiThreadedAllocator.alloc,
            .free = FuzzMultiThreadedAllocator.free,
            .resize = FuzzMultiThreadedAllocator.resize,
            .remap = FuzzMultiThreadedAllocator.remap,
        } };
    }

    fn maybeFail(f: *FuzzMultiThreadedAllocator) bool {
        @disableInstrumentation();
        const i = @atomicRmw(usize, &f.fail_i, .Add, 1, .monotonic);
        return i < f.fails.len and f.fails[i];
    }

    fn maybeFixedRemap(f: *FuzzMultiThreadedAllocator) bool {
        @disableInstrumentation();
        const i = @atomicRmw(usize, &f.fixed_remap_i, .Add, 1, .monotonic);
        return i < f.fixed_remaps.len and f.fixed_remaps[i];
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const memory = f.allocInner(len, alignment) orelse return null;
        _ = @atomicRmw(usize, &f.active_allocs, .Add, 1, .monotonic);
        return memory;
    }

    fn allocInner(f: *FuzzMultiThreadedAllocator, len: usize, alignment: Alignment) ?[*]u8 {
        var prev_fill = @atomicLoad(usize, &f.fill, .monotonic);
        var start: usize = undefined;
        while (true) {
            const start_addr = alignment.forward(@intFromPtr(f.buf[prev_fill..].ptr));
            start = @as([*]u8, @ptrFromInt(start_addr)) - f.buf.ptr;
            if (start +| len > f.buf.len or f.maybeFail()) return null;
            prev_fill = @cmpxchgStrong(
                usize,
                &f.fill,
                prev_fill,
                start + len,
                .monotonic,
                .monotonic,
            ) orelse {
                @branchHint(.likely);
                break;
            };
        }
        return f.buf[start..][0..len].ptr;
    }

    fn free(ctx: *anyopaque, _: []u8, _: Alignment, _: usize) void {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        assert(@atomicRmw(usize, &f.active_allocs, .Sub, 1, .monotonic) != 0);
    }

    fn resize(ctx: *anyopaque, memory: []u8, _: Alignment, new_len: usize, _: usize) bool {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const start = memory.ptr - f.buf.ptr;
        const old_end = start + memory.len;
        const new_end = start +| new_len;
        if (new_end > f.buf.len or f.maybeFail()) {
            return false;
        }

        if (new_len <= memory.len) {
            // The fill is not decreased so memory is not reused.
            return true;
        }

        return @cmpxchgStrong(usize, &f.fill, old_end, new_end, .monotonic, .monotonic) == null;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        @disableInstrumentation();

        if (maybeFixedRemap(@ptrCast(@alignCast(ctx)))) {
            const resized = FuzzMultiThreadedAllocator.resize(
                ctx,
                memory,
                alignment,
                new_len,
                undefined,
            );
            return if (resized) memory.ptr else null;
        }

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const new_ptr = f.allocInner(new_len, alignment) orelse return null;
        const copy_len = @min(memory.len, new_len);
        @memcpy(new_ptr[0..copy_len], memory[0..copy_len]);
        return new_ptr;
    }
};

fn fuzzMultiThreaded(ctx: FuzzMultiThreadedContext, smith: *Smith) !void {
    @disableInstrumentation();

    var arena_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
    const arena = arena_instance.allocator();
    const options = fuzz_probs.generateOptions(smith);
    const ops = try fuzzMultiThreadedGenerateOps(arena, smith, options.check_write_after_free);

    const fails: []bool = arena.alloc(bool, ops.items.len * 2 + smith.value(u8)) catch &.{};
    const fixed_remaps: []bool = arena.alloc(bool, ops.expected_remaps + smith.value(u8)) catch &.{};
    for (fails) |*f| f.* = smith.boolWeighted(31, 1);
    for (fixed_remaps) |*f| f.* = smith.value(bool);
    var backing_gpa_instance: FuzzMultiThreadedAllocator = .{
        .gpa = arena,

        .fill = 0,
        .active_allocs = 0,
        .fail_i = 0,
        .fixed_remap_i = 0,

        .buf = ctx.backing_buf,
        .fails = fails,
        .fixed_remaps = fixed_remaps,
    };
    const backing_gpa = backing_gpa_instance.allocator();
    var s: SafeAllocator = .init(backing_gpa, options);
    ctx.ops.instance = s.allocator();

    const expected_leaks = try fuzzMultiThreadedRun(ctx.ops, ops);
    try std.testing.expectEqual(expected_leaks, s.deinitLog(false));
    try std.testing.expectEqual(0, backing_gpa_instance.active_allocs); // no leaks
}

/// Returns the number of expected remaps
fn fuzzMultiThreadedGenerateOps(
    arena: mem.Allocator,
    smith: *Smith,
    check_write_after_free: bool,
) !FuzzMultiThreadedContext.ThreadOps.Generated {
    @disableInstrumentation();
    const Op = FuzzMultiThreadedContext.ThreadOps.Op;
    const Generated = FuzzMultiThreadedContext.ThreadOps.Generated;

    var n_ops: u32 = 0;
    while (!smith.eosWeighted(fuzz_probs.eos)) n_ops += 1;
    var g: Generated = .{
        .items = arena.alloc(Op, n_ops) catch return error.SkipZigTest,
        .results = arena.alloc(Op.MemoryDependency, n_ops) catch return error.SkipZigTest,
        .leaked_allocs = arena.alloc(Generated.Alloc, n_ops) catch return error.SkipZigTest,
        .expected_remaps = 0,
    };
    @memset(g.results, .init);

    var n_allocs: usize = 0;
    for (g.items, g.results) |*op, *result| switch (fuzz_probs.generateOp(smith, n_allocs != 0)) {
        .alloc => {
            const splat = fuzz_probs.generateSplat(smith);
            const will_memset = check_write_after_free or splat != null;
            op.* = .{ .alloc = .{
                .len = fuzz_probs.generateLen(smith, will_memset),
                .alignment = smith.valueWeighted(Alignment, fuzz_probs.alignment),

                .splat = splat,
                .result = result,
            } };
            g.leaked_allocs[n_allocs] = .{
                .memory = result,
                .alignment = op.alloc.alignment,
                .splat = splat,
            };
            n_allocs += 1;
        },
        .free => {
            const i = smith.index(n_allocs);
            op.* = .{ .free = .{
                .memory = g.leaked_allocs[i].memory,
                .alignment = g.leaked_allocs[i].alignment,

                .splat = g.leaked_allocs[i].splat,
            } };

            n_allocs -= 1;
            g.leaked_allocs[i] = g.leaked_allocs[n_allocs];
        },
        .resize, .remap => |kind| {
            op.* = switch (kind) {
                .remap => .{ .remap = undefined },
                .resize => .{ .resize = undefined },
                else => unreachable,
            };
            const realloc = switch (kind) {
                .remap => &op.remap,
                .resize => &op.resize,
                else => unreachable,
            };
            g.expected_remaps += @intFromBool(kind == .remap);

            const i = smith.index(n_allocs);
            realloc.* = .{
                .memory = g.leaked_allocs[i].memory,
                .alignment = g.leaked_allocs[i].alignment,
                .new_len = fuzz_probs.generateLen(smith, check_write_after_free),

                .splat = g.leaked_allocs[i].splat,
                .result = result,
            };
            g.leaked_allocs[i].memory = result;
        },
    };

    g.leaked_allocs = g.leaked_allocs[0..n_allocs];
    return g;
}

fn fuzzMultiThreadedRun(
    ops: *FuzzMultiThreadedContext.ThreadOps,
    g: FuzzMultiThreadedContext.ThreadOps.Generated,
) !usize {
    ops.i = 0;
    ops.items = g.items;
    ops.running = FuzzMultiThreadedContext.n_threads;
    // Loading `ops.run` non-atomically is fine since this is the only thread that writes to it.
    @atomicStore(FuzzMultiThreadedContext.ThreadOps.Run, &ops.run, ops.run.next(), .release);
    ops.io.futexWake(FuzzMultiThreadedContext.ThreadOps.Run, &ops.run, math.maxInt(u32));
    while (true) {
        const prev_running = @atomicLoad(u32, &ops.running, .acquire);
        if (prev_running == 0) break;
        ops.io.futexWaitUncancelable(u32, &ops.running, prev_running);
    }

    var expected_leaks = g.leaked_allocs.len;
    for (g.leaked_allocs) |a| {
        expected_leaks -= @intFromBool(a.memory.memory == null);
    }
    return expected_leaks;
}

fn fuzzMultiThreadedWorker(ops: *FuzzMultiThreadedContext.ThreadOps) error{Canceled}!void {
    const no_ra: usize = 0;
    var next_run: FuzzMultiThreadedContext.ThreadOps.Run = .{ .n = true };
    while (true) {
        try ops.run.wait(next_run, ops.io);
        next_run = .next(next_run);

        while (true) {
            const i = @atomicRmw(usize, &ops.i, .Add, 1, .monotonic);
            if (i >= ops.items.len) {
                // `.acq_rel` is necessary since acquire loads only synchronize with the thread
                // which the read value was written from, not all previous writer threads.
                const prev_rem = @atomicRmw(u32, &ops.running, .Sub, 1, .acq_rel);
                if (prev_rem - 1 == 0) {
                    ops.io.futexWake(u32, &ops.running, 1);
                }
                break;
            }

            switch (ops.items[i]) {
                .alloc => |call| {
                    const alloc_ptr = ops.instance.rawAlloc(call.len, call.alignment, no_ra);
                    if (alloc_ptr) |memory_ptr| {
                        const memory = memory_ptr[0..call.len];
                        if (call.splat) |b| @memset(memory, b);
                        call.result.memory = memory;
                    } else {
                        call.result.memory = null;
                    }
                    call.result.ready.set(ops.io);
                },
                .free => |call| {
                    const memory = call.memory.get(ops.io) orelse continue;
                    fuzz_probs.checkSplat(call.splat, memory);
                    ops.instance.rawFree(memory, call.alignment, no_ra);
                },
                .resize, .remap => |call, kind| {
                    const memory = call.memory.get(ops.io) orelse {
                        call.result.memory = null;
                        call.result.ready.set(ops.io);
                        continue;
                    };
                    const new_memory: []u8 = switch (kind) {
                        .remap => if (ops.instance.rawRemap(
                            memory,
                            call.alignment,
                            call.new_len,
                            no_ra,
                        )) |new_ptr| new_ptr[0..call.new_len] else memory,
                        .resize => if (ops.instance.rawResize(
                            memory,
                            call.alignment,
                            call.new_len,
                            no_ra,
                        )) memory.ptr[0..call.new_len] else memory,
                        else => unreachable,
                    };

                    const old_len = memory.len;
                    const new_len = new_memory.len;
                    fuzz_probs.checkSplat(call.splat, new_memory[0..@min(old_len, new_len)]);
                    if (call.splat) |b| @memset(new_memory[@min(old_len, new_len)..], b);

                    call.result.memory = new_memory;
                    call.result.ready.set(ops.io);
                },
            }
        }
    }
}

/// Provides the same gaurauntees as `SafeAllocator`.
///
/// Uses the same allocation metadata format as `SafeAllocator`, so
/// canary mismatches are still caught and give useful information.
pub const FixedBuffer = struct {
    const scoped_log = std.log.scoped(.SafeFixedBufferAllocator);

    pub const Options = struct {
        const is_debug = @import("builtin").mode == .debug;

        stack_trace_frames: usize = if (is_debug and std.debug.sys_can_stack_trace) 7 else 0,
        check_write_after_free: bool = is_debug,
        no_resize: bool = is_debug,
        /// A unique value used to check that allocations created by other
        /// `SafeAllocator` instances are not passed to this one.
        ///
        /// This is only useful to change if `buf` was allocated inside another
        /// `SafeAllocator` instance as otherwise `buf` should be unique.
        canary: u32 = 0x4818d972,
    };

    // This is treated very similarily to `Bucket`.
    buf: []align(8) u8,
    fill: Fill,

    /// In `usize`s
    stack_trace_size: usize,
    check_write_after_free: bool,
    no_resize: bool,
    canary: u32,

    const Fill = packed struct(usize) {
        last_is_extended: bool,
        zero: u2 = 0,
        hi: @Int(.unsigned, @bitSizeOf(usize) - 3),

        fn index(f: Fill) usize {
            assert(f.zero == 0);
            return @as(usize, f.hi) << 3;
        }
    };

    pub fn init(buf: []align(8) u8, options: FixedBuffer.Options) FixedBuffer {
        return .{
            .buf = buf,
            .fill = .{ .hi = 0, .last_is_extended = false },

            .stack_trace_size = options.stack_trace_frames +
                @intFromBool(options.stack_trace_frames != 0),
            .check_write_after_free = options.check_write_after_free,
            .no_resize = options.no_resize,
            .canary = options.canary,
        };
    }

    /// Returns the number of leaks
    pub fn deinit(s: *FixedBuffer) usize {
        return s.deinitLog(true);
    }

    /// Same as `deinit`, expect if `log` is `false`, it will not log leaks.
    pub fn deinitLog(s: *FixedBuffer, log: bool) usize {
        var leaks: usize = 0;
        var maybe_footer = s.lastAlloc(s.fill);
        while (maybe_footer) |footer| {
            const modify = @atomicRmw(
                AllocFooter.Modify,
                &footer.modify,
                .Xchg,
                undefined,
                .monotonic,
            ).storedXor(&footer.modify);

            const bad_modify = modify != .none and modify != .freed;
            if (bad_modify or footer.actualChecksum() != footer.checksum ^ s.canary) {
                panic("corrupted footer metadata at *{x}", .{@intFromPtr(&footer)});
            }

            switch (modify) {
                .none => {
                    leaks += 1;
                    if (log) FixedBuffer.scoped_log.err("leaked {f} allocated at: {f}", .{
                        FormatMemory{
                            .memory = footer.userMemory(),
                            .alignment = footer.userAlign(),
                        },
                        formatStackTrace(footer.allocTrace(s.stack_trace_size)),
                    });
                },
                .freed => if (s.check_write_after_free) checkFreed(footer, s.stack_trace_size),
                else => unreachable,
            }

            maybe_footer = s.allocFooterPrev(footer);
        }
        return leaks;
    }

    /// Returned allocator is thread-safe
    pub fn allocator(s: *FixedBuffer) mem.Allocator {
        return .{ .ptr = s, .vtable = &FixedBuffer.vtable };
    }

    fn checkOwnedMemory(
        s: *FixedBuffer,
        memory: []u8,
        alignment: Alignment,
        m: AllocFooter.Modify,
    ) void {
        if (@intFromPtr(memory.ptr) < @intFromPtr(s.buf.ptr) or
            @intFromPtr(memory.ptr) + memory.len > @intFromPtr(s.buf.ptr) + s.buf.len)
        {
            panic("{s} of invalid memory {f}", .{
                m.opName(),
                @as(FormatMemory, .{ .memory = memory, .alignment = alignment }),
            });
        }
    }

    fn allocFooterBefore(s: *FixedBuffer, i: usize, is_extended: bool) ?*AllocFooter {
        if (i == 0) return null;
        const off = i - AllocFooter.lenBucket(is_extended, s.stack_trace_size);
        return @ptrCast(@alignCast(s.buf[off..]));
    }

    fn allocFooterPrev(s: *FixedBuffer, f: *AllocFooter) ?*AllocFooter {
        if (f.isExtended()) return f.extended().container.toBucketPrev();
        return s.allocFooterBefore(f.userMemory().ptr - s.buf.ptr, f.data.prev_extended);
    }

    fn lastAlloc(s: *FixedBuffer, fill: Fill) ?*AllocFooter {
        return s.allocFooterBefore(fill.index(), fill.last_is_extended);
    }

    fn growingResize(
        s: *FixedBuffer,
        f: *AllocFooter,
        memory: []const u8,
        alignment: Alignment,
        new_len: usize,
        ra: usize,
    ) bool {
        assert(new_len >= memory.len);
        return s.advanceAlloc(f, memory.ptr - s.buf.ptr, false, alignment, new_len, ra);
    }

    fn advanceAlloc(
        s: *FixedBuffer,
        old: *AllocFooter,
        new_start: usize,
        start_moved: bool,
        alignment: Alignment,
        new_len: usize,
        ra: usize,
    ) bool {
        const old_is_extended = old.isExtended();
        const old_footer_len = AllocFooter.lenBucket(old_is_extended, s.stack_trace_size);
        const old_fill = @intFromPtr(old) - @intFromPtr(s.buf.ptr) + old_footer_len;

        const new_is_extended = old_is_extended or start_moved or
            AllocFooter.requiresExtended(new_len, alignment);
        const new_footer_len = AllocFooter.lenBucket(new_is_extended, s.stack_trace_size);
        const new_footer_off = AllocFooter.allocOffsetOrOom(new_len) catch return false;
        const new_fill = addOrOom(new_start + new_footer_len, new_footer_off) catch return false;

        assert(old_fill <= new_fill);
        if (new_fill > s.buf.len) {
            return false;
        }

        if (old_fill == new_fill or @cmpxchgStrong(
            Fill,
            &s.fill,
            .{ .last_is_extended = old_is_extended, .hi = @intCast(@shrExact(old_fill, 3)) },
            .{ .last_is_extended = new_is_extended, .hi = @intCast(@shrExact(new_fill, 3)) },
            .monotonic,
            .monotonic,
        ) != null) {
            return false;
        }

        _ = AllocFooter.populate(@alignCast(s.buf[new_start..new_fill]), .{
            .canary = s.canary,
            .is_extended = new_is_extended,
            .stack_trace_size = s.stack_trace_size,

            .user_len = new_len,
            .user_align = alignment,
            .ra = ra,

            .prev_extended = old.data.prev_extended,
            .container = .fromBucketPrev(s.allocFooterPrev(old)),
        });
        return true;
    }

    const vtable: mem.Allocator.VTable = .{
        .alloc = FixedBuffer.alloc,
        .free = FixedBuffer.free,
        .resize = FixedBuffer.resize,
        .remap = FixedBuffer.remap,
    };

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
        const s: *FixedBuffer = @ptrCast(@alignCast(ctx));

        const is_extended = AllocFooter.requiresExtended(len, alignment);
        const alloc_len = AllocFooter.allocLenBucketOrOom(
            len,
            is_extended,
            s.stack_trace_size,
        ) catch return null;
        const alloc_align = AllocFooter.allocAlign(alignment);

        var prev_fill = @atomicLoad(Fill, &s.fill, .monotonic);
        var start: usize = undefined;
        var end: usize = undefined;
        while (true) {
            const addr = alignForwardOrOom(
                alloc_align,
                @intFromPtr(s.buf.ptr) + prev_fill.index(),
            ) catch return null;
            start = addr - @intFromPtr(s.buf.ptr);
            end = math.add(usize, start, alloc_len) catch return null;
            if (end > s.buf.len) return null;

            prev_fill = @cmpxchgWeak(
                Fill,
                &s.fill,
                prev_fill,
                .{ .last_is_extended = is_extended, .hi = @intCast(@shrExact(end, 3)) },
                .monotonic,
                .monotonic,
            ) orelse {
                @branchHint(.likely);
                break;
            };
        }

        const memory = s.buf[start..end];
        _ = AllocFooter.populate(@alignCast(memory), .{
            .canary = s.canary,
            .is_extended = is_extended,
            .stack_trace_size = s.stack_trace_size,

            .user_len = len,
            .user_align = alignment,
            .ra = ra,

            .prev_extended = prev_fill.last_is_extended,
            .container = .fromBucketPrev(s.lastAlloc(prev_fill)),
        });

        return memory.ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
        const s: *FixedBuffer = @ptrCast(@alignCast(ctx));
        s.checkOwnedMemory(memory, alignment, .freed);

        const f: *AllocFooter = .of(memory);
        f.startModify(
            .freed,
            .{ .memory = memory, .alignment = alignment },
            s.canary,
            s.stack_trace_size,
        );

        if (s.check_write_after_free) overwriteFreed(memory);
        captureStackTrace(f.freeTrace(s.stack_trace_size), ra);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
        const s: *FixedBuffer = @ptrCast(@alignCast(ctx));
        s.checkOwnedMemory(memory, alignment, .freed);

        const f: *AllocFooter = .of(memory);
        f.startModify(
            .resized,
            .{ .memory = memory, .alignment = alignment },
            s.canary,
            s.stack_trace_size,
        );

        if (s.no_resize) {
            f.modify.setNone();
            return false;
        }

        if (new_len < memory.len) {
            // Resize shrinks are disallowed in all cases since the linked list would be broken.
            // Even if this footer is the final one, the fill value would need decreased which
            // would allow memory to be reused.
            f.modify.setNone();
            return false;
        }

        if (s.growingResize(f, memory, alignment, new_len, ra)) {
            @branchHint(.likely);
            return true;
        } else {
            f.modify.setNone();
            return false;
        }
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const s: *FixedBuffer = @ptrCast(@alignCast(ctx));
        s.checkOwnedMemory(memory, alignment, .freed);

        const f: *AllocFooter = .of(memory);
        f.startModify(
            .resized,
            .{ .memory = memory, .alignment = alignment },
            s.canary,
            s.stack_trace_size,
        );

        if (s.no_resize) {
            f.modify.setNone();
            return null;
        }

        if (new_len < memory.len) {
            // Move the allocation forward to avoid bucket reuse

            const fixed_start_addr = @intFromPtr(f) - AllocFooter.allocOffset(new_len);
            const moved_start_addr = alignForwardOrOom(alignment, fixed_start_addr) catch return null;
            if (moved_start_addr != fixed_start_addr or !f.isExtended()) {
                @branchHint(.unlikely);
                // For `moved_start_addr != fixed_start_addr`: the footer needs moved forward as
                // well to maintain the correct allocOffset.
                //
                // For `!f.isExtended()`: since the memory will no longer be directly after the
                // previous footer, the footer needs promoted to an extended one to encode the
                // location of the previous footer.
                const moved_start = moved_start_addr - @intFromPtr(s.buf.ptr);
                if (!s.advanceAlloc(f, moved_start, true, alignment, new_len, ra)) {
                    @branchHint(.unlikely);
                    f.modify.setNone();
                    return null;
                }
                const new_memory = s.buf[moved_start..][0..new_len];
                @memmove(new_memory, memory[0..new_memory.len]);
                return new_memory.ptr;
            }

            // The footer can be modified in place
            f.extended().len = new_len;
            f.checksum = f.actualChecksum() ^ s.canary;
            captureStackTrace(f.allocTrace(s.stack_trace_size), ra);

            const new_memory = f.userMemory();
            @memmove(new_memory, memory[0..new_memory.len]);

            f.modify.setNone();
            return new_memory.ptr;
        }

        if (s.growingResize(f, memory, alignment, new_len, ra)) {
            @branchHint(.likely);
            return memory.ptr;
        } else {
            f.modify.setNone();
            return null;
        }
    }

    test "fuzz single threaded" {
        // This single threaded fuzz test has the following advantages:
        // * Higher throughput and deterministic, which helps the fuzzer.
        // * Easier debugging of single-threaded reproducable bugs.
        const testing_buf = try std.testing.allocator.alloc(u8, 65536);
        defer std.testing.allocator.free(testing_buf);
        const backing_buf = try std.testing.allocator.alignedAlloc(u8, .@"8", 1 << 17);
        defer std.testing.allocator.free(backing_buf);
        try std.testing.fuzz(FuzzSingleThreadedContext{
            .testing_buf = testing_buf,
            .backing_buf = backing_buf,
        }, FixedBuffer.fuzzSingleThreaded, .{});
    }

    fn fuzzSingleThreaded(ctx: FuzzSingleThreadedContext, smith: *Smith) !void {
        @disableInstrumentation();

        var gpa_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
        const gpa = gpa_instance.allocator();

        const options = fuzz_probs.generateFixedBufferOptions(smith);
        const buf_len = smith.index(ctx.backing_buf.len);
        var s: FixedBuffer = .init(@alignCast(ctx.backing_buf[0..buf_len]), options);
        const expected_leaks = try fuzzSingleThreadedInner(.{
            .interface = s.allocator(),
            .check_write_after_free = options.check_write_after_free,
        }, gpa, smith);
        try std.testing.expectEqual(expected_leaks, s.deinitLog(false));
    }

    test "fuzz multi threaded" {
        if (@import("builtin").single_threaded) return error.SkipZigTest;

        const testing_buf = try std.testing.allocator.alloc(u8, 65536);
        defer std.testing.allocator.free(testing_buf);
        const backing_buf = try std.testing.allocator.alignedAlloc(u8, .@"8", 1 << 17);
        defer std.testing.allocator.free(backing_buf);

        // `std.testing` instances are overwritten during `std.testing.fuzz` so
        // it is necessary to use our own io and gpa instances.
        var threaded_io: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
        defer threaded_io.deinit();

        var ops: FuzzMultiThreadedContext.ThreadOps = .{
            .io = threaded_io.io(),
            .run = .{ .n = false },
            .running = undefined,

            .instance = undefined,
            .items = undefined,
            .i = undefined,
        };

        var group: std.Io.Group = .init;
        defer group.cancel(ops.io);
        for (0..FuzzMultiThreadedContext.n_threads) |_| {
            try group.concurrent(ops.io, fuzzMultiThreadedWorker, .{&ops});
        }

        try std.testing.fuzz(FuzzMultiThreadedContext{
            .testing_buf = testing_buf,
            .backing_buf = backing_buf,
            .ops = &ops,
        }, FixedBuffer.fuzzMultiThreaded, .{});
    }

    fn fuzzMultiThreaded(ctx: FuzzMultiThreadedContext, smith: *Smith) !void {
        @disableInstrumentation();

        var arena_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
        const arena = arena_instance.allocator();
        const options = fuzz_probs.generateFixedBufferOptions(smith);
        const ops = try fuzzMultiThreadedGenerateOps(arena, smith, options.check_write_after_free);

        const buf_len = smith.index(ctx.backing_buf.len);
        var s: FixedBuffer = .init(@alignCast(ctx.backing_buf[0..buf_len]), options);
        ctx.ops.instance = s.allocator();

        const expected_leaks = try fuzzMultiThreadedRun(ctx.ops, ops);
        try std.testing.expectEqual(expected_leaks, s.deinitLog(false));
    }
};

test {
    _ = FixedBuffer;
}
