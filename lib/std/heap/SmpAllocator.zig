//! An allocator that is designed for ReleaseFast optimization mode, with
//! multi-threading enabled.
//!
//! This allocator is a singleton; it uses global state and only one should be
//! instantiated for the entire process.
//!
//! ## Basic Design
//!
//! Each thread gets a separate freelist, however, the data must be recoverable
//! when the thread exits. We do not directly learn when a thread exits, so
//! occasionally, one thread must attempt to reclaim another thread's
//! resources.
//!
//! Above a certain size, those allocations are memory mapped directly, with no
//! storage of allocation metadata. This works because the implementation
//! refuses resizes that would move an allocation from small category to large
//! category or vice versa.
//!
//! Each allocator operation checks the thread identifier from a threadlocal
//! variable to find out which metadata in the global state to access, and
//! attempts to grab its lock. This will usually succeed without contention,
//! unless another thread has been assigned the same id. In the case of such
//! contention, the thread moves on to the next thread metadata slot and
//! repeats the process of attempting to obtain the lock.
//!
//! By limiting the thread-local metadata array to the same number as the CPU
//! count, ensures that as threads are created and destroyed, they cycle
//! through the full set of freelists.
//!
//! `free` usually doesn't push to the per-thread freelists directly, but to a
//! deferred per-slab freelist. Once in a while these per-slab lists are pushed
//! to the per-thread ones in their entirety. This ensures that contention
//! between parallel `free` calls remains relatively low and promotes reuse of
//! freed slots as the deferred freelists are always eventually pushed back to
//! the per-thread states they originated from.
const SmpAllocator = @This();

const builtin = @import("builtin");

const std = @import("../std.zig");
const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const PageAllocator = std.heap.PageAllocator;

cpu_count: std.atomic.Value(u32),
threads: [max_thread_count]Thread,

var global: SmpAllocator = .{
    .cpu_count = .init(0),
    .threads = @splat(.{}),
};
threadlocal var thread_index: u32 = 0;

const max_thread_count = 128;
const min_slab_len: usize = @max(std.heap.page_size_max, 64 * 1024);
/// Because of storing free list pointers, the minimum size class is 3.
const min_class = math.log2(@sizeOf(usize));
const size_class_count = math.log2(min_slab_len) - min_class;
/// Before mapping a fresh page, `alloc` will rotate this many times.
const max_alloc_search = 4;
/// If one over this number of a slab's total slots are pending frees,
/// the next `free` call will reap the pending freelist of that slab.
const reap_threshold_divisor = 32;

const Thread = struct {
    /// Avoid false sharing.
    _: void align(std.atomic.cache_line) = {},
    /// Protects the state in this struct (per-thread state).
    ///
    /// Threads lock this before accessing their own state in order
    /// to support freelist reclamation.
    /// To make `free` always succeed, the freelists can always be
    /// pushed to. Popping from them requires holding this lock to
    /// avoid ABA problems.
    mutex: std.atomic.Mutex = .unlocked,
    next_addrs: [size_class_count]usize = @splat(0),
    /// For each size class, points to the freed pointer.
    frees: [size_class_count]std.atomic.Value(usize) = @splat(.init(0)),
};

const Slab = struct {
    _: void align(std.atomic.cache_line) = {},
    owner_index: u32,
    pending_count: std.atomic.Value(u32),
    pending_frees: std.atomic.Value(usize),
};

fn getCpuCount() u32 {
    const cpu_count = global.cpu_count.load(.unordered);
    if (cpu_count != 0) return cpu_count;
    const n: u32 = @min(std.Thread.getCpuCount() catch max_thread_count, max_thread_count);
    return if (global.cpu_count.cmpxchgStrong(0, n, .monotonic, .monotonic)) |other| other else n;
}

pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

comptime {
    assert(!builtin.single_threaded); // you're holding it wrong
}

