const Mir = @This();

const std = @import("std");
const bits = @import("bits.zig");
const link = @import("../../link.zig");
const Zcu = @import("../../Zcu.zig");
const InternPool = @import("../../InternPool.zig");
const abi = @import("abi.zig");

instructions: std.ArrayList(Inst) = .empty,

pub const Inst = struct {
    tag: Tag,
    data: Data,

    pub const Tag = enum {
        ret,
        add_d,
        sub_d,
        addi_d,
        @"or",
        and_d,
        xor_d,
        sll_w,
        srl_w,
        sra_w,
        sll_d,
        srl_d,
        sra_d,
        ld_d,
        st_d,
        slt,
        sltu,
        sltui,
        beq,
        bne,
        b,
    };

    pub const Data = union(enum) {
        none,
        rrr: struct { rd: abi.Register, rj: abi.Register, rk: abi.Register },
        rri: struct { rd: abi.Register, rj: abi.Register, imm12: i12 },
        branch: struct { rj: abi.Register, rd: abi.Register, target: u32 }, // target = Inst.Index
        b: struct { target: u32 }, // target = Inst.Index
    };
};

pub fn deinit(self: *Mir, gpa: std.mem.Allocator) void {
    self.instructions.deinit(gpa);
}

pub fn emit(
    self: *const Mir,
    lf: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    atom_id: link.File.AtomId,
    w: *std.Io.Writer,
    debug_output: link.File.DebugInfoOutput,
) (link.Error || std.Io.Writer.Error)!void {
    _ = lf;
    _ = pt;
    _ = func_index;
    _ = atom_id;
    _ = debug_output;

    for (self.instructions.items, 0..) |inst, i| {
        const word: bits.Word = switch (inst.tag) {
            .ret => bits.ret(),
            .add_d => bits.addD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sub_d => bits.subD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .@"or" => bits.@"or"(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .addi_d => bits.addiD(inst.data.rri.rd, inst.data.rri.rj, inst.data.rri.imm12),
            .and_d => bits.andD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .xor_d => bits.xorD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sll_w => bits.sllW(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .srl_w => bits.srlW(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sra_w => bits.sraW(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sll_d => bits.sllD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .srl_d => bits.srlD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sra_d => bits.sraD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .ld_d => bits.ldD(inst.data.rri.rd, inst.data.rri.rj, inst.data.rri.imm12),
            .st_d => bits.stD(inst.data.rri.rd, inst.data.rri.rj, inst.data.rri.imm12),
            .slt => bits.slt(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sltu => bits.sltu(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sltui => bits.sltui(inst.data.rri.rd, inst.data.rri.rj, inst.data.rri.imm12),
            .beq => blk: {
                const offset = @as(i64, @intCast(inst.data.branch.target)) - @as(i64, @intCast(i));
                break :blk bits.beq(inst.data.branch.rj, inst.data.branch.rd, @intCast(offset));
            },
            .bne => blk: {
                const offset = @as(i64, @intCast(inst.data.branch.target)) - @as(i64, @intCast(i));
                break :blk bits.bne(inst.data.branch.rj, inst.data.branch.rd, @intCast(offset));
            },
            .b => blk: {
                const offset = @as(i64, @intCast(inst.data.b.target)) - @as(i64, @intCast(i));
                break :blk bits.b(@intCast(offset));
            },
        };
        try w.writeInt(u32, word, .little);
    }
}
