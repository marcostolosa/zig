// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/arm/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/arm

const builtin = @import("builtin");
const c = @import("std").c;

inline fn vmrs() c.fexcept_t {
    var val: c.fexcept_t = 0;
    asm volatile (
        \\ vmrs %[val], fpscr
        : [val] "=r" (val),
    );
    return val;
}

inline fn vmsr(val: c.fexcept_t) void {
    asm volatile (
        \\ vmsr fpscr, %[val]
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = vmrs();
    fcsr &= ~(excepts & c.FE.ALL_EXCEPT);
    vmsr(fcsr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = vmrs();
    fcsr |= (excepts & c.FE.ALL_EXCEPT);
    vmsr(fcsr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.ALL_EXCEPT;

    return vmrs() & (mask & c.FE.ALL_EXCEPT);
}

pub fn getRound() c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return 0;
    return vmrs() & c.FE.TOWARD_ZERO;
}
pub fn setRound(mode: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = vmrs();
    fcsr &= ~c.FE.TOWARD_ZERO;
    fcsr |= mode;
    vmsr(fcsr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = vmrs();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    vmsr(env.cw);
}
