const std = @import("std");
const math = std.math;
const testing = std.testing;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__log2si2, "__log2si2");
    symbol(&__log2di2, "__log2di2");
    symbol(&__log2ti2, "__log2ti2");
}

inline fn log2Xi2(a: anytype) math.Log2IntResult(@TypeOf(a)) {
    return @intCast(@typeInfo(@TypeOf(a)).int.bits - 1 - @clz(a));
}

pub fn __log2si2(a: u32) callconv(.c) u8 {
    return log2Xi2(a);
}

pub fn __log2di2(a: u64) callconv(.c) u8 {
    return log2Xi2(a);
}

pub fn __log2ti2(a: u128) callconv(.c) u8 {
    return log2Xi2(a);
}

test __log2si2 {
    try testing.expectEqual(0, __log2si2(1));
    try testing.expectEqual(1, __log2si2(2));
    try testing.expectEqual(31, __log2si2(math.maxInt(u32)));

    try testing.expectEqual(31, __log2si2(3715621902));
    try testing.expectEqual(30, __log2si2(1586438423));
    try testing.expectEqual(28, __log2si2(293925349));
    try testing.expectEqual(31, __log2si2(2603375199));
    try testing.expectEqual(31, __log2si2(4240318981));
    try testing.expectEqual(31, __log2si2(3309655134));
    try testing.expectEqual(29, __log2si2(922917435));
    try testing.expectEqual(29, __log2si2(935840647));
}

test __log2di2 {
    try testing.expectEqual(0, __log2di2(1));
    try testing.expectEqual(1, __log2di2(2));
    try testing.expectEqual(63, __log2di2(math.maxInt(u64)));

    try testing.expectEqual(62, __log2di2(5905875944942564734));
    try testing.expectEqual(62, __log2di2(8918776106544777724));
    try testing.expectEqual(60, __log2di2(1183363062845017763));
    try testing.expectEqual(59, __log2di2(600487548862564129));
    try testing.expectEqual(59, __log2di2(903396656992693505));
    try testing.expectEqual(58, __log2di2(307286255387926602));
    try testing.expectEqual(57, __log2di2(160604707773362097));
    try testing.expectEqual(56, __log2di2(128939560012880821));
}

test __log2ti2 {
    try testing.expectEqual(0, __log2ti2(1));
    try testing.expectEqual(1, __log2ti2(2));
    try testing.expectEqual(127, __log2ti2(math.maxInt(u128)));

    try testing.expectEqual(127, __log2ti2(238139014599816174265014841345455070164));
    try testing.expectEqual(126, __log2ti2(120026386029157161835837203303054196771));
    try testing.expectEqual(125, __log2ti2(58581058832734652764005407414015317261));
    try testing.expectEqual(123, __log2ti2(12163803310079001327343285454514980931));
    try testing.expectEqual(122, __log2ti2(7516812878606214933475820886459293632));
    try testing.expectEqual(122, __log2ti2(9439996298733018249970919516780541162));
    try testing.expectEqual(117, __log2ti2(229950030354472437537610006201833109));
    try testing.expectEqual(118, __log2ti2(594320213846984243105603760823276192));
}
