const std = @import("std");
const Terminal = std.Io.Terminal;

pub const ArgsParser = @import("cli/ArgsParser.zig");
pub const ArgsTokenizer = @import("cli/ArgsTokenizer.zig");

/// Convenience function for parsing the process's arguments into a struct or tagged union instance.
/// See `ArgsParser` for more detailed information about the parser's behavior.
pub fn parseProcessArgs(comptime T: type, init: std.process.Init) ArgsParser.ParseAllocError!T {
    // It is okay for the stdout and stderr writers to both share the same buffer,
    // the parser will only write to at most one of them, never both.
    var writer_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &writer_buf);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &writer_buf);

    const NO_COLOR = if (init.environ_map.get("NO_COLOR")) |x| x.len != 0 else false;
    const CLICOLOR_FORCE = if (init.environ_map.get("CLICOLOR_FORCE")) |x| x.len != 0 else false;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const parser: ArgsParser = .{
        .stdout = .{
            .writer = &stdout_writer.interface,
            .mode = try .detect(init.io, .stdout(), NO_COLOR, CLICOLOR_FORCE),
        },
        .stderr = .{
            .writer = &stderr_writer.interface,
            .mode = try .detect(init.io, .stderr(), NO_COLOR, CLICOLOR_FORCE),
        },
        .program_name = if (args.len != 0) std.Io.Dir.path.basename(args[0]) else null,
    };

    return parser.parseAllocZ(T, init.arena.allocator(), args[@min(1, args.len)..]);
}

test {
    _ = ArgsParser;
    _ = ArgsTokenizer;
}
