// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/powerpc64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/powerpc64

const builtin = @import("builtin");
const c = @import("std").c;

inline fn getFpscr() c.fexcept_t {
    return @truncate(@as(u64, @bitCast(getFpscr_f())));
}
inline fn getFpscr_f() f64 {
    var fpc: f64 = 0;
    asm volatile (
        \\ mffs %[out]
        : [out] "=d" (fpc),
    );
    return fpc;
}
inline fn setFpscr(fpc: c.fexcept_t) void {
    setFpscr_f(@bitCast(@as(u64, @intCast(fpc))));
}
inline fn setFpscr_f(fpc: f64) void {
    asm volatile (
        \\ mtfsf 255, %[out]
        :
        : [out] "d" (fpc),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    var mask = excepts & c.FE.ALL_EXCEPT;
    if ((mask & c.FE.INVALID) != 0) mask |= 0x1f80700;
    setFpscr(getFpscr() & ~mask);
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    var mask = excepts & c.FE.ALL_EXCEPT;
    if ((mask & c.FE.INVALID) != 0) mask |= 0x00000400;
    setFpscr(getFpscr() | mask);
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    return getFpscr() & mask & c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    return (getFpscr() & 3);
}
pub fn setRound(mode: c.fexcept_t) void {
    setFpscr(getFpscr() & ~@as(u32, @intCast(3)) | mode);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    env.cw = getFpscr_f();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    setFpscr_f(env.cw);
}
