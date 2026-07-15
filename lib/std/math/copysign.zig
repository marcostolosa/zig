const std = @import("../std.zig");
const builtin = @import("builtin");
const math = std.math;
const expect = std.testing.expect;

/// Returns a value with the magnitude of `magnitude` and the sign of `sign`.
pub fn copysign(magnitude: anytype, sign: @TypeOf(magnitude)) @TypeOf(magnitude) {
    const T = @TypeOf(magnitude);
    const TBits, const sign_mask = switch (@typeInfo(T)) {
        .float => |f| b: {
            const TBits = @Int(.unsigned, f.bits);
            const mask = @as(TBits, 1) << (@bitSizeOf(T) - 1);
            break :b .{ TBits, mask };
        },

        .vector => |v| b: {
            const f = @typeInfo(v.child).float;
            const TBits = @Vector(v.len, @Int(.unsigned, f.bits));
            const mask = @as(TBits, @splat(1 << (@bitSizeOf(v.child) - 1)));
            break :b .{ TBits, mask };
        },

        else => @compileError("Expected a float or vector of float, found " ++ @typeName(T)),
    };

    const sign_bits = @as(TBits, @bitCast(sign)) & sign_mask;
    const magnitude_bits = @as(TBits, @bitCast(magnitude)) & ~sign_mask;

    return @bitCast(sign_bits | magnitude_bits);
}

/// Generate a namespace of tests for copysign on values of the given type
/// (patterned after the modf tests)
fn CopysignTests(comptime T: type) type {
    return struct {
        test "scalar" {
            try expect(copysign(@as(T, 1.0), @as(T, 1.0)) == 1.0);
            try expect(copysign(@as(T, 2.0), @as(T, -2.0)) == -2.0);
            try expect(copysign(@as(T, -3.0), @as(T, 3.0)) == 3.0);
            try expect(copysign(@as(T, -4.0), @as(T, -4.0)) == -4.0);
            try expect(copysign(@as(T, 5.0), @as(T, -500.0)) == -5.0);
            try expect(copysign(math.inf(T), @as(T, -0.0)) == -math.inf(T));
            try expect(copysign(@as(T, 6.0), -math.nan(T)) == -6.0);
        }

        test "vector" {
            if (builtin.os.tag.isDarwin() and builtin.cpu.arch == .aarch64) return error.SkipZigTest;
            if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest; // llvm assertion fails: `N->getValueType(0) == MVT::v1i1 && "Expected v1i1 type"`
            if (builtin.cpu.arch == .s390x) return error.SkipZigTest; // https://github.com/llvm/llvm-project/issues/194256
            if (builtin.cpu.arch == .hexagon) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/pulls/36180#issuecomment-19380871

            const widths = [_]comptime_int{ 1, 2, 3, 4, 8, 16 };

            inline for (widths) |len| {
                const V: type = @Vector(len, T);

                const vec_test = struct {
                    pub fn t(mag: comptime_float, sgn: comptime_float, expected: comptime_float) bool {
                        return @reduce(.And, copysign(@as(V, @splat(mag)), @as(V, @splat(sgn))) == @as(V, @splat(expected)));
                    }
                }.t;

                try expect(vec_test(1.0, 1.0, 1.0));
                try expect(vec_test(2.0, -2.0, -2.0));
                try expect(vec_test(-3.0, 3.0, 3.0));
                try expect(vec_test(-4.0, -4.0, -4.0));
                try expect(vec_test(5.0, -500.0, -5.0));
                try expect(vec_test(math.inf(T), -0.0, -math.inf(T)));
                try expect(vec_test(6.0, -math.nan(T), -6.0));
            }
        }
    };
}

comptime {
    for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        _ = CopysignTests(T);
    }
}
