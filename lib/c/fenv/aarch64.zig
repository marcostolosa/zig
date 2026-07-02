// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/aarch64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/aarch64

const builtin = @import("builtin");
const c = @import("std").c;

inline fn get_fpcr() c.fexcept_t {
    var val: u32 = 0;
    asm volatile (
        \\ mrs x1, fpcr
        : [val] "={w1}" (val),
        :
        : .{ .x1 = true });
    return val;
}
inline fn get_fpsr() c.fexcept_t {
    var val: u32 = 0;
    asm volatile (
        \\ mrs x1, fpsr
        : [val] "={w1}" (val),
        :
        : .{ .x1 = true });
    return val;
}
inline fn set_fpsr(val: c.fexcept_t) void {
    asm volatile (
        \\ msr fpsr, x1
        :
        : [val] "{w1}" (val),
    );
}
inline fn set_fpcr(val: c.fexcept_t) void {
    asm volatile (
        \\ msr fpcr, x1
        :
        : [val] "{w1}" (val),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    var fpsr = get_fpsr();
    fpsr &= ~(excepts & c.FE.ALL_EXCEPT);
    set_fpsr(fpsr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    var fpsr = get_fpsr();
    fpsr |= (excepts & c.FE.ALL_EXCEPT);
    set_fpsr(fpsr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    return get_fpsr() & (mask & c.FE.ALL_EXCEPT);
}

pub fn getRound() c.fexcept_t {
    return get_fpcr() & c.FE.TOWARD_ZERO;
}
pub fn setRound(mode: c.fexcept_t) void {
    var fpcr = get_fpcr();
    fpcr &= ~c.FE.TOWARD_ZERO;
    fpcr |= mode;
    set_fpcr(fpcr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    env.fpcr = get_fpcr();
    env.fpsr = get_fpsr();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    set_fpcr(env.fpcr);
    set_fpsr(env.fpsr);
}
