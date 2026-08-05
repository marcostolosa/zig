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
        pcalau12i_reloc,
        ld_d_reloc,
        addi_d_reloc,
    };

    pub const Data = union {
        none: void,
        rrr: struct { rd: abi.Register, rj: abi.Register, rk: abi.Register },
        rri: struct { rd: abi.Register, rj: abi.Register, imm12: i12 },
        branch: struct { rj: abi.Register, rd: abi.Register, target: u32 }, // target = Inst.Index
        b: struct { target: u32 }, // target = Inst.Index
        reloc: struct {
            rd: abi.Register,
            sym_index: link.File.SymbolId,
        },
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
    _ = func_index;
    _ = debug_output;

    const gpa = pt.zcu.gpa;

    for (self.instructions.items, 0..) |inst, i| {
        switch (inst.tag) {
            .pcalau12i_reloc => {
                const rd = inst.data.reloc;
                try emitReloc(gpa, lf, atom_id, w, bits.pcalau12i(rd.rd, 0), rd.sym_index, @backingInt(std.elf.R_LARCH.PCALA_HI20));
                continue;
            },
            .ld_d_reloc, .addi_d_reloc => {
                const rd = inst.data.reloc;
                const word_lo = if (inst.tag == .addi_d_reloc) bits.addiD(rd.rd, rd.rd, 0) else bits.ldD(rd.rd, rd.rd, 0);
                try emitReloc(gpa, lf, atom_id, w, word_lo, rd.sym_index, @backingInt(std.elf.R_LARCH.PCALA_LO12));
                continue;
            },
            else => {},
        }

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
            .beq => bits.beq(inst.data.branch.rj, inst.data.branch.rd, @intCast(branchOffset(inst.data.branch.target, i))),
            .bne => bits.bne(inst.data.branch.rj, inst.data.branch.rd, @intCast(branchOffset(inst.data.branch.target, i))),
            .b => bits.b(@intCast(branchOffset(inst.data.b.target, i))),
            .pcalau12i_reloc, .ld_d_reloc, .addi_d_reloc => unreachable, // Processed above via continue
        };
        try w.writeInt(u32, word, .little);
    }
}

fn emitReloc(
    gpa: std.mem.Allocator,
    lf: *link.File,
    atom_id: link.File.AtomId,
    w: *std.Io.Writer,
    word: bits.Word,
    sym_index: link.File.SymbolId,
    r_type: u32,
) !void {
    const offset: u32 = @intCast(w.end);
    try w.writeInt(u32, word, .little);

    const elf_file = lf.cast(.elf).?;
    const zo = elf_file.zigObjectPtr().?;
    const atom_ptr = zo.symbol(@backingInt(atom_id)).atom(elf_file).?;
    const sym_idx = @backingInt(sym_index);

    try atom_ptr.addReloc(gpa, .{
        .r_offset = offset,
        .r_info = (@as(u64, sym_idx) << 32) | r_type,
        .r_addend = 0,
    }, zo);
}

fn branchOffset(target: u32, idx: usize) i64 {
    // TODO: bounds-check branch offsets
    return @as(i64, @intCast(target)) - @as(i64, @intCast(idx));
}
