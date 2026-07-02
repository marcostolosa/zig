// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/hexagon

const builtin = @import("builtin");
const c = @import("std").c;

inline fn getusr() c.fexcept_t {
    var val: c.fexcept_t = 0;
    asm volatile (
        \\ %[val] = usr
        : [val] "=r" (val),
    );
    return val;
}
inline fn setusr(val: c.fexcept_t) void {
    asm volatile (
        \\ usr = %[val]
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    var fcsr = getusr();
    fcsr &= ~(excepts & c.FE.ALL_EXCEPT);
    setusr(fcsr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    var fcsr = getusr();
    fcsr |= (excepts & c.FE.ALL_EXCEPT);
    setusr(fcsr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    return (getusr() & mask & c.FE.ALL_EXCEPT);
}

pub fn getRound() c.fexcept_t {
    return ((getusr() & (c.FE.UPWARD << 22)) >> 22);
}
pub fn setRound(mode: c.fexcept_t) void {
    var fcsr = getusr();
    fcsr &= ~(c.FE.UPWARD << 22);
    fcsr |= ((mode & c.FE.UPWARD) << 22);
    setusr(fcsr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    env.cw = getusr();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    var val = env.cw;
    val &= c.FE.USR_FE_MASK;
    var fscr = getusr() & ~c.FE.USR_FE_MASK;
    fscr |= val;
    setusr(fscr);
}
