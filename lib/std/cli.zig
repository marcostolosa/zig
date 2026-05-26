const std = @import("std");
const assert = std.debug.assert;
const Terminal = std.Io.Terminal;

pub const ArgsParser = @import("cli/ArgsParser.zig");
pub const ArgsTokenizer = @import("cli/ArgsTokenizer.zig");

/// Parses the process's arguments into a struct or tagged union instance.
/// See `std.cli.ArgsParser` for more details.
pub fn parseProcessArgs(comptime T: type, init: std.process.Init) ArgsParser.ParseAllocError!T {
    // It is okay for the stdout and stderr writers to both share the same buffer,
    // the parser will only write to at most one of them, never both.
    var writer_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &writer_buf);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &writer_buf);

    const NO_COLOR = if (init.environ_map.get("NO_COLOR")) |x| x.len != 0 else false;
    const CLICOLOR_FORCE = if (init.environ_map.get("CLICOLOR_FORCE")) |x| x.len != 0 else false;
    const stdout_mode: Terminal.Mode = try .detect(init.io, .stdout(), NO_COLOR, CLICOLOR_FORCE);
    const stderr_mode: Terminal.Mode = try .detect(init.io, .stderr(), NO_COLOR, CLICOLOR_FORCE);

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const parser: ArgsParser = .{
        .command_name = if (args.len != 0) &.{std.Io.Dir.path.basename(args[0])} else &.{},
        .stdout = .{ .writer = &stdout_writer.interface, .mode = stdout_mode },
        .stderr = .{ .writer = &stderr_writer.interface, .mode = stderr_mode },
    };

    return parser.parseAllocZ(T, init.arena.allocator(), args[@min(1, args.len)..]);
}

/// Used to customize the help text printed by `std.cli.ArgsParser`.
pub fn Help(comptime T: type) type {
    return struct {
        command_name: ?[]const u8 = null,
        summary: ?[]const u8 = null,
        args: Args,

        pub const Arg = struct {
            display: ?[]const u8 = null,
            description: ?[]const u8 = null,
            hidden: bool = false,
        };

        pub const Args = @Struct(.auto, null, std.meta.fieldNames(T), &@splat(Arg), &@splat(.{}));
    };
}

test {
    _ = ArgsParser;
    _ = ArgsTokenizer;
}
