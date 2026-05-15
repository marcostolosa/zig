const Args = struct {
    target_triple: []const u8,

    pub const @"--help": std.cli.Help(Args) = .{
        .command_name = "zig run tools/generate_c_size_and_align_checks.zig --",
        .summary = (
            \\Prints _Static_asserts for the size and alignment of all the basic built-in
            \\C types. The output can be run through a compiler for the specified target
            \\to verify that Zig's values are the same as those used by a C compiler
            \\for the target.
        ),
        .args = .{
            .target_triple = .{ .description = "Zig target triple (e.g. x86_64-linux-gnu)" },
        },
    };
};

const std = @import("std");
const Io = std.Io;

fn cName(ty: std.Target.CType) []const u8 {
    return switch (ty) {
        .char => "char",
        .short => "short",
        .ushort => "unsigned short",
        .int => "int",
        .uint => "unsigned int",
        .long => "long",
        .ulong => "unsigned long",
        .longlong => "long long",
        .ulonglong => "unsigned long long",
        .float => "float",
        .double => "double",
        .longdouble => "long double",
    };
}

pub fn main(init: std.process.Init, args: Args) !void {
    const io = init.io;

    const query = try std.Target.Query.parse(.{ .arch_os_abi = args.target_triple });
    const target = try std.zig.system.resolveTargetQuery(io, query);

    var buffer: [2000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout_writer.interface;
    inline for (@typeInfo(std.Target.CType).@"enum".field_values) |field_value| {
        const c_type: std.Target.CType = @enumFromInt(field_value);
        try w.print("_Static_assert(sizeof({0s}) == {1d}, \"sizeof({0s}) == {1d}\");\n", .{
            cName(c_type),
            target.cTypeByteSize(c_type),
        });
        try w.print("_Static_assert(_Alignof({0s}) == {1d}, \"_Alignof({0s}) == {1d}\");\n", .{
            cName(c_type),
            target.cTypeAlignment(c_type),
        });
        try w.print("_Static_assert(__alignof({0s}) == {1d}, \"__alignof({0s}) == {1d}\");\n\n", .{
            cName(c_type),
            target.cTypePreferredAlignment(c_type),
        });
    }
    try w.flush();
}
