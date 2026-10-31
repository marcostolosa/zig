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

pub const heap = struct {
    var state: std.heap.FixedBufferAllocator = .init(&.{});

    pub fn page_allocator() std.mem.Allocator {
        return state.allocator();
    }

    pub fn init(start: [*]u8) void {
        const top = syscall0(.end_of_heap);
        state = .init(start[0 .. top - @intFromPtr(start)]);
    }
};

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
