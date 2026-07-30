const CodeGen = @This();

const std = @import("std");
const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const link = @import("../../link.zig");
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const InternPool = @import("../../InternPool.zig");
const codegen = @import("../../codegen.zig");
const Mir = @import("Mir.zig");
const abi = @import("abi.zig");

pub const Error = codegen.Error;

pt: Zcu.PerThread,
lf: *link.File,
gpa: std.mem.Allocator,
func_index: InternPool.Index,
air: *const Air,
liveness: *const ?Air.Liveness,
mir: Mir,
values: std.AutoHashMapUnmanaged(Air.Inst.Index, MCValue) = .empty,
block_fixups: std.AutoHashMapUnmanaged(Air.Inst.Index, std.ArrayListUnmanaged(u32)) = .empty,
loop_starts: std.AutoHashMapUnmanaged(Air.Inst.Index, u32) = .empty,
arg_index: u32 = 0,
next_temp_reg: u32 = 0,
next_stack_offset: i32 = 0,

const frame_size: i32 = 256;
const ra_offset: i32 = frame_size - 8; // 248
const fp_offset: i32 = frame_size - 16; // 240

comptime {
    std.debug.assert(ra_offset >= std.math.minInt(i12) and ra_offset <= std.math.maxInt(i12));
    std.debug.assert(fp_offset >= std.math.minInt(i12) and fp_offset <= std.math.maxInt(i12));
}

pub const SymbolOffset = struct {
    sym_index: link.File.SymbolId,
    off: i32 = 0,
};

pub const MCValue = union(enum) {
    none,
    register: abi.Register,
    immediate: i64,
    stack_offset: i32,
    lea_symbol: SymbolOffset,
    load_symbol: SymbolOffset,
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
    var cg: CodeGen = .{
        .pt = pt,
        .lf = lf,
        .gpa = pt.zcu.gpa,
        .func_index = func_index,
        .air = air,
        .liveness = liveness,
        .mir = .{},
    };
    defer cg.values.deinit(cg.gpa);
    defer {
        var it = cg.block_fixups.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(cg.gpa);
        cg.block_fixups.deinit(cg.gpa);
        cg.loop_starts.deinit(cg.gpa);
    }
    errdefer cg.mir.deinit(cg.gpa);

    try cg.genPrologue();
    try cg.genBody(air.getMainBody());

    return cg.mir;
}

fn genBody(cg: *CodeGen, body: []const Air.Inst.Index) Error!void {
    const zcu = cg.pt.zcu;
    const ip = &zcu.intern_pool;
    const air_tags = cg.air.instructions.items(.tag);
    const liveness = cg.liveness.* orelse return cg.fail("liveness analysis is missing", .{});

    for (body) |inst| {
        if (liveness.isUnused(inst) and !cg.air.mustLower(inst, ip)) continue;

        const tag = air_tags[@backingInt(inst)];
        switch (tag) {
            .ret, .ret_safe => try cg.airRet(inst),
            .arg => try cg.airArg(inst),
            .add, .add_wrap, .add_safe, .add_optimized => try cg.airArithOp(inst, .add_d),
            .sub, .sub_wrap, .sub_safe, .sub_optimized => try cg.airArithOp(inst, .sub_d),
            .bit_and => try cg.airArithOp(inst, .and_d),
            .bit_or => try cg.airArithOp(inst, .@"or"),
            .xor => try cg.airArithOp(inst, .xor_d),
            .shl, .shl_exact, .shr, .shr_exact => try cg.airShift(inst),
            .int_cast, .int_cast_safe, .trunc => try cg.airIntCast(inst),
            .alloc => try cg.airAlloc(inst),
            .store, .store_safe => try cg.airStore(inst),
            .load => try cg.airLoad(inst),

            .cmp_eq, .cmp_eq_optimized => try cg.airCmp(inst, .eq),
            .cmp_neq, .cmp_neq_optimized => try cg.airCmp(inst, .neq),
            .cmp_gt, .cmp_gt_optimized => try cg.airCmp(inst, .gt),
            .cmp_gte, .cmp_gte_optimized => try cg.airCmp(inst, .gte),
            .cmp_lt, .cmp_lt_optimized => try cg.airCmp(inst, .lt),
            .cmp_lte, .cmp_lte_optimized => try cg.airCmp(inst, .lte),

            .cond_br => try cg.airCondBr(inst),
            .block => try cg.airBlock(inst),
            .br => try cg.airBr(inst),
            .loop => try cg.airLoop(inst),
            .repeat => try cg.airRepeat(inst),
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
        const ret_val = try cg.resolveInst(un_op);

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
            .immediate, .lea_symbol, .load_symbol => {
                const ret_reg = try cg.resolveToReg(ret_val);
                if (ret_reg != .a0) {
                    try cg.mir.instructions.append(cg.gpa, .{
                        .tag = .@"or",
                        .data = .{ .rrr = .{ .rd = .a0, .rj = ret_reg, .rk = .zero } },
                    });
                }
            },
            else => return cg.fail("TODO: return value of type {s}", .{@tagName(ret_val)}),
        }
    }
    // Epilogue, recover $ra and $fp and clear the stack
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .ld_d,
        .data = .{ .rri = .{ .rd = .ra, .rj = .sp, .imm12 = try cg.imm12(ra_offset) } },
    });
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .ld_d,
        .data = .{ .rri = .{ .rd = .fp, .rj = .sp, .imm12 = try cg.imm12(fp_offset) } },
    });
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .addi_d,
        .data = .{ .rri = .{ .rd = .sp, .rj = .sp, .imm12 = try cg.imm12(frame_size) } },
    });

    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .ret,
        .data = .{ .none = {} },
    });
}

