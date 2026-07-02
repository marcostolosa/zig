// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/loongarch64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/loongarch64

const builtin = @import("builtin");
const c = @import("std").c;

inline fn movfcsr2gr() c.fexcept_t {
    var val: u64 = 0;
    asm volatile (
        \\ movfcsr2gr %[val], $fcsr0
        : [val] "=r" (val),
    );
    return @truncate(val);
}
inline fn movgr2fcsr(val: c.fexcept_t) void {
    asm volatile (
        \\ movgr2fcsr $fcsr0, %[val]
        :
        : [val] "r" (val),
        : .{ .fcsr0 = true });
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr &= ~(excepts & c.FE.ALL_EXCEPT);
    movgr2fcsr(fcsr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr |= (excepts & c.FE.ALL_EXCEPT);
    movgr2fcsr(fcsr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.ALL_EXCEPT;
    return (movfcsr2gr() & mask & c.FE.ALL_EXCEPT);
}

pub fn getRound() c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.TO_NEAREST;
    return (movfcsr2gr() & c.FE.DOWNWARD);
}
pub fn setRound(mode: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr &= c.FE.DOWNWARD;
    fcsr &= ~c.FE.DOWNWARD;
    fcsr |= (mode & c.FE.DOWNWARD);
    movgr2fcsr(fcsr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = movfcsr2gr();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    movgr2fcsr(env.cw);
}
