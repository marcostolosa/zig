//! Least common multiple (https://mathworld.wolfram.com/LeastCommonMultiple.html)
const std = @import("std");

/// Returns the least common multiple (LCM) of two integers (`a` and `b`) if the Type supports it
/// Otherwise throws a Memory Overflow error.
/// For example, the LCM of `8` and `12` is `24`, that is, `lcm(8, 12) == 24`.
/// If any of the arguments is zero, then the returned value is 0.
pub fn lcm(comptime T: type, a: T, b: T) (error{Overflow}!T) {
    // if an argument is 0 then returned value is 0.
    if (a == 0 or b == 0) return 0;

    // Doing the calculation in steps for some safety to make sure the intermediate steps
    // do not go out of bounds mostly to keep the number of values that can be handled more
    const safelyDivided = @abs(a) / std.math.gcd(@abs(a), @abs(b));
    const result, const err = @mulWithOverflow(safelyDivided, @abs(b));
    if (err != 0) {
        return error.Overflow;
    }

    if (std.math.cast(T, result)) |finalResult| {
        return finalResult;
    } else {
        return error.Overflow;
    }
}

/// Returns the least common multiple (LCM) of two integers (`a` and `b`) will never return an Overflow error.
/// For example, the LCM of `254` and `255` is `64770`, that is, `lcm(254, 255) == 64770`.
/// lcm implementation will return error.Overflow but lcmwide will return the value 64770
/// If any of the arguments is zero, then the returned value is 0.
pub fn lcmwide(comptime T: type, a: T, b: T) @Int(.unsigned, @typeInfo(T).int.bits + @typeInfo(T).int.bits) {
    // If an argument is zero, then the returned value is 0.
    if (a == 0 or b == 0) return 0;

    // Return Type of the lcm wide tiwe with number of bits equal to bitsize(a) + bitsize(b)
    const returnType = @Int(.unsigned, @typeInfo(T).int.bits + @typeInfo(T).int.bits);

    const valA: returnType = @as(returnType, @abs(a));
    const valB: returnType = @as(returnType, @abs(b));

    return valA * valB / std.math.gcd(valA, valB);
}

test lcm {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(lcm(i8, 0, 0), 0);
    try expectEqual(lcm(i8, 1, 0), 0);
    try expectEqual(lcm(i8, -1, 0), 0);
    try expectEqual(lcm(u8, 0, 1), 0);
    try expectEqual(lcm(i8, 0, -1), 0);
    try expectEqual(lcm(u8, 7, 1), 7);
    try expectEqual(lcm(i8, 7, -1), 7);
    try expectEqual(lcm(u8, 8, 12), 24);
    try expectEqual(lcm(i8, -23, 15), error.Overflow);
    try expectEqual(lcm(u16, 120, 84), 840);
    try expectEqual(lcm(i16, 84, -120), 840);
    try expectEqual(lcm(u16, 120, 84), 840);
    try expectEqual(lcm(u8, 255, 254), error.Overflow);
    try expectEqual(lcm(u245, 1216342683557601535506311712, 436522681849110124616458784), 16592536571065866494401400422922201534178938447014944);
}

test lcmwide {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(lcmwide(u8, 30, 133), 3990);
    try expectEqual(lcmwide(u8, 255, 254), 64770);
}