fn genPrologue(cg: *CodeGen) Error!void {
    // Select the stack frame: addi.d $sp, $sp, -frame_size
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .addi_d,
        .data = .{ .rri = .{ .rd = .sp, .rj = .sp, .imm12 = try cg.imm12(-frame_size) } },
    });
    // Save $ra: st.d $ra, $sp, ra_offset
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .st_d,
        .data = .{ .rri = .{ .rd = .ra, .rj = .sp, .imm12 = try cg.imm12(ra_offset) } },
    });
    // Save $fp: st.d $fp, $sp, fp_offset
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .st_d,
        .data = .{ .rri = .{ .rd = .fp, .rj = .sp, .imm12 = try cg.imm12(fp_offset) } },
    });
    // Set up a new $fp: addi.d $fp, $sp, frame_size
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .addi_d,
        .data = .{ .rri = .{ .rd = .fp, .rj = .sp, .imm12 = try cg.imm12(frame_size) } },
    });
}

fn airAlloc(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    cg.next_stack_offset += 8; // TODO
    if (cg.next_stack_offset >= fp_offset) {
        return cg.fail("Stack frame overflow", .{});
    }
    try cg.values.put(cg.gpa, inst, .{ .stack_offset = cg.next_stack_offset });
}

fn airStore(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const bin_op = cg.air.instructions.items(.data)[@backingInt(inst)].bin_op;
    const ptr = try cg.resolveInst(bin_op.lhs);
    const val = try cg.resolveInst(bin_op.rhs);

    const src_reg = try cg.resolveToReg(val);

    switch (ptr) {
        .stack_offset => |off| {
            // TODO: Choose store instruction based on type size (e.g., st.w for i32)
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .st_d,
                .data = .{ .rri = .{ .rd = src_reg, .rj = .sp, .imm12 = try cg.imm12(off) } },
            });
        },
        .lea_symbol => {
            const addr_reg = try cg.resolveToReg(ptr);
            // TODO: Choose store instruction based on type size (e.g., st.w for i32)
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .st_d,
                .data = .{ .rri = .{ .rd = src_reg, .rj = addr_reg, .imm12 = 0 } },
            });
        },
        else => return cg.fail("TODO: airStore ptr", .{}),
    }
}

fn airLoad(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const ty_op = cg.air.instructions.items(.data)[@backingInt(inst)].ty_op;
    const ptr = try cg.resolveInst(ty_op.operand);

    switch (ptr) {
        .stack_offset => |off| {
            const dst_reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .ld_d,
                .data = .{ .rri = .{ .rd = dst_reg, .rj = .sp, .imm12 = try cg.imm12(off) } },
            });
            try cg.values.put(cg.gpa, inst, .{ .register = dst_reg });
        },
        .lea_symbol => |sym| {
            try cg.values.put(cg.gpa, inst, .{ .load_symbol = sym });
        },
        else => return cg.fail("TODO: airLoad ptr", .{}),
    }
}

