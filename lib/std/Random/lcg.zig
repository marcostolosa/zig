//! Linear congruential generator
//!
//! X(n+1) = (a * Xn + c) mod m
//!
//! PRNG

/// Linear congruent generator where the modulo is `std.math.maxInt(T) + 1`,
/// wrapping over the integer.
pub fn Wrapping(comptime T: type) type {
    return struct {
        xi: T,
        a: T,
        c: T,

        pub fn init(xi: T, a: T, c: T) LcgSelf {
            return .{ .xi = xi, .a = a, .c = c };
        }

        pub fn next(lcg: *LcgSelf) T {
            lcg.xi = (lcg.a *% lcg.xi) +% lcg.c;
            return lcg.xi;
        }

        const LcgSelf = @This();
    };
}
