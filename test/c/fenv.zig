const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "fenv rounding" {
    if (builtin.target.os.tag != .linux and
        builtin.target.os.tag != .windows and
        builtin.target.os.tag != .wasi and
        builtin.os.tag != .freebsd and
        builtin.os.tag != .openbsd) return error.SkipZigTest;
    //
    // // Linking issue with aarch64-freebsd target
    if (builtin.os.tag == .freebsd and (builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be)) return error.SkipZigTest;
    if (builtin.os.tag == .windows and builtin.abi == .msvc) return error.SkipZigTest;
    if (builtin.abi.isGnu()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    _ = c.fesetround(@intCast(c.FE.DOWNWARD));
    try std.testing.expectEqual(@as(c_int, c.FE.DOWNWARD), c.fegetround());
    _ = c.fesetround(@intCast(c.FE.TOWARD_ZERO));
    try std.testing.expectEqual(@as(c_int, c.FE.TOWARD_ZERO), c.fegetround());
    _ = c.fesetround(@intCast(c.FE.TO_NEAREST));
    try std.testing.expectEqual(@as(c_int, c.FE.TO_NEAREST), c.fegetround());
    _ = c.fesetround(@intCast(c.FE.UPWARD));
    try std.testing.expectEqual(@as(c_int, c.FE.UPWARD), c.fegetround());

    // https://lists.gnu.org/archive/html/bug-gnulib/2025-06/msg00104.html
    if (builtin.os.tag != .windows) {
        const two100: f32 = 0x1p100;

        var env: c.fenv_t = .{};
        _ = c.fegetenv(&env);
        const g = c.fegetround();
        const env2: c.fenv_t = .{};

        _ = c.fesetenv(&env2);
        try std.testing.expectEqual(@as(c_int, c.FE.TO_NEAREST), c.fegetround());
        try std.testing.expectEqual(two100, two100 + 1);
        try std.testing.expectEqual(two100, two100 - 1);

        _ = c.fesetenv(&env);
        try std.testing.expectEqual(g, c.fegetround());

        _ = c.fesetenv(&env2);
    }
}

test "fenv except" {
    if (builtin.target.os.tag != .linux and
        builtin.target.os.tag != .windows and
        builtin.target.os.tag != .wasi and
        builtin.os.tag != .freebsd and
        builtin.os.tag != .openbsd) return error.SkipZigTest;

    // Linking issue with aarch64-freebsd target
    if (builtin.os.tag == .freebsd and (builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .aarch64_be)) return error.SkipZigTest;
    if (builtin.os.tag == .windows and builtin.abi == .msvc) return error.SkipZigTest;
    if (builtin.abi.isGnu()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    _ = c.feclearexcept(@intCast(c.FE.ALL_EXCEPT));
    _ = c.feraiseexcept(@intCast(c.FE.DIV_BY_ZERO));
    try std.testing.expectEqual(@as(c_int, c.FE.DIV_BY_ZERO), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

    _ = c.feclearexcept(@intCast(c.FE.ALL_EXCEPT));
    _ = c.feraiseexcept(@intCast(c.FE.INEXACT));
    try std.testing.expectEqual(@as(c_int, c.FE.INEXACT), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

    _ = c.feclearexcept(@intCast(c.FE.ALL_EXCEPT));
    _ = c.feraiseexcept(@intCast(c.FE.INVALID));
    try std.testing.expectEqual(@as(c_int, c.FE.INVALID), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

    _ = c.feclearexcept(@intCast(c.FE.ALL_EXCEPT));
    _ = c.feraiseexcept(@intCast(c.FE.UNDERFLOW));
    var res = c.fetestexcept(@intCast(c.FE.ALL_EXCEPT));
    if (res != @as(c_int, c.FE.UNDERFLOW)) {
        try std.testing.expectEqual(@as(c_int, c.FE.UNDERFLOW | c.FE.INEXACT), res);
    }

    _ = c.feclearexcept(@intCast(c.FE.ALL_EXCEPT));
    _ = c.feraiseexcept(@intCast(c.FE.OVERFLOW));
    res = c.fetestexcept(@intCast(c.FE.ALL_EXCEPT));
    if (res != @as(c_int, c.FE.OVERFLOW)) {
        try std.testing.expectEqual(@as(c_int, c.FE.OVERFLOW | c.FE.INEXACT), res);
    }

    if (builtin.os.tag != .windows) {
        var env: c.fenv_t = .{};
        const env2: c.fenv_t = .{};

        _ = c.feraiseexcept(@intCast(c.FE.ALL_EXCEPT));
        _ = c.fegetenv(&env);
        try std.testing.expectEqual(@as(c_int, c.FE.ALL_EXCEPT), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

        _ = c.fesetenv(&env2);
        try std.testing.expectEqual(@as(c_int, 0), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

        _ = c.fesetenv(&env);
        try std.testing.expectEqual(@as(c_int, c.FE.ALL_EXCEPT), c.fetestexcept(@intCast(c.FE.ALL_EXCEPT)));

        _ = c.fesetenv(&env2);
    }
}
