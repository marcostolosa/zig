// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/mips/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/arch/mips64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/mips
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/mips64

const builtin = @import("builtin");
const c = @import("std").c;

inline fn cfc1_fcsr() c.fexcept_t {
    var val: u32 = 0;
    asm volatile (
        \\ cfc1 %[val], $31
        : [val] "=r" (val),
    );
    return @truncate(val);
}

inline fn ctc1_fcsr(val: c.fexcept_t) void {
    asm volatile (
        \\ ctc1 %[val], $31
        :
        : [val] "r" (@as(u32, val)),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = cfc1_fcsr();
    fcsr |= excepts & c.FE.ALL_EXCEPT;
    fcsr ^= excepts & c.FE.ALL_EXCEPT;
    ctc1_fcsr(fcsr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = cfc1_fcsr();
    fcsr |= excepts & c.FE.ALL_EXCEPT;
    ctc1_fcsr(fcsr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.ALL_EXCEPT;

    return cfc1_fcsr() & mask & c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return 0;
    return cfc1_fcsr() & 3;
}
pub fn setRound(mode: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = cfc1_fcsr();
    fcsr &= @as(c.fexcept_t, @bitCast(@as(i16, -4)));
    fcsr |= mode;
    ctc1_fcsr(fcsr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = @intCast(cfc1_fcsr());
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    ctc1_fcsr(@truncate(env.cw));
}
