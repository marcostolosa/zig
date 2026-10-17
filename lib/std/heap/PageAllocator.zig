const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const mem = std.mem;
const maxInt = std.math.maxInt;
const assert = std.debug.assert;
const windows = std.os.windows;
const ntdll = std.os.windows.ntdll;
const posix = std.posix;
const page_size_min = std.heap.page_size_min;

pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

/// Hhinting is disabled on operating systems that make an effort to not reuse
/// mappings. For example, OpenBSD aggressively randomizes addresses of mappings
/// that don't provide a hint (for security reasons, but it serves our needs
/// too).
const enable_hints = switch (builtin.target.os.tag) {
    .linux => !builtin.target.cpu.arch.isSPARC(), // https://bugzilla.kernel.org/show_bug.cgi?id=221820
    .openbsd => false,
    else => true,
};

/// On operating systems that don't immediately map in the whole stack, we need
/// to be careful to not hint into the pages after the stack guard gap, which
/// the stack will expand into. The easiest way to avoid that is to hint in the
/// same direction as stack growth.
const stack_direction = builtin.target.stackGrowth();

/// When hinting upwards, this points to the next page that we hope to allocate
/// at; when hinting downwards, this points to the beginning of the last
/// successful allocation.
///
/// TODO: Utilize this on Windows.
var addr_hint: ?[*]align(page_size_min) u8 = null;

pub fn map(n: usize, alignment: Alignment) ?[*]u8 {
    const page_size = std.heap.pageSize();
    if (n >= maxInt(usize) - page_size) return null;
    const alignment_bytes = alignment.toByteUnits();

    if (native_os == .windows) {
        const current_process = windows.GetCurrentProcess();
        var base_addr: ?*anyopaque = null;
        var region_size: windows.SIZE_T = undefined;

        const allocation_granularity = 64 * 1024;
        const page_aligned_len = mem.alignForward(usize, n, page_size);

        // For common small alignments, a plain reserve+commit is sufficient.
        if (alignment_bytes <= allocation_granularity) {
            base_addr = null;
            region_size = page_aligned_len;
            const fast_status = ntdll.NtAllocateVirtualMemory(current_process, @ptrCast(&base_addr), 0, &region_size, .{ .COMMIT = true, .RESERVE = true }, .{ .READWRITE = true });
            if (fast_status == .SUCCESS) {
                return @ptrCast(base_addr);
            }
            return null;
        }

        const max_drop_len = alignment_bytes - allocation_granularity;
        if (page_aligned_len > maxInt(usize) - max_drop_len) return null;
        const overalloc_len = page_aligned_len + max_drop_len;

        // Reserve a larger scratch mapping, pick an aligned address within it,
        // release the scratch mapping, then reserve+commit at the aligned address.
        base_addr = null;
        region_size = overalloc_len;
        const scratch_status = ntdll.NtAllocateVirtualMemory(current_process, @ptrCast(&base_addr), 0, &region_size, .{ .RESERVE = true }, .{ .NOACCESS = true });
        if (scratch_status != .SUCCESS) return null;

        const scratch_addr = @intFromPtr(base_addr);
        const aligned_addr = mem.alignForward(usize, scratch_addr, alignment_bytes);

        // The aligned block is guaranteed to fit within the scratch mapping because:
        // 1. scratch_addr is a multiple of 64KB (Windows guarantee).
        // 2. The max distance to the next `alignment_bytes` boundary is `alignment_bytes - 64kiB`.
        // 3. overalloc_len = page_aligned_len + (alignment_bytes - 64kiB).

        var release_base = base_addr;
        var release_size: windows.SIZE_T = 0;
        _ = ntdll.NtFreeVirtualMemory(current_process, @ptrCast(&release_base), &release_size, .{ .RELEASE = true });

        base_addr = @ptrFromInt(aligned_addr);
        region_size = page_aligned_len;
        const final_status = ntdll.NtAllocateVirtualMemory(current_process, @ptrCast(&base_addr), 0, &region_size, .{ .COMMIT = true, .RESERVE = true }, .{ .READWRITE = true });

        if (final_status == .SUCCESS) {
            return @ptrCast(base_addr);
        }

        return null;
    }

    const page_aligned_len = mem.alignForward(usize, n, page_size);
    const max_drop_len = alignment_bytes -| page_size;
    const overalloc_len = page_aligned_len + max_drop_len;

    const maybe_unaligned_hint, const hint = blk: {
        if (!enable_hints) break :blk .{ null, null };

        const maybe_unaligned_hint = @atomicLoad(@TypeOf(addr_hint), &addr_hint, .unordered);

        // For the very first mmap, let the kernel pick a good starting address;
        // we'll begin doing our hinting from there.
        if (maybe_unaligned_hint == null) break :blk .{ null, null };

        // Aligning hint does not use mem.alignPointer, because it is slow.
        // Aligning hint does not use mem.alignForward, because it asserts that there will be no overflow.
        const hint: ?[*]align(page_size_min) u8 = @ptrFromInt(switch (stack_direction) {
            .down => ((@intFromPtr(maybe_unaligned_hint) -% page_aligned_len) & ~(alignment_bytes - 1)) -% max_drop_len,
            .up => (@intFromPtr(maybe_unaligned_hint) +% (alignment_bytes - 1)) & ~(alignment_bytes - 1),
        });

        break :blk .{ maybe_unaligned_hint, hint };
    };

    const slice = posix.mmap(
        hint,
        overalloc_len,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch return null;
    const result_ptr = mem.alignPointer(slice.ptr, alignment_bytes).?;

    // Unmap the extra bytes that were only requested in order to guarantee
    // that the range of memory we were provided had a proper alignment in it
    // somewhere. The extra bytes could be at the beginning, or end, or both.
    const drop_len = result_ptr - slice.ptr;
    if (drop_len != 0) posix.munmap(slice[0..drop_len]);
    const remaining_len = overalloc_len - drop_len;
    if (remaining_len > page_aligned_len) posix.munmap(@alignCast(result_ptr[page_aligned_len..remaining_len]));

    if (enable_hints) {
        const new_hint: [*]align(page_size_min) u8 = @alignCast(result_ptr + switch (stack_direction) {
            .up => page_aligned_len,
            .down => 0,
        });
        _ = @cmpxchgStrong(@TypeOf(addr_hint), &addr_hint, maybe_unaligned_hint, new_hint, .monotonic, .monotonic);
    }

    return result_ptr;
}

fn alloc(context: *anyopaque, n: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    _ = context;
    _ = ra;
    assert(n > 0);
    return map(n, alignment);
}

fn resize(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) bool {
    _ = context;
    _ = return_address;
    return realloc(memory, alignment, new_len, false) != null;
}

fn remap(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    _ = context;
    _ = return_address;
    return realloc(memory, alignment, new_len, true);
}

fn free(context: *anyopaque, memory: []u8, alignment: Alignment, return_address: usize) void {
    _ = context;
    _ = return_address;
    _ = alignment;
    return unmap(@alignCast(memory));
}

pub fn unmap(memory: []align(page_size_min) u8) void {
    if (native_os == .windows) {
        var base_addr: ?*anyopaque = memory.ptr;
        var region_size: windows.SIZE_T = 0;
        _ = ntdll.NtFreeVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&base_addr), &region_size, .{ .RELEASE = true });
    } else {
        const page_aligned_len = mem.alignForward(usize, memory.len, std.heap.pageSize());
        posix.munmap(memory.ptr[0..page_aligned_len]);
    }
}

