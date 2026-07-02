// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/arch/m68k/bits/fenv.h
// https://git.musl-libc.org/cgit/musl/tree/src/fenv/m68k

const builtin = @import("builtin");
const std = @import("std");
const c = std.c;

inline fn m68kGetSR() c.fexcept_t {
    var v: c.fexcept_t = 0;
    asm volatile (
        \\ fmove.l %%fpsr, %[out]
        : [out] "=dm" (v),
    );
    return v;
}
inline fn m68kSetSR(v: c.fexcept_t) void {
    asm volatile (
        \\ fmove.l %[v], %%fpsr)
        :
        : [v] "dm" (v),
    );
}
inline fn m68kGetCR() c.fexcept_t {
    var v: c.fexcept_t = 0;
    asm volatile (
        \\ fmove.l %%fpcr, %[out]
        : [out] "=dm" (v),
    );
    return v;
}
inline fn m68kSetCR(v: c.fexcept_t) void {
    asm volatile (
        \\ fmove.l %[v], %%fpcr
        :
        : [v] "dm" (v),
    );
}

pub fn clearExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        if (excepts & ~c.FE.ALL_EXCEPT != 0) return;
        m68kSetSR(m68kGetSR() & ~excepts);
    }
}

pub fn raiseExcept(excepts: c.fexcept_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        if (excepts & ~c.FE.ALL_EXCEPT) return;
        m68kSetSR(m68kGetSR() | excepts);
    }
}

pub fn testExcept(mask: c.fexcept_t) c.fexcept_t {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        return m68kGetSR() & mask;
    }
    return c.FE.ALL_EXCEPT;
}

pub fn getRound() c.fexcept_t {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        return m68kGetCR() & c.FE.UPWARD;
    }
    return c.FE.TO_NEAREST;
}
pub fn setRound(mode: c.fexcept_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        m68kSetCR((m68kGetCR() & ~c.FE.UPWARD) | mode);
    }
}

pub fn getEnv() c.fenv_t {
    var env: c.fenv_t = .{};
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        env.control_register = m68kGetCR();
        env.status_register = m68kGetSR();

        var iaddr: u32 = 0;
        asm volatile (
            \\ fmove.l %%fpiar, %[out]
            : [out] "=dm" (iaddr),
        );

        env.instruction_address = iaddr;
    }
    return env;
}

pub fn setEnv(env: c.fenv_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        m68kSetCR(env.control_register);
        m68kSetSR(env.status_register);

        asm volatile (
            \\ fmove.l  %[in], %%fpiar
            :
            : [in] "dm" (env.instruction_address),
        );
    }
}
