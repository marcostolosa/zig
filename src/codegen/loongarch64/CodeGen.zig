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

pub const MCValue = union(enum) {
    none,
    register: abi.Register,
    immediate: i64,
};

pub fn legalizeFeatures(target: *const std.Target) ?*const Air.Legalize.Features {
    _ = target;
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
                    return cg.fail("TODO: move return value to a0", .{});
                }
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
