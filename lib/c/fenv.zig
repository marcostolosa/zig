// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/fenv
const builtin = @import("builtin");

const std = @import("std");
const c = std.c;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&feclearexcept, "feclearexcept");
        symbol(&fegetexceptflag, "fegetexceptflag");
        symbol(&feraiseexcept, "feraiseexcept");
        symbol(&fesetexceptflag, "fesetexceptflag");
        symbol(&fetestexcept, "fetestexcept");
        symbol(&fegetround, "fegetround");
        symbol(&fesetround, "fesetround");
        symbol(&fegetenv, "fegetenv");
        symbol(&feholdexcept, "feholdexcept");
        symbol(&fesetenv, "fesetenv");
        symbol(&feupdateenv, "feupdateenv");
    }
}

const impl = switch (builtin.cpu.arch) {
    .x86_64 => @import("fenv/x86_64.zig"),
    .s390x => @import("fenv/s390x.zig"),
    .riscv64, .riscv32 => @import("fenv/riscv.zig"),
    .powerpc64, .powerpc64le => @import("fenv/powerpc64.zig"),
    .powerpc, .powerpcle => @import("fenv/powerpc.zig"),
    .mips64, .mips64el, .mips, .mipsel => @import("fenv/mips.zig"),
    .m68k => @import("fenv/m68k.zig"),
    .loongarch64 => @import("fenv/loongarch64.zig"),
    .x86 => @import("fenv/x86.zig"),
    .hexagon => @import("fenv/hexagon.zig"),
    .arm, .thumb, .armeb, .thumbeb => @import("fenv/arm.zig"),
    .aarch64, .aarch64_be => @import("fenv/aarch64.zig"),
    else => @import("fenv/no_impl.zig"),
};

fn getExceptFlag(mask: c.fexcept_t) c.fexcept_t {
    return impl.testExcept(mask);
}
fn setExceptFlag(excepts: c.fexcept_t, mask: c.fexcept_t) void {
    impl.clearExcept(excepts);
    impl.raiseExcept(excepts & mask);
}
fn holdExcept() c.fenv_t {
    const env = impl.getEnv();
    impl.clearExcept(c.FE.ALL_EXCEPT);
    return env;
}

fn updateEnv(env: c.fenv_t) void {
    const ex = impl.testExcept(c.FE.ALL_EXCEPT);
    impl.setEnv(env);
    impl.raiseExcept(ex);
}

fn feclearexcept(excepts: c_int) callconv(.c) c_int {
    impl.clearExcept(@truncate(@as(c_uint, @bitCast(excepts))));
    return 0;
}
fn fegetexceptflag(flagp: ?*c.fexcept_t, excepts: c_int) callconv(.c) c_int {
    if (flagp) |f_ptr| {
        if (@intFromPtr(f_ptr) == std.math.maxInt(usize)) {
            return -1;
        } else {
            f_ptr.* = getExceptFlag(@truncate(@as(c_uint, @bitCast(excepts))));
        }
    }
    return 0;
}
fn feraiseexcept(excepts: c_int) callconv(.c) c_int {
    impl.raiseExcept(@truncate(@as(c_uint, @bitCast(excepts))));
    return 0;
}
fn fesetexceptflag(flagp: ?*const c.fexcept_t, excepts: c_int) callconv(.c) c_int {
    if (flagp) |f_ptr| {
        if (@intFromPtr(f_ptr) == std.math.maxInt(usize)) {
            return -1;
        } else {
            setExceptFlag(f_ptr.*, @truncate(@as(c_uint, @bitCast(excepts))));
        }
    }
    return 0;
}
fn fetestexcept(excepts: c_int) callconv(.c) c_int {
    if (excepts == -1) return 0;
    return @intCast(impl.testExcept(@truncate(@as(c_uint, @bitCast(excepts)))));
}

fn fegetround() callconv(.c) c_int {
    return @intCast(impl.getRound());
}
fn fesetround(rounding_mode: c_int) callconv(.c) c_int {
    const m: c.fexcept_t = @truncate(@as(c_uint, @bitCast(rounding_mode)));
    if (m & ~(c.FE.DOWNWARD | c.FE.UPWARD | c.FE.TOWARD_ZERO) != 0) return -1;
    impl.setRound(m);
    return 0;
}

fn fegetenv(envp: ?*anyopaque) callconv(.c) c_int {
    if (envp == null) {
        return 0;
    }

    if (@intFromPtr(envp.?) == std.math.maxInt(usize)) {
        return 0;
    }
    const ptr: *align(1) c.fenv_t = @ptrCast(envp.?);
    ptr.* = impl.getEnv();
    return 0;
}
fn feholdexcept(envp: ?*anyopaque) callconv(.c) c_int {
    if (envp == null) {
        return 0;
    }
    if (@intFromPtr(envp.?) == std.math.maxInt(usize)) {
        return 0;
    }
    const ptr: *align(1) c.fenv_t = @ptrCast(envp.?);
    ptr.* = holdExcept();
    return 0;
}
fn fesetenv(envp: ?*const anyopaque) callconv(.c) c_int {
    if (envp == null) {
        impl.setEnv(.{});
        return 0;
    }
    if (@intFromPtr(envp.?) == std.math.maxInt(usize)) {
        impl.setEnv(.{});
        return 0;
    }
    const ptr: *align(1) const c.fenv_t = @ptrCast(envp.?);
    impl.setEnv(ptr.*);
    return 0;
}
fn feupdateenv(envp: ?*const anyopaque) callconv(.c) c_int {
    if (envp == null) {
        updateEnv(.{});
        return 0;
    }
    if (@intFromPtr(envp.?) == std.math.maxInt(usize)) {
        updateEnv(.{});
        return 0;
    }
    const ptr: *align(1) const c.fenv_t = @ptrCast(envp.?);
    updateEnv(ptr.*);
    return 0;
}
