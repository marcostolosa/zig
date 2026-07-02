// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/powerpc/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/powerpc

const builtin = @import("builtin");
const c = @import("std").c;

inline fn mffs() u32 {
    var val: f64 = 0;
    asm volatile (
        \\ mffs %[val]
        : [val] "=d" (val),
    );
    return @truncate(@as(u64, @bitCast(val)));
}
inline fn mtfsf(val: u32) void {
    asm volatile (
        \\ mtfsf 255, %[val]
        :
        : [val] "d" (@as(u64, val)),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (builtin.abi.float() == .soft) return;

    var mask = excepts & c.FE.ALL_EXCEPT;
    if (mask & c.FE.INVALID != 0) mask |= c.FE.ALL_INVALID;

    var fpscr = mffs();
    fpscr &= ~mask;
    mtfsf(fpscr);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var mask = excepts & c.FE.ALL_EXCEPT;
    if (mask & c.FE.INVALID != 0) mask |= c.FE.SOFTWARE_INVALID;

    var fpscr = mffs();
    fpscr |= mask;
    mtfsf(fpscr);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.ALL_EXCEPT;
    const fpscr = mffs();
    return fpscr & mask & c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    if (comptime builtin.abi.float() == .soft) return c.FE.ALL_EXCEPT;

    return mffs() & c.FE.DOWNWARD;
}
pub fn setRound(mode: c.fexcept_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fpscr = mffs();
    fpscr &= ~c.FE.DOWNWARD;
    fpscr |= mode;
    mtfsf(fpscr);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (comptime builtin.abi.float() == .soft) return env;

    env.cw = @bitCast(@as(u64, mffs()));
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    mtfsf(@truncate(@as(u64, @bitCast(env.cw))));
}
