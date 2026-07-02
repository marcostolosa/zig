// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/generic/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv

const builtin = @import("builtin");
const c = @import("std").c;

pub fn clearExcept(excepts: c.fexcept_t) void {
    _ = excepts;
    return;
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    _ = excepts;
    return;
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    _ = mask;
    return c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    return 0;
}
pub fn setRound(mode: c.fexcept_t) void {
    _ = mode;
}

pub fn getEnv() c.fenv_t {
    return .{};
}

pub fn setEnv(env: c.fenv_t) void {
    _ = env;
}