pub fn realloc(uncasted_memory: []u8, alignment: Alignment, new_len: usize, may_move: bool) ?[*]u8 {
    const memory: []align(page_size_min) u8 = @alignCast(uncasted_memory);
    const page_size = std.heap.pageSize();
    if (alignment.toByteUnits() > page_size) return null;
    const new_size_aligned = mem.alignForward(usize, new_len, page_size);

    if (native_os == .windows) {
        if (new_len <= memory.len) {
            const base_addr = @intFromPtr(memory.ptr);
            const old_addr_end = base_addr + memory.len;
            const new_addr_end = mem.alignForward(usize, base_addr + new_len, page_size);
            if (old_addr_end > new_addr_end) {
                var decommit_addr: ?*anyopaque = @ptrFromInt(new_addr_end);
                var decommit_size: windows.SIZE_T = old_addr_end - new_addr_end;

                _ = ntdll.NtAllocateVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&decommit_addr), 0, &decommit_size, .{ .RESET = true }, .{ .NOACCESS = true });
            }
            return memory.ptr;
        }
        const old_size_aligned = mem.alignForward(usize, memory.len, page_size);
        if (new_size_aligned <= old_size_aligned) {
            return memory.ptr;
        }
        return null;
    }

    const page_aligned_len = mem.alignForward(usize, memory.len, page_size);
    if (new_size_aligned == page_aligned_len)
        return memory.ptr;

    // When the stack grows down, only use `mremap` if the allocation may move.
    // Otherwise, we might grow the allocation and intrude on virtual address
    // space which we want to keep available to the stack.
    if (posix.MREMAP != void and (stack_direction == .up or may_move)) {
        // TODO: if the next_mmap_addr_hint is within the remapped range, update it
        const new_memory = posix.mremap(memory.ptr, page_aligned_len, new_size_aligned, .{ .MAYMOVE = may_move }, null) catch return null;
        return new_memory.ptr;
    }

    if (new_size_aligned < page_aligned_len) {
        const ptr = memory.ptr + new_size_aligned;
        // TODO: if the next_mmap_addr_hint is within the unmapped range, update it
        posix.munmap(@alignCast(ptr[0 .. page_aligned_len - new_size_aligned]));
        return memory.ptr;
    }

    return null;
}