fn alloc(context: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    _ = context;
    _ = ra;
    const class = sizeClassIndex(len, alignment);
    if (class >= size_class_count) {
        @branchHint(.unlikely);
        return PageAllocator.map(len, alignment);
    }

    const slot_size = slotSize(class);
    const slab_len = slabLen(slot_size);
    assert(slab_len % slot_size == 0);

    for (0..1 + max_alloc_search) |search_count| {
        const t: *Thread = t: {
            var index = thread_index;
            if (search_count == 0) {
                const t = &global.threads[index];
                if (t.mutex.tryLock()) {
                    break :t t;
                }
            }
            const cpu_count = getCpuCount();
            assert(cpu_count != 0);
            for (0..cpu_count) |_| {
                index = (index + 1) % cpu_count;
                const t = &global.threads[index];
                if (t.mutex.tryLock()) {
                    thread_index = index;
                    break :t t;
                }
            }
            continue;
        };
        defer t.mutex.unlock();

        var top_free_ptr = t.frees[class].load(.acquire);
        while (top_free_ptr != 0) {
            const node: *usize = @ptrFromInt(top_free_ptr);
            if (t.frees[class].cmpxchgWeak(
                @intFromPtr(node),
                node.*,
                .acquire,
                .acquire,
            )) |new_free_ptr| {
                top_free_ptr = new_free_ptr;
            } else {
                return @ptrFromInt(top_free_ptr);
            }
        }

        const next_addr = t.next_addrs[class];
        if (next_addr % slab_len != 0) {
            @branchHint(.likely);
            t.next_addrs[class] = next_addr + slot_size;
            return @ptrFromInt(next_addr);
        }
    } else {
        @branchHint(.unlikely);

        const slab: *Slab = @ptrCast(@alignCast(PageAllocator.map(slab_len, .fromByteUnits(slab_len)) orelse
            return null));
        slab.* = .{
            .owner_index = thread_index,
            .pending_count = .init(0),
            .pending_frees = .init(0),
        };
        const slots_start = @intFromPtr(slab) + slabHeaderSize(slot_size);
        assert(slots_start < @intFromPtr(slab) + 2 * slab_len);

        const t = &global.threads[thread_index];
        const first_addr: usize, const last_node: *usize = nodes: {
            if (t.mutex.tryLock()) {
                defer t.mutex.unlock();

                const next_addr = t.next_addrs[class];
                t.next_addrs[class] = slots_start + slot_size;

                if (next_addr % slab_len != 0) {
                    const first_addr = next_addr;
                    var last_node: *usize = @ptrFromInt(first_addr);
                    while ((@intFromPtr(last_node) + slot_size) % slab_len != 0) {
                        last_node.* = @intFromPtr(last_node) + slot_size;
                        last_node = @ptrFromInt(last_node.*);
                    }
                    break :nodes .{ first_addr, last_node };
                }
                break :nodes .{ 0, undefined };
            } else {
                @branchHint(.unlikely);

                const first_addr = slots_start + slot_size;
                var last_node: *usize = @ptrFromInt(first_addr);
                while (@intFromPtr(last_node) + slot_size != @intFromPtr(slab) + slab_len) {
                    last_node.* = @intFromPtr(last_node) + slot_size;
                    last_node = @ptrFromInt(last_node.*);
                }
                break :nodes .{ first_addr, last_node };
            }
        };

        if (first_addr != 0) {
            last_node.* = t.frees[class].load(.monotonic);
            while (t.frees[class].cmpxchgWeak(
                last_node.*,
                first_addr,
                .release,
                .monotonic,
            )) |top_free_ptr| {
                last_node.* = top_free_ptr;
            }
        }

        return @ptrFromInt(slots_start);
    }
}

fn resize(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    _ = context;
    _ = ra;
    const class = sizeClassIndex(memory.len, alignment);
    const new_class = sizeClassIndex(new_len, alignment);
    if (class >= size_class_count) {
        if (new_class < size_class_count) return false;
        return PageAllocator.realloc(memory, alignment, new_len, false) != null;
    }
    return new_class == class;
}

fn remap(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    _ = context;
    _ = ra;
    const class = sizeClassIndex(memory.len, alignment);
    const new_class = sizeClassIndex(new_len, alignment);
    if (class >= size_class_count) {
        if (new_class < size_class_count) return null;
        return PageAllocator.realloc(memory, alignment, new_len, true);
    }
    return if (new_class == class) memory.ptr else null;
}

fn free(context: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    _ = context;
    _ = ra;
    const class = sizeClassIndex(memory.len, alignment);
    if (class >= size_class_count) {
        @branchHint(.unlikely);
        return PageAllocator.unmap(@alignCast(memory));
    }

    const slot_size = slotSize(class);
    const slab_len = slabLen(slot_size);
    assert(slab_len % slot_size == 0);

    const slab: *Slab = @ptrFromInt(mem.alignBackward(usize, @intFromPtr(memory.ptr), slab_len));
    const node: *usize = @ptrCast(@alignCast(memory.ptr));

    const slots_per_slab = @divExact(slab_len - slabHeaderSize(slot_size), slot_size);
    const reap_threshold: u32 = @intCast(@divCeil(slots_per_slab, reap_threshold_divisor));
    if (slab.pending_count.fetchAdd(1, .monotonic) == reap_threshold) {
        @branchHint(.unlikely);
        assert(slab.pending_count.fetchSub(reap_threshold, .monotonic) >= reap_threshold);

        node.* = slab.pending_frees.swap(0, .acquire);
        const first_addr = @intFromPtr(node);

        var last_node = node;
        while (last_node.* != 0) last_node = @ptrFromInt(last_node.*);

        const t = &global.threads[slab.owner_index];
        last_node.* = t.frees[class].load(.monotonic);
        while (t.frees[class].cmpxchgWeak(
            last_node.*,
            first_addr,
            .release,
            .monotonic,
        )) |top_free_ptr| {
            last_node.* = top_free_ptr;
        }
    } else {
        node.* = slab.pending_frees.load(.monotonic);
        while (slab.pending_frees.cmpxchgWeak(
            node.*,
            @intFromPtr(node),
            .release,
            .monotonic,
        )) |top_pending_ptr| {
            node.* = top_pending_ptr;
        }
    }
}

fn sizeClassIndex(len: usize, alignment: Alignment) usize {
    return @max(@bitSizeOf(usize) - @clz(len - 1), @backingInt(alignment), min_class) - min_class;
}

fn slotSize(class: usize) usize {
    return @as(usize, 1) << @intCast(class + min_class);
}

fn slabLen(slot_size: usize) usize {
    return @max(min_slab_len, 64 * slot_size);
}

fn slabHeaderSize(slot_size: usize) usize {
    return mem.alignForward(usize, @sizeOf(Slab), slot_size);
}
