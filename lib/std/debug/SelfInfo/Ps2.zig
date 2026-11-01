const std = @import("std");
const elf = std.elf;
const ps2 = std.os.ps2;
const Error = std.debug.SelfInfoError;

const SelfInfo = @This();

/// Holds the image's `.symtab` and `.strtab` sections, read into memory on first lookup
symbols: Symbols = .unloaded,

pub const can_unwind = true;

const Symbols = union(enum) {
    unloaded,
    missing,
    loaded: struct {
        symtab: std.debug.ElfFile.SymtabSection,
        strtab: []const u8,

        search_table: ?[]usize = null,
    },
};

const SymbolTables = struct {
    symtab_off: u32,
    symtab_size: u32,
    symtab_entry_size: u32,

    strtab_off: u32,
    strtab_size: u32,
};

/// Handrolled wrapper around `file_io` as the `std.debug` `Io` instance does not support
/// file access.
const File = struct {
    client: ps2.file_io.Client,
    fd: i32,

    fn init(path: []const u8) Error!@This() {
        const client = ps2.rpc.Rpc.acquire().bind(.file_io) catch return error.MissingDebugInfo;
        const fd = ps2.file_io.open(client, path, .{}) catch return error.MissingDebugInfo;
        return .{ .client = client, .fd = fd };
    }

    fn deinit(self: @This()) void {
        ps2.file_io.close(self.client, self.fd) catch {};
    }

    fn readAt(file: File, off: u32, buf: []u8) Error!void {
        _ = ps2.file_io.lseek(
            file.client,
            file.fd,
            @intCast(off),
            .set,
        ) catch return error.ReadFailed;

        const n = ps2.file_io.read(file.client, file.fd, buf) catch return error.ReadFailed;
        if (n != buf.len) return error.InvalidDebugInfo;
    }
};

/// Reads the program image's `.symtab` and linked `.strtab` through `file_io`
fn loadSymbols(gpa: std.mem.Allocator) Error!Symbols {
    const args = ps2.programArgs();
    if (args.len == 0) return error.MissingDebugInfo;

    const file: File = try .init(std.mem.span(args[0]));
    defer file.deinit();

    const tabs = try findSymbolTables(file);

    const symtab = try gpa.alloc(u8, tabs.symtab_size);
    try file.readAt(tabs.symtab_off, symtab);
    const strtab = try gpa.alloc(u8, tabs.strtab_size);
    try file.readAt(tabs.strtab_off, strtab);

    return .{ .loaded = .{
        .symtab = .{ .entry_size = tabs.symtab_entry_size, .bytes = symtab },
        .strtab = strtab,
    } };
}

/// Looks up `.symtab` and its linked `.strtab`
fn findSymbolTables(file: File) Error!SymbolTables {
    var ehdr: elf.Elf32_Ehdr = undefined;
    try file.readAt(0, std.mem.asBytes(&ehdr));
    if (!std.mem.eql(u8, ehdr.e_ident[0..4], elf.MAGIC) or ehdr.e_shentsize != @sizeOf(elf.Elf32_Shdr))
        return error.InvalidDebugInfo;

    for (0..ehdr.e_shnum) |i| {
        var shdr: elf.Elf32_Shdr = undefined;
        try file.readAt(
            ehdr.e_shoff + @as(u32, @intCast(i)) * @sizeOf(elf.Elf32_Shdr),
            std.mem.asBytes(&shdr),
        );
        if (shdr.sh_type != elf.SHT_SYMTAB) continue;

        var strtab: elf.Elf32_Shdr = undefined;
        if (shdr.sh_link >= ehdr.e_shnum) return error.InvalidDebugInfo;

        try file.readAt(
            ehdr.e_shoff + shdr.sh_link * @sizeOf(elf.Elf32_Shdr),
            std.mem.asBytes(&strtab),
        );
        return .{
            .symtab_off = shdr.sh_offset,
            .symtab_size = shdr.sh_size,
            .symtab_entry_size = shdr.sh_entsize,

            .strtab_off = strtab.sh_offset,
            .strtab_size = strtab.sh_size,
        };
    }

    return error.MissingDebugInfo;
}

pub const init: SelfInfo = .{};
pub fn deinit(_: *SelfInfo, _: std.Io) void {}

pub fn getSymbols(
    self: *SelfInfo,
    _: std.Io,
    sym_alloc: std.mem.Allocator,
    _: std.mem.Allocator,
    addr: usize,
    _: bool,
    symbols: *std.ArrayList(std.debug.Symbol),
) Error!void {
    const gpa = std.debug.getDebugInfoAllocator();
    if (self.symbols == .unloaded) self.symbols = loadSymbols(gpa) catch .missing;

    const loaded = switch (self.symbols) {
        .loaded => |*loaded| loaded,

        else => return error.MissingDebugInfo,
    };

    const sym = std.debug.ElfFile.searchSymbolTable(
        gpa,
        false,
        @import("builtin").cpu.arch.endian(),
        loaded.symtab,
        loaded.strtab,
        &loaded.search_table,
        addr,
    ) catch |err| return switch (err) {
        error.BadSymtab => error.InvalidDebugInfo,
        error.OutOfMemory => error.OutOfMemory,
    };
    try symbols.append(sym_alloc, sym);
}

/// Returns the file name of the `ELF` the program was started from
pub fn getModuleName(
    _: *SelfInfo,
    _: std.Io,
    _: usize,
) Error![]const u8 {
    const args = ps2.programArgs();
    if (args.len == 0) return error.MissingDebugInfo;

    const path = std.mem.span(args[0]);
    // TODO: This seems to share logic with `Io`'s `convertPath`, factor it out?
    return path[if (std.mem.lastIndexOfAny(u8, path, ":/\\")) |i| i + 1 else 0..];
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