fn airCmp(cg: *CodeGen, inst: Air.Inst.Index, op: std.math.CompareOperator) Error!void {
    const bin_op = cg.air.instructions.items(.data)[@backingInt(inst)].bin_op;
    const lhs = try cg.resolveInst(bin_op.lhs);
    const rhs = try cg.resolveInst(bin_op.rhs);
    const lhs_reg = try cg.resolveToReg(lhs);
    const rhs_reg = try cg.resolveToReg(rhs);

    const lhs_ty = cg.air.typeOf(bin_op.lhs, &cg.pt.zcu.intern_pool);
    const is_signed = lhs_ty.isSignedInt(cg.pt.zcu);
    const dst_reg = cg.allocReg();

    switch (op) {
        .eq => {
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .xor_d, .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } } });
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .sltui, .data = .{ .rri = .{ .rd = dst_reg, .rj = dst_reg, .imm12 = 1 } } });
        },
        .neq => {
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .xor_d, .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } } });
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .sltu, .data = .{ .rrr = .{ .rd = dst_reg, .rj = .zero, .rk = dst_reg } } });
        },
        .lt => {
            const mir_tag: Mir.Inst.Tag = if (is_signed) .slt else .sltu;
            try cg.mir.instructions.append(cg.gpa, .{ .tag = mir_tag, .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } } });
        },
        .lte => {
            const mir_tag: Mir.Inst.Tag = if (is_signed) .slt else .sltu;
            try cg.mir.instructions.append(cg.gpa, .{ .tag = mir_tag, .data = .{ .rrr = .{ .rd = dst_reg, .rj = rhs_reg, .rk = lhs_reg } } });
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .sltui, .data = .{ .rri = .{ .rd = dst_reg, .rj = dst_reg, .imm12 = 1 } } });
        },
        .gt => {
            const mir_tag: Mir.Inst.Tag = if (is_signed) .slt else .sltu;
            try cg.mir.instructions.append(cg.gpa, .{ .tag = mir_tag, .data = .{ .rrr = .{ .rd = dst_reg, .rj = rhs_reg, .rk = lhs_reg } } });
        },
        .gte => {
            const mir_tag: Mir.Inst.Tag = if (is_signed) .slt else .sltu;
            try cg.mir.instructions.append(cg.gpa, .{ .tag = mir_tag, .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } } });
            try cg.mir.instructions.append(cg.gpa, .{ .tag = .sltui, .data = .{ .rri = .{ .rd = dst_reg, .rj = dst_reg, .imm12 = 1 } } });
        },
    }
    try cg.values.put(cg.gpa, inst, .{ .register = dst_reg });
}

fn airCondBr(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const cond_br = cg.air.unwrapCondBr(inst);
    const cond_val = try cg.resolveInst(cond_br.condition);
    const cond_reg = try cg.resolveToReg(cond_val);

    const beq_inst_idx: u32 = @intCast(cg.mir.instructions.items.len);
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = .beq,
        .data = .{ .branch = .{ .rj = cond_reg, .rd = .zero, .target = 0 } },
    });

    try cg.genBody(cond_br.then_body);

    const jmp_reloc = try cg.jump();

    cg.mir.instructions.items[beq_inst_idx].data.branch.target = @intCast(cg.mir.instructions.items.len);

    try cg.genBody(cond_br.else_body);

    cg.performReloc(jmp_reloc);
}

fn airBlock(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const block_data = cg.air.unwrapBlock(inst);
    try cg.genBody(block_data.body);

    if (cg.block_fixups.fetchRemove(inst)) |entry| {
        var fixups = entry.value;
        defer fixups.deinit(cg.gpa);
        for (fixups.items) |idx| {
            cg.performReloc(idx);
        }
    }
    try cg.values.put(cg.gpa, inst, .none); // block do not return values yet
}

fn airBr(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const br = cg.air.instructions.items(.data)[@backingInt(inst)].br;

    if (cg.loop_starts.get(br.block_inst)) |loop_start| {
        // It is a loop, jump backwards to the start
        try cg.mir.instructions.append(cg.gpa, .{ .tag = .b, .data = .{ .b = .{ .target = loop_start } } });
    } else {
        // It is a block, jump forwards to the end (will be patched later)
        const reloc = try cg.jump();
        const gop = try cg.block_fixups.getOrPut(cg.gpa, br.block_inst);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(cg.gpa, reloc);
    }
}

fn airLoop(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const loop_data = cg.air.unwrapBlock(inst);
    const loop_start_idx: u32 = @intCast(cg.mir.instructions.items.len);

    try cg.loop_starts.put(cg.gpa, inst, loop_start_idx);
    try cg.genBody(loop_data.body);
    _ = cg.loop_starts.remove(inst);

    try cg.mir.instructions.append(cg.gpa, .{ .tag = .b, .data = .{ .b = .{ .target = loop_start_idx } } });
}

fn airRepeat(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const repeat = cg.air.instructions.items(.data)[@backingInt(inst)].repeat;
    const loop_start = cg.loop_starts.get(repeat.loop_inst) orelse return cg.fail("airRepeat: loop start not found", .{});

    try cg.mir.instructions.append(cg.gpa, .{ .tag = .b, .data = .{ .b = .{ .target = loop_start } } });
}

fn jump(cg: *CodeGen) Error!u32 {
    const idx: u32 = @intCast(cg.mir.instructions.items.len);
    try cg.mir.instructions.append(cg.gpa, .{ .tag = .b, .data = .{ .b = .{ .target = 0 } } });
    return idx;
}

