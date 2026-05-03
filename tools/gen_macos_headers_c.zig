const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const assert = std.debug.assert;
const info = std.log.info;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;

const usage =
    \\gen_macos_headers_c [dir]
    \\
    \\General Options:
    \\  -h, --help               Print this help and exit
    \\
;

const command: std.cli.Command = .{
    .name = "gen_macos_headers_c",
    .help = usage,
    .positional_args = &.{
        .init([:0]const u8, .{ .name = "dir" }),
    },
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const parsed = try std.cli.parseAlloc(command, arena, args, .{
        .exit_help = true,
        .exit_usage_error = true,
        .render_usage_errors = true,
        .render_help = .verbatim,
    });

    var dir = try Io.Dir.cwd().openDir(io, parsed.kind.args.dir, .{ .follow_symlinks = false });
    defer dir.close(io);
    var paths = std.array_list.Managed([]const u8).init(arena);
    try findHeaders(arena, io, dir, "", &paths);

    const SortFn = struct {
        pub fn lessThan(ctx: void, lhs: []const u8, rhs: []const u8) bool {
            _ = ctx;
            return std.mem.lessThan(u8, lhs, rhs);
        }
    };

    std.mem.sort([]const u8, paths.items, {}, SortFn.lessThan);

    var buffer: [2000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout_writer.interface;
    try w.writeAll("#define _XOPEN_SOURCE\n");
    for (paths.items) |path| {
        try w.print("#include <{s}>\n", .{path});
    }
    try w.writeAll(
        \\int main(int argc, char **argv) {
        \\    return 0;
        \\}
    );
    try w.flush();
}

fn findHeaders(
    arena: Allocator,
    io: Io,
    dir: Dir,
    prefix: []const u8,
    paths: *std.array_list.Managed([]const u8),
) anyerror!void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                const path = try Io.Dir.path.join(arena, &.{ prefix, entry.name });
                var subdir = try dir.openDir(io, entry.name, .{ .follow_symlinks = false });
                defer subdir.close(io);
                try findHeaders(arena, io, subdir, path, paths);
            },
            .file, .sym_link => {
                const ext = Io.Dir.path.extension(entry.name);
                if (!std.mem.eql(u8, ext, ".h")) continue;
                const path = try Io.Dir.path.join(arena, &.{ prefix, entry.name });
                try paths.append(path);
            },
            else => {},
        }
    }
}
