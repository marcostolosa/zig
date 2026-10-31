const builtin = @import("builtin");
const std = @import("std");
const expect = std.testing.expect;

test "call @setCpuMode function" {
    if (!builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isThumb() and builtin.cpu.has(.arm, .noarm)) return error.SkipZigTest;

    const opposite_mode: std.lang.CpuMode = if (builtin.cpu.arch.isThumb() and comptime !builtin.cpu.has(.arm, .noarm))
        .arm
    else
        .thumb;
    const same_mode: std.lang.CpuMode = if (builtin.cpu.arch.isThumb()) .thumb else .arm;
    const S = struct {
        fn opposite(x: u8) u8 {
            @setCpuMode(opposite_mode);
            return (x +% 153) >> 3;
        }
        fn same(x: u8) u8 {
            @setCpuMode(same_mode);
            return (x +% 153) >> 3;
        }
    };

    try std.testing.expect(S.opposite(95) == 31);
    try std.testing.expect(S.same(95) == 31);
}

test "analyze @setCpuMode function" {
    if (builtin.cpu.arch.isArm() or !(builtin.cpu.arch == .x86 or builtin.cpu.arch.isMips32())) {
        return error.SkipZigTest;
    }
    if (builtin.cpu.arch == .x86 and builtin.zig_backend == .stage2_c) return error.SkipZigTest;

    const opposite_mode: std.lang.CpuMode = if (builtin.cpu.arch == .x86) .@"16" else .mips16;
    const same_mode: std.lang.CpuMode = if (builtin.cpu.arch == .x86) .@"32" else .mips;
    const S = struct {
        fn opposite(x: u8) u8 {
            @setCpuMode(opposite_mode);
            return (x +% 153) >> 3;
        }
        fn same(x: u8) u8 {
            @setCpuMode(same_mode);
            return (x +% 153) >> 3;
        }
    };

    _ = &S.opposite;
    _ = &S.same;
}
