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
    };

    pub const Data = union(enum) {
        none,
        rrr: struct { rd: abi.Register, rj: abi.Register, rk: abi.Register },
        rri: struct { rd: abi.Register, rj: abi.Register, imm12: i32 },
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

    for (self.instructions.items) |inst| {
        const word: bits.Word = switch (inst.tag) {
            .ret => bits.ret(),
            .add_d => bits.addD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .sub_d => bits.subD(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .@"or" => bits.@"or"(inst.data.rrr.rd, inst.data.rrr.rj, inst.data.rrr.rk),
            .addi_d => bits.addiD(inst.data.rri.rd, inst.data.rri.rj, @truncate(inst.data.rri.imm12)),
        };
        try w.writeInt(u32, word, .little);
    }
}
