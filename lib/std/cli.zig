const std = @import("std");
const assert = std.debug.assert;
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

pub fn Help(comptime T: type) type {
    return struct {
        command_name: ?[]const u8 = null,
        summary: ?[]const u8 = null,
        args: Args,

        pub const Arg = struct {
            description: ?[]const u8 = null,
            display: ?[]const u8 = null,
            hidden: bool = false,
        };

        pub const Args = @Struct(.auto, null, std.meta.fieldNames(T), &@splat(Arg), &@splat(.{}));

        pub const RenderError = Terminal.SetColorError || std.Io.Writer.Error;

        pub fn renderHelp(help: @This(), term: Terminal, maybe_program_name: ?[]const u8) RenderError!void {
            const cmd: ArgsParser.CommandInfo = comptime .from(T);
            try term.setColor(.bold);
            try term.writer.writeAll("Usage:");
            try term.setColor(.reset);
            if (help.command_name orelse maybe_program_name) |command_name| {
                try term.writer.writeByte(' ');
                try term.setColor(.bold);
                try term.writer.writeAll(command_name);
                try term.setColor(.reset);
            }
            try renderUsageTokens(term, .normal, " [<option>...]");
            var brackets: usize = 0;
            var max_positional_width: ?usize = null;
            inline for (cmd.positional_names, cmd.positional_classes) |p_name, p_class| @"continue": {
                const arg_help: Arg = @field(help.args, p_name);
                if (arg_help.hidden) break :@"continue";
                if (max_positional_width == null) {
                    try renderUsageTokens(term, .normal, " [--]");
                }
                try term.writer.writeByte(' ');
                if (p_class != .required) {
                    try term.writer.writeByte('[');
                    brackets += 1;
                }
                const display = arg_help.display orelse
                    "<" ++ p_name ++ ">" ++ (if (p_class == .repeated) "..." else "");
                try renderUsageTokens(term, .normal, display);
                max_positional_width = @max(max_positional_width orelse 0, display.len);
            }
            if (brackets != 0) {
                try term.writer.splatByteAll(']', brackets);
            }
            if (help.summary) |summary| {
                try term.writer.print("\n\n{s}", .{summary});
            }
            if (max_positional_width) |max_width| {
                try term.writer.writeAll("\n\n");
                try term.setColor(.bold);
                try term.writer.writeAll("Arguments:");
                try term.setColor(.reset);
                inline for (cmd.positional_names, cmd.positional_classes) |p_name, p_class| @"continue": {
                    const arg_help: Arg = @field(help.args, p_name);
                    if (arg_help.hidden) break :@"continue";
                    try term.writer.writeAll("\n  ");
                    const display = arg_help.display orelse
                        "<" ++ p_name ++ ">" ++ (if (p_class == .repeated) "..." else "");
                    try renderUsageTokens(term, .normal, display);
                    if (arg_help.description) |description| {
                        try term.writer.splatByteAll(' ', max_width - display.len + 2);
                        try term.writer.writeAll(description);
                    }
                }
            }
            try term.writer.writeAll("\n\n");
            try term.setColor(.bold);
            try term.writer.writeAll("Options:");
            try term.setColor(.reset);
            var max_option_width: usize = "-h, --help".len;
            inline for (cmd.option_names, cmd.option_types) |o_name, o_type| @"continue": {
                const arg_help: Arg = @field(help.args, o_name);
                if (arg_help.hidden) break :@"continue";
                var width: usize = o_name.len;
                switch (o_type) {
                    void => {},
                    bool => {
                        width += "[no-]".len;
                    },
                    else => {
                        const display = arg_help.display orelse "<value>";
                        width += "=".len + display.len;
                    },
                }
                max_option_width = @max(max_option_width, width);
            }
            inline for (cmd.option_names, cmd.option_types) |o_name, o_type| @"continue": {
                const arg_help: Arg = @field(help.args, o_name);
                if (arg_help.hidden) break :@"continue";
                try term.writer.writeAll("\n  ");
                var width: usize = o_name.len;
                try term.setColor(.bold);
                try term.writer.writeAll("--");
                if (o_type == bool) {
                    width += "[no-]".len;
                    try renderUsageTokens(term, .bold, "[no-]");
                    try term.setColor(.bold);
                }
                // Don't use 'renderUsageTokens' for the option name;
                // all characters in the name are literal and should thus be bold.
                try term.writer.writeAll(o_name[2..]);
                if (o_type == void or o_type == bool) {
                    try term.setColor(.reset);
                } else {
                    try term.writer.writeByte('=');
                    const display = arg_help.display orelse "<value>";
                    width += "=".len + display.len;
                    try renderUsageTokens(term, .bold, display);
                }
                if (arg_help.description) |description| {
                    try term.writer.splatByteAll(' ', max_option_width - width + 2);
                    try term.writer.writeAll(description);
                }
            }
            try term.writer.writeAll("\n  ");
            try renderUsageTokens(term, .normal, "-h, --help");
            try term.writer.splatByteAll(' ', max_option_width - "-h, --help".len + 2);
            try term.writer.writeAll("Print this help and exit");
            if (@hasDecl(T, "--version")) {
                try term.writer.writeAll("\n  ");
                try renderUsageTokens(term, .normal, "--version");
                try term.writer.splatByteAll(' ', max_option_width - "--version".len + 2);
                try term.writer.writeAll("Print version and exit");
            }
            try term.writer.writeByte('\n');
            try term.writer.flush();
        }

        const Style = enum { normal, bold, italic };

        /// Styles commands/arguments/options in a usage message, roughly according to the
        /// conventions prescribed by man-pages(7):
        ///
        /// > [...] boldface is used for as-is text and italics are used to indicate replaceable
        /// > arguments. Brackets ([]) surround optional arguments, vertical bars (|) separate
        /// > choices, and ellipses (...) can be repeated.
        ///
        /// <https://man7.org/linux/man-pages/man7/man-pages.7.html>
        fn renderUsageTokens(term: Terminal, init_style: Style, tokens: []const u8) !void {
            var prev_style: Style = init_style;
            for (tokens) |c| {
                if (prev_style == .italic) {
                    try term.writer.writeByte(c);
                    if (c == '>') {
                        try term.setColor(.reset);
                        prev_style = .normal;
                    }
                } else {
                    const cur_style: Style = switch (c) {
                        ' ', '.', '(', ')', '[', ']', '|', ',' => .normal,
                        '<' => .italic,
                        else => .bold,
                    };
                    if (cur_style != prev_style) {
                        if (prev_style != .normal) {
                            try term.setColor(.reset);
                        }
                        switch (cur_style) {
                            .normal => {},
                            .bold => try term.setColor(.bold),
                            .italic => {
                                // TODO: Add missing common SGR parameters to 'std.Io.Terminal.Color'?
                                if (term.mode == .escape_codes) {
                                    try term.writer.writeAll("\x1b[3m");
                                }
                            },
                        }
                        prev_style = cur_style;
                    }
                    try term.writer.writeByte(c);
                }
            }
            if (prev_style != .normal) {
                try term.setColor(.reset);
            }
        }
    };
}

test {
    _ = ArgsParser;
    _ = ArgsTokenizer;
}
