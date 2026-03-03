//! Based on https://graphics.stanford.edu/~seander/bithacks.html#IntegerLog10

const std = @import("std");
const math = std.math;
const testing = std.testing;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__log10si2, "__log10si2");
    symbol(&__log10di2, "__log10di2");
    symbol(&__log10ti2, "__log10ti2");
}

fn makePowers(comptime T: type) [math.log10(math.maxInt(T)) + 1]T {
    const size = math.log10(math.maxInt(T)) + 1;
    var powers: [size]T = undefined;
    for (&powers, 0..) |*y, i| {
        y.* = math.powi(T, 10, i) catch unreachable;
    }
    return powers;
}

const powers_32 = makePowers(u32);
const powers_64 = makePowers(u64);
const powers_128 = makePowers(u128);

inline fn log10Xi2(a: anytype) math.Log10IntResult(@TypeOf(a)) {
    const T = @TypeOf(a);

    const powers = switch (@bitSizeOf(T)) {
        32 => &powers_32,
        64 => &powers_64,
        128 => &powers_128,
        else => @compileError("bad integer size"),
    };

    const log2_plus_one: T = @typeInfo(T).int.bits - @clz(a);
    const t = log2_plus_one * 1233 >> 12;
    return @intCast(t - @intFromBool(a < powers[@intCast(t)]));
}

pub fn __log10si2(a: u32) callconv(.c) u8 {
    return log10Xi2(a);
}

pub fn __log10di2(a: u64) callconv(.c) u8 {
    return log10Xi2(a);
}

pub fn __log10ti2(a: u128) callconv(.c) u8 {
    return log10Xi2(a);
}

test __log10si2 {
    try testing.expectEqual(0, __log10si2(1));
    try testing.expectEqual(1, __log10si2(10));
    try testing.expectEqual(9, __log10si2(math.maxInt(u32)));

    try testing.expectEqual(9, __log10si2(3848813595));
    try testing.expectEqual(9, __log10si2(2015373390));
    try testing.expectEqual(8, __log10si2(324489896));
    try testing.expectEqual(8, __log10si2(116731104));
    try testing.expectEqual(7, __log10si2(79357470));
    try testing.expectEqual(8, __log10si2(114630836));
    try testing.expectEqual(5, __log10si2(582761));
    try testing.expectEqual(7, __log10si2(31171823));
}

test __log10di2 {
    try testing.expectEqual(0, __log10di2(1));
    try testing.expectEqual(1, __log10di2(10));
    try testing.expectEqual(19, __log10di2(math.maxInt(u64)));

    try testing.expectEqual(19, __log10di2(16731436938436565272));
    try testing.expectEqual(18, __log10di2(3411951192151278702));
    try testing.expectEqual(17, __log10di2(339560690086256605));
    try testing.expectEqual(16, __log10di2(45932705153360101));
    try testing.expectEqual(16, __log10di2(42734419975174141));
    try testing.expectEqual(15, __log10di2(9437000118809764));
    try testing.expectEqual(15, __log10di2(1477543028381389));
    try testing.expectEqual(14, __log10di2(531714738723648));
}

test __log10ti2 {
    try testing.expectEqual(0, __log10ti2(1));
    try testing.expectEqual(1, __log10ti2(10));
    try testing.expectEqual(38, __log10ti2(math.maxInt(u128)));

    try testing.expectEqual(38, __log10ti2(306840740199468424462624809972888822679));
    try testing.expectEqual(37, __log10ti2(17178738026631335573577367156484275679));
    try testing.expectEqual(35, __log10ti2(220733650502074312199918985591421101));
    try testing.expectEqual(34, __log10ti2(13481913885638457322166544164531899));
    try testing.expectEqual(33, __log10ti2(2564216044796526250052364279406680));
    try testing.expectEqual(31, __log10ti2(19836604604059760374040642913102));
    try testing.expectEqual(30, __log10ti2(4107140261644268868428939521891));
    try testing.expectEqual(29, __log10ti2(659919797534839461574146348568));
}
