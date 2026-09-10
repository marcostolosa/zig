const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const cwd: std.Io.Dir = .cwd();

    var main_it = try init.minimal.args.iterateAllocator(arena);
    if (!main_it.skip()) return error.BadUsage;

    const expect_abs = std.mem.eql(u8, main_it.next() orelse return error.BadUsage, "abs");

    const rsp_decorated_path = main_it.next() orelse return error.BadUsage;
    const rsp_path = cutDecoratedPath(rsp_decorated_path) orelse return error.BadUsage;
    const rsp_bytes = try cwd.readFileAlloc(io, rsp_path, arena, .limited(10 * 1024 * 1024));
    var rsp_it: std.process.Args.IteratorGeneral(.{}) = try .init(arena, rsp_bytes);

    while (main_it.next()) |expected_arg| {
        const actual_arg = rsp_it.next() orelse return error.MissingResponseFileArg;
        if (cutDecoratedPath(actual_arg)) |path| {
            // It is not an error to receive an absolute path when expecting a relative path
            try std.testing.expect(!expect_abs or std.Io.Dir.path.isAbsolute(path));

            // Compare only the filename stems
            const stem = std.Io.Dir.path.stem(path);
            try std.testing.expectEqualStrings(expected_arg, stem);

            const extension = std.Io.Dir.path.extension(path);
            if (std.mem.eql(u8, extension, ".d")) {
                // Create an empty dep file
                const file = try cwd.createFile(io, path, .{});
                defer file.close(io);
            } else if (std.mem.eql(u8, extension, ".rsp")) {
                // Print the full contents of the nested response file to stderr
                const bytes = try cwd.readFileAlloc(io, path, arena, .limited(10 * 1024 * 1024));
                std.debug.print("{s}\n", .{bytes});
            }
        } else {
            try std.testing.expectEqualStrings(expected_arg, actual_arg);
        }
    }
    if (rsp_it.skip()) return error.UnexpectedResponseFileArg;
}

fn cutDecoratedPath(path: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, path, "path^") and std.mem.endsWith(u8, path, "$"))
        path["path^".len..(path.len - "$".len)]
    else
        null;
}
