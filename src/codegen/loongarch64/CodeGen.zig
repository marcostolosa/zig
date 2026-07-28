const CodeGen = @This();

const std = @import("std");
const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const link = @import("../../link.zig");
const Type = @import("../../Type.zig");
const InternPool = @import("../../InternPool.zig");
const codegen = @import("../../codegen.zig");
const Mir = @import("Mir.zig");
const abi = @import("abi.zig");

pub const Error = codegen.Error;

pt: Zcu.PerThread,
gpa: std.mem.Allocator,
func_index: InternPool.Index,
air: *const Air,
liveness: *const ?Air.Liveness,
mir: Mir,
values: std.AutoHashMapUnmanaged(Air.Inst.Index, MCValue) = .empty,
arg_index: u32 = 0,
next_temp_reg: u32 = 0,

pub const MCValue = union(enum) {
    none,
    register: abi.Register,
    immediate: i64,
};

pub fn legalizeFeatures(_: *const std.Target) ?*const Air.Legalize.Features {
    return null;
}

pub fn generate(
    lf: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) Error!Mir {
    _ = lf;

    var cg: CodeGen = .{
        .pt = pt,
        .gpa = pt.zcu.gpa,
        .func_index = func_index,
        .air = air,
        .liveness = liveness,
        .mir = .{},
    };
    defer cg.values.deinit(cg.gpa);
    errdefer cg.mir.deinit(cg.gpa);

    try cg.genBody(air.getMainBody());

    return cg.mir;
}

fn genBody(cg: *CodeGen, body: []const Air.Inst.Index) Error!void {
    const air_tags = cg.air.instructions.items(.tag);
    for (body) |inst| {
        const tag = air_tags[@backingInt(inst)];
        switch (tag) {
            .ret, .ret_safe => try cg.airRet(inst),
            .arg => try cg.airArg(inst),
            .add, .add_wrap, .add_safe => try cg.airArithOp(inst, .add_d),
            .sub, .sub_wrap, .sub_safe => try cg.airArithOp(inst, .sub_d),
            .bit_and => try cg.airArithOp(inst, .and_d),
            .bit_or => try cg.airArithOp(inst, .@"or"),
            .xor => try cg.airArithOp(inst, .xor_d),
            .shl, .shl_exact, .shr, .shr_exact => try cg.airShift(inst),
            .int_cast, .int_cast_safe, .trunc => try cg.airIntCast(inst),
            // Ignore debug instructions during the MVP
            .dbg_stmt, .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline, .dbg_empty_stmt => {},
            else => return cg.fail("TODO: implement AIR tag {s}", .{@tagName(tag)}),
        }
    }
}

fn airRet(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const zcu = cg.pt.zcu;
    const func = zcu.funcInfo(cg.func_index);
    const fn_ty = Type.fromInterned(func.ty);
    const ret_ty = fn_ty.fnReturnType(zcu);

    if (ret_ty.hasRuntimeBits(zcu)) {
        const un_op = cg.air.instructions.items(.data)[@backingInt(inst)].un_op;
        const ret_val = cg.resolveInst(un_op);

        switch (ret_val) {
            .register => |reg| {
                if (reg != .a0) {
                    // Move result to a0: or a0, reg, $zero
                    try cg.mir.instructions.append(cg.gpa, .{
                        .tag = .@"or",
                        .data = .{ .rrr = .{ .rd = .a0, .rj = reg, .rk = .zero } },
                    });
                }
            },
            .immediate => |imm| {
                // Load immediate into a0: addi.d a0, $zero, imm
                try cg.mir.instructions.append(cg.gpa, .{
                    .tag = .addi_d,
                    .data = .{ .rri = .{ .rd = .a0, .rj = .zero, .imm12 = @intCast(imm) } },
                });
            },
            else => return cg.fail("TODO: return value of type {s}", .{@tagName(ret_val)}),
        }
    }
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .ret,
        .data = .{ .none = {} },
    });
}

fn airArg(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const arg_index = cg.arg_index;
    cg.arg_index += 1;

    const regs = [_]abi.Register{ .a0, .a1, .a2, .a3, .a4, .a5, .a6, .a7 };

    if (arg_index >= regs.len) {
        return cg.fail("TODO: handle stack arguments", .{});
    }

    const reg = regs[@intCast(arg_index)];
    try cg.values.put(cg.gpa, inst, .{ .register = reg });
}

