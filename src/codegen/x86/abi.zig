const std = @import("std");
const assert = std.debug.assert;

const InternPool = @import("../../InternPool.zig");
const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");
const CallingConventionRegs = @import("../llvm.zig").CallingConventionRegs;

const ParamClass = union(enum) {
    direct,
    direct_inreg,
    indirect,
    i32_array: u8,
    i64,

    pub fn i32Array(bits: u64) ParamClass {
        const n = std.mem.alignForward(u64, bits, 32) / 32;
        return .{ .i32_array = @intCast(n) };
    }
};

pub fn classifyParamTypeWin32(
    zcu: *Zcu,
    cc: std.lang.CallingConvention,
    cc_regs: *CallingConventionRegs,
    ty: Type,
) ParamClass {
    const target = zcu.getTarget();
    if (ty.zigTypeTag(zcu) == .bool) {
        return .direct;
    }

    if (ty.isPtrAtRuntime(zcu) or ty.isAbiInt(zcu)) {
        if (cc_regs.int_regs > 0 and ty.abiSize(zcu) <= 4) {
            cc_regs.int_regs -= 1;
            return .direct_inreg;
        }

        return .direct;
    }

    if (ty.isRuntimeFloat()) {
        if (cc == .x86_vectorcall and cc_regs.float_regs > 0) {
            cc_regs.float_regs -= 1;
            return .direct_inreg;
        }

        return .direct;
    }

    if (ty.isVector(zcu)) {
        if (target.abi == .msvc) {
            if (cc_regs.float_regs > 0 and ty.totalVectorBits(zcu) <= 512) {
                cc_regs.float_regs -= 1;
                return .direct_inreg;
            }

            return .indirect;
        }

        if (ty.totalVectorBits(zcu) == 64 and ty.childType(zcu).isAbiInt(zcu)) {
            return .i64;
        }

        return .direct;
    }

    if (isAggregate(zcu, ty)) {
        if (target.abi == .msvc and aggregateIsExplicitlyOveralignedForMsvc(zcu, ty)) {
            return .indirect;
        }

        return ParamClass.i32Array(ty.bitSize(zcu));
    }

    return .indirect;
}

const ReturnClass = enum {
    none,
    direct,
    indirect,
    int,
    half,
    float,
    double,
};

pub fn classifyReturnTypeWin32(zcu: *Zcu, ty: Type) ReturnClass {
    const target = zcu.getTarget();
    if (!ty.hasRuntimeBits(zcu)) {
        return .none;
    }

    if (ty.zigTypeTag(zcu) == .bool or
        ty.isPtrAtRuntime(zcu) or
        ty.isAbiInt(zcu) or
        ty.isRuntimeFloat() or
        ty.isVector(zcu))
    {
        return .direct;
    }

    if (isAggregate(zcu, ty)) {
        if (target.abi != .msvc) {
            const sfp = aggregateIsSingleFloatingPointType(zcu, ty);
            if (sfp) |fp_ty| {
                const aggregate_align = ty.abiAlignment(zcu);
                const fp_align = fp_ty.abiAlignment(zcu);

                if (aggregate_align.compareStrict(.eq, fp_align)) {
                    switch (fp_ty.floatBits(target)) {
                        16 => return .half,
                        32 => return .float,
                        64 => return .double,
                        else => {},
                    }
                }
            }
        }

        return switch (ty.abiSize(zcu)) {
            1, 2, 4, 8 => .int,
            else => .indirect,
        };
    }

    return .indirect;
}

fn isAggregate(zcu: *Zcu, ty: Type) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .@"struct", .@"union" => true,
        else => false,
    };
}

fn aggregateIsSingleFloatingPointType(zcu: *Zcu, ty: Type) ?Type {
    const ip = &zcu.intern_pool;
    const field_count = switch (ty.zigTypeTag(zcu)) {
        .@"struct" => ip.loadStructType(ty.toIntern()).field_types.len,
        .@"union" => ip.loadUnionType(ty.toIntern()).field_types.len,
        else => return null,
    };

    var result: ?Type = null;
    var count: usize = 0;

    for (0..field_count) |i| {
        const field_ty = ty.fieldType(i, zcu);
        if (!field_ty.hasRuntimeBits(zcu)) continue;

        result = switch (field_ty.zigTypeTag(zcu)) {
            .@"struct", .@"union" => blk: {
                const inner = aggregateIsSingleFloatingPointType(zcu, field_ty);
                if (inner == null) return null;
                break :blk inner;
            },
            else => blk: {
                if (!field_ty.isRuntimeFloat()) return null;
                break :blk field_ty;
            },
        };

        count += 1;
        if (count > 1) return null;
    }

    return result;
}

fn aggregateIsExplicitlyOveralignedForMsvc(zcu: *Zcu, ty: Type) bool {
    const ip = &zcu.intern_pool;
    const explicit_aligns: InternPool.Alignment.Slice = switch (ty.zigTypeTag(zcu)) {
        .@"struct" => ip.loadStructType(ty.toIntern()).field_aligns,
        .@"union" => ip.loadUnionType(ty.toIntern()).field_aligns,
        else => return false,
    };

    for (0..explicit_aligns.len) |i| {
        const field_ty = ty.fieldType(i, zcu);
        if (!field_ty.hasRuntimeBits(zcu)) continue;

        if (aggregateIsExplicitlyOveralignedForMsvc(zcu, field_ty)) return true;

        const alignment = explicit_aligns.get(ip)[i].toByteUnits();
        if (alignment != null and alignment.? > 4) {
            return true;
        }
    }

    return false;
}
