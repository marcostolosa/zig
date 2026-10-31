const std = @import("std");

pub const io = @import("ps2/io.zig");

pub const Sys = enum(i32) {
    exit = 4,
    setup_thread = 0x3c,
    setup_heap = 0x3d,
    end_of_heap = 0x3e,
    flush_cache = 0x64,
};

const SysInt = usize;

pub fn syscall0(
    number: Sys,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
        : .{
          .r1 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall1(
    number: Sys,
    arg1: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
        : .{
          .r1 = true,
          .r3 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall2(
    number: Sys,
    arg1: SysInt,
    arg2: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
          [arg2] "{$5}" (arg2),
        : .{
          .r1 = true,
          .r3 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall3(
    number: Sys,
    arg1: SysInt,
    arg2: SysInt,
    arg3: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
          [arg2] "{$5}" (arg2),
          [arg3] "{$6}" (arg3),
        : .{
          .r1 = true,
          .r3 = true,
          .r7 = true,
          .r8 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall4(
    number: Sys,
    arg1: SysInt,
    arg2: SysInt,
    arg3: SysInt,
    arg4: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
          [arg2] "{$5}" (arg2),
          [arg3] "{$6}" (arg3),
          [arg4] "{$7}" (arg4),
        : .{
          .r1 = true,
          .r3 = true,
          .r8 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall5(
    number: Sys,
    arg1: SysInt,
    arg2: SysInt,
    arg3: SysInt,
    arg4: SysInt,
    arg5: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
          [arg2] "{$5}" (arg2),
          [arg3] "{$6}" (arg3),
          [arg4] "{$7}" (arg4),
          [arg5] "{$8}" (arg5),
        : .{
          .r1 = true,
          .r3 = true,
          .r9 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

pub fn syscall6(
    number: Sys,
    arg1: SysInt,
    arg2: SysInt,
    arg3: SysInt,
    arg4: SysInt,
    arg5: SysInt,
    arg6: SysInt,
) SysInt {
    return asm volatile (
        \\ syscall
        : [ret] "={$2}" (-> u32),
        : [number] "{$3}" (@backingInt(number)),
          [arg1] "{$4}" (arg1),
          [arg2] "{$5}" (arg2),
          [arg3] "{$6}" (arg3),
          [arg4] "{$7}" (arg4),
          [arg5] "{$8}" (arg5),
          [arg6] "{$9}" (arg6),
        : .{
          .r1 = true,
          .r3 = true,
          .r10 = true,
          .r11 = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .r24 = true,
          .r25 = true,
          .hi = true,
          .lo = true,
          .memory = true,
        });
}

/// Small driver for the `EE`'s serial I/O
pub const sio = struct {
    const isr: *volatile u32 = @ptrFromInt(0x1000_f130);
    const tx_fifo: *volatile u8 = @ptrFromInt(0x1000_f180);

    pub fn writeByte(byte: u8) void {
        while (isr.* & 0xf000 == 0x8000) {}

        tx_fifo.* = byte;
    }

    pub fn writeAll(bytes: []const u8) void {
        for (bytes) |byte| writeByte(byte);
    }
};

var cur_brk: usize = 0;

/// Implements a `Linux`-esque `brk`, with the caveat that it never shrinks
pub fn brk(addr: usize) usize {
    if (cur_brk == 0) cur_brk = @intFromPtr(@extern([*]u8, .{ .name = "_end" }));
    if (addr != 0 and addr >= cur_brk and addr <= syscall0(.end_of_heap)) cur_brk = addr;

    return cur_brk;
}

/// Exits the currently running executable
pub fn exit(status: u8) noreturn {
    sio.writeAll("ZIG_PS2_EXIT ");

    var buf: [3]u8 = undefined;
    var n = status;
    var i: usize = buf.len;

    while (true) {
        i -= 1;
        buf[i] = '0' + n % 10;
        n /= 10;
        if (n == 0) break;
    }

    sio.writeAll(buf[i..]);
    sio.writeByte('\n');

    _ = syscall1(.exit, status);
    unreachable;
}

/// Program arguments passed by the kernel
pub const ProgramArgs = extern struct {
    const max_nr_args = 16;
    const max_payload_size = 256;

    /// Number of arguments in `args`
    nr_args: c_int,
    /// Array of `C` strings pointing into `payload`
    args: [max_nr_args][*:0]const u8,
    /// Payload data, holding the program arguments
    payload: [max_payload_size]u8,
};

/// Enumerates cache operations that can be performed by the kernel through `cacheOp`
pub const CacheOp = enum(c_int) {
    /// Writes-back and invalidates the data cache
    dxwbin = 0,
    /// Invalidates the data cache
    dxin = 1,
    /// Invalidates the instruction and Branch Target Address Cache (`BTAC`)
    bfh_ixin = 2,
    /// Invalidates the data, instruction and Branch Target Address Cache (`BTAC`)
    dxin_bfh_ixin = 3,
};

/// Performs an `EE` cache maintenance operation
pub fn cacheOp(
    /// Determines the cache operation performed by the kernel
    op: CacheOp,
) void {
    _ = syscall1(.flush_cache, @intCast(@backingInt(op)));
}

/// Registers the executable's heap region with the `EE` kernel
pub fn setupHeap(
    /// Base address of the heap
    base: *const anyopaque,
    /// Size in bytes of the heap
    size: ?u32,
) void {
    _ = syscall2(.setup_heap, @intFromPtr(base), size orelse @bitCast(@as(isize, -1)));
}
