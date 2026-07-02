// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/riscv32/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/arch/riscv64/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/riscv32
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/riscv64

const builtin = @import("builtin");
const c = @import("std").c;

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (builtin.abi.float() == .soft) return;
    asm volatile (
        \\ csrc fflags, %[mask]
        :
        : [mask] "r" (excepts),
        : .{
          .fflags = true,
        });
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (builtin.abi.float() == .soft) return;
    asm volatile (
        \\ csrs fflags, %[mask]
        :
        : [mask] "r" (excepts),
        : .{ .fflags = true });
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    var out: c.fexcept_t = 0;
    if (builtin.abi.float() == .soft) return out;
    asm volatile (
        \\ frflags %[out]
        : [out] "=r" (out),
    );
    return (out & mask);
}

pub fn getRound() c.fexcept_t {
    var out: c.fexcept_t = 0;
    if (builtin.abi.float() == .soft) return out;
    asm volatile (
        \\ frrm %[out]
        : [out] "=r" (out),
    );
    return out;
}
pub fn setRound(mode: c.fexcept_t) void {
    if (builtin.abi.float() == .soft) return;
    asm volatile (
        \\ fsrm %[in]
        :
        : [in] "r" (@as(u64, @intCast(mode))),
    );
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (builtin.abi.float() == .soft) return env;
    asm volatile (
        \\ frcsr t0
        \\ sw t0 , 0(t1)
        :
        : [addr] "{t1}" (&env),
        : .{ .memory = true });
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (builtin.abi.float() == .soft) return;
    asm volatile (
        \\ lw t1, 0(%[addr])
        \\ fscsr t1
        :
        : [addr] "r" (&env),
    );
}