fn airArithOp(cg: *CodeGen, inst: Air.Inst.Index, tag: Mir.Inst.Tag) Error!void {
    const bin_op = cg.air.instructions.items(.data)[@backingInt(inst)].bin_op;
    const lhs = cg.resolveInst(bin_op.lhs);
    const rhs = cg.resolveInst(bin_op.rhs);

    const lhs_reg = switch (lhs) {
        .register => |r| r,
        .immediate => |imm| blk: {
            const reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .addi_d,
                .data = .{ .rri = .{ .rd = reg, .rj = .zero, .imm12 = @intCast(imm) } },
            });
            break :blk reg;
        },
        else => return cg.fail("TODO: arith op lhs", .{}),
    };

    const rhs_reg = switch (rhs) {
        .register => |r| r,
        .immediate => |imm| blk: {
            const reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .addi_d,
                .data = .{ .rri = .{ .rd = reg, .rj = .zero, .imm12 = @intCast(imm) } },
            });
            break :blk reg;
        },
        else => return cg.fail("TODO: arith op rhs", .{}),
    };

    const dst_reg = cg.allocReg();
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = tag,
        .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } },
    });

    try cg.values.put(cg.gpa, inst, .{ .register = dst_reg });
}

fn airIntCast(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const ty_op = cg.air.instructions.items(.data)[@backingInt(inst)].ty_op;
    const operand = cg.resolveInst(ty_op.operand);

    switch (operand) {
        .register, .immediate => {
            try cg.values.put(cg.gpa, inst, operand);
        },
        .none => return cg.fail("airIntCast: operand not found in values map", .{}),
    }
}

fn airShift(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const zcu = cg.pt.zcu;
    const tag = cg.air.instructions.items(.tag)[@backingInt(inst)];
    const bin_op = cg.air.instructions.items(.data)[@backingInt(inst)].bin_op;

    const lhs_ty = cg.air.typeOf(bin_op.lhs, &zcu.intern_pool);
    const is_64bit = lhs_ty.bitSize(zcu) == 64;
    
    const mir_tag: Mir.Inst.Tag = switch (tag) {
        .shl, .shl_exact => if (is_64bit) .sll_d else .sll_w,
        .shr, .shr_exact => if (lhs_ty.isSignedInt(zcu))
            (if (is_64bit) .sra_d else .sra_w)
        else
            (if (is_64bit) .srl_d else .srl_w),
        else => unreachable,
    };

    try cg.airArithOp(inst, mir_tag);
}

// TODO: Replace naive round-robin register alloc with proper liveness tracking/linear scan
fn allocReg(cg: *CodeGen) abi.Register {
    const temps = [_]abi.Register{ .t0, .t1, .t2, .t3, .t4, .t5, .t6, .t7, .t8 };
    const reg = temps[cg.next_temp_reg % temps.len];
    cg.next_temp_reg += 1;
    return reg;
}

fn resolveInst(cg: *CodeGen, ref: Air.Inst.Ref) MCValue {
    if (ref.toIndex()) |inst_index| {
        return cg.values.get(inst_index) orelse .none;
    }
    return .none;
}

fn fail(cg: *CodeGen, comptime fmt: []const u8, args: anytype) Error {
    @branchHint(.cold);
    return cg.pt.zcu.codegenFail(cg.pt.zcu.funcInfo(cg.func_index).owner_nav, fmt, args);
}

pub fn generateLazy(
    lf: *link.File,
    pt: Zcu.PerThread,
    lazy_sym: link.File.LazySymbol,
    atom_id: link.File.AtomId,
    w: *std.Io.Writer,
    debug_output: link.File.DebugInfoOutput,
) (link.Error || std.Io.Writer.Error)!void {
    @branchHint(.cold);
    _ = pt;
    _ = lazy_sym;
    _ = atom_id;
    _ = w;
    _ = debug_output;

    const diags = &lf.comp.link_diags;
    diags.fail("TODO: generateLazy in loongarch64", .{}) catch return error.OutOfMemory;
    return error.LinkFailure;
}
