// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/x86_64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/x86_64

const builtin = @import("builtin");
const c = @import("std").c;

inline fn fnstsw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ fnstsw %%ax
        : [val] "={ax}" (val),
    );
    return val;
}
inline fn fnstcw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ push %%rax
        \\ fnstcw (%%rsp)
        \\ pop %%rax
        : [val] "={ax}" (val),
    );
    return val;
}
inline fn fldcw(val: u16) void {
    asm volatile (
        \\ movw %[val], -4(%%rsp)
        \\ fldcw -4(%%rsp)
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
        \\ movl %[val], -8(%%rsp)
        \\ ldmxcsr -8(%%rsp)
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    const mask = excepts & c.FE.ALL_EXCEPT;
    var fsw = fnstsw();

    if (mask & fsw != 0) {
        fnclex();
    }

    var mxcsr = stmxcsr();
    fsw &= c.FE.TOWARD_ZERO;
    mxcsr |= fsw;
    if (@as(u32, mask) & mxcsr != 0) {
        mxcsr &= ~@as(u32, mask);
        ldmxcsr(mxcsr);
    }
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    ldmxcsr(stmxcsr() | @as(u32, @intCast(excepts & c.FE.ALL_EXCEPT)));
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    var fsw = fnstsw();

    fsw |= @truncate(stmxcsr());
    fsw &= mask;
    fsw &= c.FE.ALL_EXCEPT;
    return fsw;
}

pub fn getRound() c.fexcept_t {
    return (@as(u16, @truncate(stmxcsr() >> 3)) & c.FE.TOWARD_ZERO);
}
pub fn setRound(mode: c.fexcept_t) void {
    var fcw = fnstcw();
    fcw &= ~(c.FE.TOWARD_ZERO);
    // fcw |= (mode & 0x11110000);
    fcw |= mode;
    fldcw(fcw);

    var mxcsr = stmxcsr();
    mxcsr &= 0x9fff;
    // mxcsr |= (mode & 0b11110000);
    mxcsr |= (@as(u32, @intCast(mode)) << 3);
    ldmxcsr(mxcsr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    asm volatile (
        \\ fnstenv (%%rax)
        \\ stmxcsr 28(%%rax)
        :
        : [addr] "{rax}" (&env),
        : .{ .memory = true });
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    asm volatile (
        \\ fldenv (%%rax)
        \\ ldmxcsr 28(%%rax) 
        :
        : [out] "{rax}" (&env),
    );
}
