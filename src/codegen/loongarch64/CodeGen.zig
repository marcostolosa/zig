const std = @import("std");
const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const link = @import("../../link.zig");
const InternPool = @import("../../InternPool.zig");
const Mir = @import("Mir.zig");

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
) !Mir {
    _ = lf;
    _ = func_index;
    _ = air;
    _ = liveness;

    var mir: Mir = .{};
    try mir.instructions.append(pt.zcu.gpa, .{
        .tag = .ret,
        .data = .{ .none = {} },
    });
    return mir;
}

pub fn generateLazy(
    lf: *link.File,
    pt: Zcu.PerThread,
    lazy_sym: link.File.LazySymbol,
    atom_id: link.File.AtomId,
    w: *std.Io.Writer,
    debug_output: link.File.DebugInfoOutput,
) (link.Error || std.Io.Writer.Error)!void {
    _ = lf;
    _ = pt;
    _ = lazy_sym;
    _ = atom_id;
    _ = w;
    _ = debug_output;
    @panic("TODO: generateLazy in loongarch64");
}
