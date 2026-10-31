const std = @import("std");
const Error = std.debug.SelfInfoError;

const SelfInfo = @This();

pub const can_unwind = true;

pub const init: SelfInfo = .{};
pub fn deinit(_: *SelfInfo, _: std.Io) void {}

// Stubbed out as we don't have `DWARF` available on the target
pub fn getSymbols(
    _: *SelfInfo,
    _: std.Io,
    _: std.mem.Allocator,
    _: std.mem.Allocator,
    _: usize,
    _: bool,
    _: *std.ArrayList(std.debug.Symbol),
) Error!void {
    return error.MissingDebugInfo;
}

pub fn getModuleName(
    _: *SelfInfo,
    _: std.Io,
    _: usize,
) Error![]const u8 {
    return error.MissingDebugInfo;
}

pub fn getModuleSlide(
    _: *SelfInfo,
    _: std.Io,
    _: usize,
) Error!usize {
    // No `ALSR` on the `PS2`
    return 0;
}

pub const UnwindContext = struct {
    /// How far we're going to look behind the current `$pc`
    pub const max_look_behind = 64 * 1024;
    /// Number of instructions after stack frame setup that count as prologue
    pub const max_prologue_insns = 24;
    /// End of the `EE`'s `32 MiB` of memory
    pub const ram_end = 0x200_0000;

    pc: usize,
    sp: usize,
    fp: usize,

    pub fn init(ctx: *const std.debug.cpu_context.Native) @This() {
        return .{
            .pc = ctx.getPc(),
            .sp = @truncate(ctx.r[29]),
            .fp = ctx.getFp(),
        };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn getFp(self: *@This()) usize {
        return self.fp;
    }
};

extern const __executable_start: u8;
extern const _etext: u8;

pub fn unwindFrame(_: *SelfInfo, _: std.Io, ctx: *UnwindContext) Error!usize {
    const text_start = @intFromPtr(&__executable_start);
    const text_end = @intFromPtr(&_etext);

    if (ctx.pc < text_start or ctx.pc >= text_end) return error.InvalidDebugInfo;

    const lowest = @max(text_start, ctx.pc -| UnwindContext.max_look_behind);
    var cur = ctx.pc;

    // Locate an `addiu/daddiu $sp, $sp, -N` from the current `$pc`
    const frame_size: usize = while (cur >= lowest) : (cur -= 4) {
        const insn = @as(*const u32, @ptrFromInt(cur)).*;
        switch (insn & 0xffff_0000) {
            0x27bd_0000, 0x67bd_0000 => {
                const imm: i16 = @bitCast(@as(u16, @truncate(insn)));
                if (imm < 0) break @intCast(-@as(i32, imm));
            },

            else => {},
        }
    } else return error.InvalidDebugInfo;

    const prologue_end = @min(ctx.pc, cur + 4 * UnwindContext.max_prologue_insns);
    var fp_is_base = false;
    var ra_off: ?u16 = null;
    var fp_off: ?u16 = null;
    var addr = cur + 4;

    // Decode the rest of the prologue to locate `$ra` and `$fp`'s save slots
    while (addr < prologue_end) : (addr += 4) {
        const insn = @as(*const u32, @ptrFromInt(addr)).*;
        const off: u16 = @truncate(insn);

        switch (insn & 0xffff_0000) {
            // `sd/sw/sq $ra, off($sp)`
            0xffbf_0000, 0xafbf_0000, 0x7fbf_0000 => ra_off = off,
            // `sd/sw/sq $fp, off($sp)`
            0xffbe_0000, 0xafbe_0000, 0x7fbe_0000 => fp_off = off,

            // `move $fp, $sp`
            else => if (insn == 0x03a0_f025) {
                fp_is_base = true;
            },
        }
    }

    const base = if (fp_is_base) ctx.fp else ctx.sp;
    if (base < ctx.sp or base % 8 != 0 or base + frame_size > UnwindContext.ram_end)
        return error.InvalidDebugInfo;

    const ret = @as(
        *const u32,
        @ptrFromInt(base + (ra_off orelse return error.InvalidDebugInfo)),
    ).*;
    const new_sp = base + frame_size;
    const new_fp = if (fp_off) |off| @as(*const u32, @ptrFromInt(base + off)).* else ctx.fp;

    if (ret % 4 != 0 or ret < text_start or ret >= text_end) return 0;

    ctx.* = .{ .pc = ret - 4, .sp = new_sp, .fp = new_fp };
    return ret;
}
