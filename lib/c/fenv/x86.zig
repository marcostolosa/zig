// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/i386/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/i386

const builtin = @import("builtin");
const std = @import("std");
const c = std.c;

inline fn fnstsw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ fnstsw %%ax
        : [val] "={ax}" (val),
        :
        : .{ .ax = true });
    return val;
}
inline fn fnstcw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ push %%eax
        \\ fnstcw (%%esp)
        \\ pop %%eax
        : [val] "={ax}" (val),
    );
    return val;
}
inline fn fldcw(val: u16) void {
    asm volatile (
        \\ movw %[val], -4(%%esp)
        \\ fldcw -4(%%esp)
        :
        : [val] "r" (val),
    );
}
inline fn fnclex() void {
    asm volatile (
        \\ fnclex
    );
}
inline fn stmxcsr() u32 {
    var val: u32 = 0;
    asm volatile (
        \\ stmxcsr %[val]
        : [val] "=m" (val),
    );
    return val;
}
inline fn ldmxcsr(val: u32) void {
    asm volatile (
        \\ movl %[val], -4(%%esp)
        \\ ldmxcsr -4(%%esp)
        :
        : [val] "r" (val),
    );
}

const sse = builtin.cpu.hasAny(builtin.target.cpu.arch.family(), &.{
    std.Target.x86.Feature.sse,
    std.Target.x86.Feature.sse2,
    std.Target.x86.Feature.sse3,
});

pub fn clearExcept(excepts: c.fexcept_t) void {
    var mask = excepts & c.FE.ALL_EXCEPT;
    var fsw = fnstsw();

    if (comptime sse) {
        if (mask & fsw != 0) fnclex();

        var mxcsr = stmxcsr();
        fsw &= c.FE.ALL_EXCEPT;
        mxcsr |= @as(u32, fsw);

        if (mxcsr & @as(u32, mask) == 0) return;
        mxcsr &= ~@as(u32, mask);
        ldmxcsr(mxcsr);
        return;
    }
    if (mask & fsw == 0) return;
    mask = ~mask;
    fsw &= mask;
    if (fsw & c.FE.ALL_EXCEPT != 0) {
        fnclex();
        return;
    }

    asm volatile (
        \\ subl $32, %%esp
        \\ fnstenv (%esp)
        \\ mov %%al, 4(%%esp)
        \\ fldenv (%%esp)
        \\ addl $32, %%esp
        :
        : [fsw] "{al}" (fsw),
    );
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    asm volatile (
        \\ subl $32, %%esp
        \\ fnstenv (%%esp)
        \\ or %%al, 4(%%esp)
        \\ fldenv (%%esp)
        \\ addl $32, %%esp
        :
        : [ex] "{eax}" (excepts & c.FE.ALL_EXCEPT),
    );
    if (comptime sse) {
        ldmxcsr(stmxcsr() | @as(u32, @intCast(excepts & c.FE.ALL_EXCEPT)));
    }
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    var fsw = fnstsw();

    if (comptime sse) {
        fsw |= @truncate(stmxcsr());
    }
    fsw &= (mask & c.FE.ALL_EXCEPT);
    return fsw;
}

pub fn getRound() c.fexcept_t {
    if (comptime sse) {
        return (@as(u16, @truncate(stmxcsr() >> 3)) & c.FE.TOWARD_ZERO);
    } else {
        return (fnstcw() & c.FE.TOWARD_ZERO);
    }
}
pub fn setRound(mode: c.fexcept_t) void {
    var fcw = fnstcw();
    fcw &= ~(c.FE.TOWARD_ZERO);
    // fcw |= (mode & 0x11110000);
    fcw |= mode;
    fldcw(fcw);

    if (comptime sse) {
        var mxcsr = stmxcsr();
        mxcsr &= 0x9fff;
        // mxcsr |= (mode & 0b11110000);
        mxcsr |= (@as(u32, @intCast(mode)) << 3);
        ldmxcsr(mxcsr);
    }
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    asm volatile (
        \\ fnstenv (%%eax)
        :
        : [addr] "{eax}" (&env),
        : .{ .memory = true });
    if (comptime sse) {
        env.status_word |= (@as(u16, @truncate(stmxcsr())) & c.FE.ALL_EXCEPT);
    }
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    asm volatile (
        \\ fldenv (%%ecx)
        :
        : [out] "{ecx}" (&env),
    );
    if (comptime sse) {
        asm volatile (
            \\ movl (%%ecx), %%ecx
            \\ andl $0xc00, %%ecx
            \\ shl $3, %%ecx
            \\ orl $0x1f80, %%ecx
            \\ mov %%ecx, -4(%%esp)
            \\ ldmxcsr -4(%%esp)
            :
            : [out] "{ecx}" (&env),
            : .{ .ecx = true });
    }
}
