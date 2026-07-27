// Original docs: https://loongson.github.io/LoongArch-Documentation/LoongArch-ELF-ABI-EN.html
const std = @import("std");
const Target = std.Target;
const assert = std.debug.assert;

const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");

/// LoongArch64 General Purpose Registers (32 registers)
pub const Register = enum(u5) {
    zero = 0, // Constant zero
    ra = 1, // Return address
    tp = 2, // Thread pointer
    sp = 3, // Stack pointer
    a0 = 4, // Argument registers / return value registers
    a1 = 5,
    a2 = 6,
    a3 = 7,
    a4 = 8,
    a5 = 9,
    a6 = 10,
    a7 = 11,
    t0 = 12, // Temporary registers
    t1 = 13,
    t2 = 14,
    t3 = 15,
    t4 = 16,
    t5 = 17,
    t6 = 18,
    t7 = 19,
    t8 = 20,
    // r21 - Reserved
    fp = 22, // Frame pointer / Static register ($s9)
    s0 = 23, // Static registers
    s1 = 24,
    s2 = 25,
    s3 = 26,
    s4 = 27,
    s5 = 28,
    s6 = 29,
    s7 = 30,
    s8 = 31,

    pub fn id(self: Register) u5 {
        return @backingInt(self);
    }
};

/// LoongArch64 Floating Point Registers (32 registers)
pub const FloatingPointRegister = enum(u5) {
    fa0 = 0, // Argument registers / return value registers
    fa1 = 1,
    fa2 = 2,
    fa3 = 3,
    fa4 = 4,
    fa5 = 5,
    fa6 = 6,
    fa7 = 7,
    ft0 = 8, // Temporary registers
    ft1 = 9,
    ft2 = 10,
    ft3 = 11,
    ft4 = 12,
    ft5 = 13,
    ft6 = 14,
    ft7 = 15,
    ft8 = 16,
    ft9 = 17,
    ft10 = 18,
    ft11 = 19,
    ft12 = 20,
    ft13 = 21,
    ft14 = 22,
    ft15 = 23,
    fs0 = 24, // Static registers
    fs1 = 25,
    fs2 = 26,
    fs3 = 27,
    fs4 = 28,
    fs5 = 29,
    fs6 = 30,
    fs7 = 31,

    pub fn id(self: FloatingPointRegister) u5 {
        return @backingInt(self);
    }
};

pub const stack_alignment: u32 = 16;

pub const Class = union(enum) {
    integer: Type,
    float: Type,
    pointer: Type,
    indirect,
};

pub fn classifyType(ty: Type, zcu: *const Zcu) Class {
    // const ip = &zcu.intern_pool;
    assert(ty.hasRuntimeBits(zcu));
    switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .error_set => return .{ .integer = ty },
        .float => return .{ .float = ty },
        .bool => return .{ .integer = ty },
        .vector => return .{ .integer = ty }, // Currently passing vectors as integers
        .array => return .indirect, // Pass arrays by reference
        .optional => {
            if (ty.isPtrLikeOptional(zcu)) {
                return .{ .pointer = ty };
            }
            return .indirect;
        },
        .pointer => {
            if (ty.isSlice(zcu)) {
                return .indirect;
            }
            return .{ .pointer = ty };
        },
        .@"struct", .@"union" => {
            if (ty.containerLayout(zcu) == .@"packed") {
                return .{ .integer = ty };
            }
            return .indirect;
        },
        .error_union,
        .frame,
        .@"anyframe",
        .noreturn,
        .void,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .spirv,
        .enum_literal,
        => unreachable,
    }
}
