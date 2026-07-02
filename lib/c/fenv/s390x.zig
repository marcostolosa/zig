// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/s390x/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/s390x

const builtin = @import("builtin");
const c = @import("std").c;

inline fn s390xGetFpc() c.fexcept_t {
    var fpc: c.fexcept_t = 0;
    asm volatile (
        \\ efpc %[out]
        : [out] "=r" (fpc),
    );
    return fpc;
}
inline fn s390xSetFpc(fpc: c.fexcept_t) void {
    asm volatile (
        \\ sfpc %[in]
        :
        : [in] "r" (fpc),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    s390xSetFpc(s390xGetFpc() & ~(excepts & c.FE.ALL_EXCEPT));
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    s390xSetFpc(s390xGetFpc() | (excepts & c.FE.ALL_EXCEPT));
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    return s390xGetFpc() & mask & c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    return (s390xGetFpc() & 3);
}
pub fn setRound(mode: c.fexcept_t) void {
    s390xSetFpc(s390xGetFpc() & ~@as(u32, 3) | mode);
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    env.cw = s390xGetFpc();
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    s390xSetFpc(env.cw);
}