fn performReloc(cg: *CodeGen, reloc: u32) void {
    cg.mir.instructions.items[reloc].data.b.target = @intCast(cg.mir.instructions.items.len);
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
    const lhs = try cg.resolveInst(bin_op.lhs);
    const rhs = try cg.resolveInst(bin_op.rhs);

    const lhs_reg = try cg.resolveToReg(lhs);
    const rhs_reg = try cg.resolveToReg(rhs);

    const dst_reg = cg.allocReg();
    try cg.mir.instructions.append(cg.gpa, .{
        .tag = tag,
        .data = .{ .rrr = .{ .rd = dst_reg, .rj = lhs_reg, .rk = rhs_reg } },
    });

    try cg.values.put(cg.gpa, inst, .{ .register = dst_reg });
}

fn airIntCast(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const ty_op = cg.air.instructions.items(.data)[@backingInt(inst)].ty_op;
    const operand = try cg.resolveInst(ty_op.operand);

    switch (operand) {
        .register, .immediate, .lea_symbol, .load_symbol => {
            try cg.values.put(cg.gpa, inst, operand);
        },
        .stack_offset => unreachable, // int_cast/trunc never operate on pointers
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

fn imm12(cg: *CodeGen, v: i64) Error!i12 {
    if (v < std.math.minInt(i12) or v > std.math.maxInt(i12)) {
        return cg.fail("TODO: immediate {d} out of i12 range, needs register materialization", .{v});
    }
    return @intCast(v);
}

fn resolveToReg(cg: *CodeGen, val: MCValue) Error!abi.Register {
    return switch (val) {
        .register => |r| r,
        .immediate => |imm| blk: {
            const reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .addi_d,
                .data = .{ .rri = .{ .rd = reg, .rj = .zero, .imm12 = try cg.imm12(imm) } },
            });
            break :blk reg;
        },
        .lea_symbol => |sym| blk: {
            const reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .pcalau12i_reloc,
                .data = .{ .reloc = .{ .rd = reg, .sym_index = sym.sym_index } },
            });
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .addi_d_reloc,
                .data = .{ .reloc = .{ .rd = reg, .sym_index = sym.sym_index } },
            });
            break :blk reg;
        },
        .load_symbol => |sym| blk: {
            const reg = cg.allocReg();
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .pcalau12i_reloc,
                .data = .{ .reloc = .{ .rd = reg, .sym_index = sym.sym_index } },
            });
            // TODO: Choose load instruction based on type size (e.g., ld.w for i32)
            try cg.mir.instructions.append(cg.gpa, .{
                .tag = .ld_d_reloc,
                .data = .{ .reloc = .{ .rd = reg, .sym_index = sym.sym_index } },
            });
            break :blk reg;
        },
        else => cg.fail("TODO: resolveToReg: unsupported MCValue {s}", .{@tagName(val)}),
    };
}

fn resolveInst(cg: *CodeGen, ref: Air.Inst.Ref) Error!MCValue {
    const zcu = cg.pt.zcu;
    const ip = &zcu.intern_pool;

    // If this is a link to instruction, look for it in HashMap
    if (ref.toIndex()) |inst_index| {
        return cg.values.get(inst_index) orelse .none;
    }

    // If this is a constant (immediate), extract it from InternPool
    if (ref.toInterned()) |ip_index| {
        const val: Value = .fromInterned(ip_index);
        if (val.isUndef(zcu)) return .none;

        const ty = val.typeOf(zcu);
        switch (ty.zigTypeTag(zcu)) {
            .pointer => {
                const ptr_info = ip.indexToKey(ip_index).ptr;
                switch (ptr_info.base_addr) {
                    .nav => |nav| {
                        const elf_file = cg.lf.cast(.elf) orelse return cg.fail("TODO: non-ELF linker for LoongArch", .{});
                        const zo = elf_file.zigObjectPtr().?;
                        const sym = zo.navs.get(nav) orelse return cg.fail("Symbol for nav {} not found", .{nav});
                        // TODO: handle ptr_info.byte_offset for struct/arrays fields
                        // Currently defaults to 0, which works for simple vars but breaks for fields
                        return .{ .lea_symbol = .{ .sym_index = @fromBackingInt(@intCast(sym.symbol_index)) } };
                    },
                    else => return cg.fail("TODO: resolve pointer base_addr {s}", .{@tagName(ptr_info.base_addr)}),
                }
            },
            .int, .bool, .@"enum", .error_set => {
                const info = ty.intInfo(zcu);
                if (info.bits <= 64) {
                    const imm: i64 = switch (info.signedness) {
                        .signed => val.toSignedInt(zcu),
                        .unsigned => @bitCast(val.toUnsignedInt(zcu)),
                    };
                    return .{ .immediate = imm };
                }
            },
            else => {},
        }
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
