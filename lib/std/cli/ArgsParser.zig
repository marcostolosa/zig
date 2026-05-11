const std = @import("std");
const ArgsTokenizer = std.cli.ArgsTokenizer;
const Help = std.cli.Help;
const assert = std.debug.assert;

const ArgsParser = @This();

stdout: std.Io.Terminal,
stderr: std.Io.Terminal,

/// Used for printing usage messages.
program_name: ?[]const u8,

pub const ParseError = error{
    /// Command-line usage error.
    Usage,
    /// The user passed the `--help` option.
    HelpRequested,
    /// The user passed the `--version` option.
    VersionRequested,
} || std.Io.Terminal.SetColorError || std.Io.Writer.Error;

pub fn parse(
    p: ArgsParser,
    comptime T: type,
    args: []const []const u8,
) ParseError!T {
    return p.parseArgs(.{ .alloc = false, .z = false }, T, {}, args);
}

pub fn parseZ(
    p: ArgsParser,
    comptime T: type,
    args: []const [:0]const u8,
) ParseError!T {
    return p.parseArgs(.{ .alloc = false, .z = true }, T, {}, args);
}

pub const ParseAllocError = ParseError || std.mem.Allocator.Error;

pub fn parseAlloc(
    p: ArgsParser,
    comptime T: type,
    arena: std.mem.Allocator,
    args: []const []const u8,
) ParseAllocError!T {
    return p.parseArgs(.{ .alloc = true, .z = false }, T, arena, args);
}

pub fn parseAllocZ(
    p: ArgsParser,
    comptime T: type,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
) ParseAllocError!T {
    return p.parseArgs(.{ .alloc = true, .z = true }, T, arena, args);
}

pub const CommandInfo = struct {
    positional_names: []const [:0]const u8,
    positional_types: []const type,
    positional_classes: []const ArgClass,
    option_names: []const [:0]const u8,
    option_types: []const type,
    option_classes: []const ArgClass,

    pub const ArgClass = enum { required, optional, repeated };

    pub fn from(comptime T: type) CommandInfo {
        for (.{ "--help", "--version" }) |field_name| if (@hasField(T, field_name)) {
            @compileError("option '" ++ field_name ++ "' is reserved and cannot be declared as a field");
        };

        var cmd: CommandInfo = .{
            .positional_names = &.{},
            .positional_types = &.{},
            .positional_classes = &.{},
            .option_names = &.{},
            .option_types = &.{},
            .option_classes = &.{},
        };
        for (@typeInfo(T).@"struct".fields) |f| {
            const unwrapped_type: type, const class: ArgClass = unwrap: {
                switch (@typeInfo(f.type)) {
                    .optional => |info| {
                        break :unwrap .{ info.child, .optional };
                    },
                    .pointer => |info| if (info.size == .slice and !isStringSlice(info)) {
                        break :unwrap .{ info.child, .repeated };
                    },
                    else => {},
                }
                break :unwrap .{ f.type, if (f.default_value_ptr != null) .optional else .required };
            };
            if (f.name[0] == '-') {
                if (!ArgsTokenizer.isValidLongOptionName(f.name)) {
                    const kind = if (ArgsTokenizer.isValidShortOptionName(f.name)) "short" else "invalid";
                    @compileError("expected long option name in the form '--foo', found " ++ kind ++ " option name '" ++ f.name ++ "'");
                }
                type_ok: {
                    switch (@typeInfo(unwrapped_type)) {
                        .void, .bool => if (class != .repeated) break :type_ok,
                        .int, .float, .@"enum" => break :type_ok,
                        .pointer => |info| if (isStringSlice(info)) break :type_ok,
                        else => {},
                    }
                    @compileError("option '" ++ f.name ++ "' has unsupported type '" ++ @typeName(f.type) ++ "'");
                }
                if (class == .required) {
                    @compileError("scalar option '" ++ f.name ++ "' must have an optional type or a default field value");
                }
                if (f.type == bool) {
                    const negated_name = "--no-" ++ f.name[2..];
                    if (@hasField(T, negated_name)) {
                        @compileError("option '" ++ negated_name ++ "' conflicts with boolean option '" ++ f.name ++ "'");
                    }
                }
                cmd.option_names = cmd.option_names ++ .{f.name};
                cmd.option_types = cmd.option_types ++ .{unwrapped_type};
                cmd.option_classes = cmd.option_classes ++ .{class};
            } else {
                type_ok: {
                    switch (@typeInfo(unwrapped_type)) {
                        .int, .float, .@"enum" => break :type_ok,
                        .pointer => |info| if (isStringSlice(info)) break :type_ok,
                        else => {},
                    }
                    @compileError("positional '" ++ f.name ++ "' has unsupported type '" ++ @typeName(f.type) ++ "'");
                }
                if (cmd.positional_names.len != 0) {
                    const i = cmd.positional_names.len - 1;
                    if (cmd.positional_classes[i] == .repeated) {
                        @compileError("repeated positional '" ++ cmd.positional_names[i] ++ "' must be declared after all other positionals");
                    }
                    if (class == .required and cmd.positional_classes[i] == .optional) {
                        @compileError("optional positional '" ++ cmd.positional_names[i] ++ "' must be declared after all required positionals");
                    }
                }
                cmd.positional_names = cmd.positional_names ++ .{f.name};
                cmd.positional_types = cmd.positional_types ++ .{unwrapped_type};
                cmd.positional_classes = cmd.positional_classes ++ .{class};
            }
        }

        return cmd;
    }

    fn isStringSlice(info: std.lang.Type.Pointer) bool {
        return info.size == .slice and info.is_const and info.child == u8 and (info.sentinel() orelse 0) == 0;
    }
};

const Api = struct { alloc: bool, z: bool };

fn parseArgs(
    p: ArgsParser,
    comptime api: Api,
    comptime T: type,
    arena: if (api.alloc) std.mem.Allocator else void,
    args: []const (if (api.z) [:0]const u8 else []const u8),
) !T {
    type_ok: {
        switch (@typeInfo(T)) {
            .@"struct" => break :type_ok,
            .@"union" => |info| if (info.tag_type != null) return p.parseSubcommand(T, api, arena, args),
            else => {},
        }
        @compileError("expected struct or tagged union, found '" ++ @typeName(T) ++ "'");
    }

    const cmd: CommandInfo = comptime .from(T);
    const cmd_name: ?[]const u8 =
        if (@hasDecl(T, "--help") and @TypeOf(T.@"--help") == Help(T))
            T.@"--help".command_name orelse p.program_name
        else
            p.program_name;

    const ArrayLists: type, //
    const required_positional_count: usize, //
    const optional_positional_count: usize, //
    const option_names: []const [:0]const u8, //
    const option_arities: []const ArgsTokenizer.OptionArity, //
    const original_options_end: usize, //
    const negated_options_end: usize, //
    const help_options_end: usize //
    = comptime info: {
        var list_field_names: []const [:0]const u8 = &.{};
        var list_field_types: []const type = &.{};
        var list_field_attrs: []const std.lang.Type.StructField.Attributes = &.{};
        var required_positional_count: usize = 0;
        var optional_positional_count: usize = 0;
        for (cmd.positional_names, cmd.positional_types, cmd.positional_classes, 0..) |p_name, p_type, p_class, i| {
            switch (p_class) {
                .required => {
                    assert(optional_positional_count == 0);
                    required_positional_count += 1;
                },
                .optional => {
                    optional_positional_count += 1;
                },
                .repeated => {
                    assert(i == cmd.positional_names.len - 1);
                    optional_positional_count = std.math.maxInt(usize);
                    list_field_names = list_field_names ++ .{p_name};
                    list_field_types = list_field_types ++ .{std.ArrayList(p_type)};
                    list_field_attrs = list_field_attrs ++ .{@as(
                        std.lang.Type.StructField.Attributes,
                        .{ .default_value_ptr = &std.ArrayList(p_type).empty },
                    )};
                },
            }
        }

        var option_arities: []const ArgsTokenizer.OptionArity = &.{};
        var negated_option_names: []const [:0]const u8 = &.{};
        for (cmd.option_names, cmd.option_types, cmd.option_classes) |o_name, o_type, o_class| {
            if (o_class == .repeated) {
                list_field_names = list_field_names ++ .{o_name};
                list_field_types = list_field_types ++ .{std.ArrayList(o_type)};
                list_field_attrs = list_field_attrs ++ .{@as(
                    std.lang.Type.StructField.Attributes,
                    .{ .default_value_ptr = &std.ArrayList(o_type).empty },
                )};
            }
            const arity: ArgsTokenizer.OptionArity = switch (o_type) {
                void => .no_arg,
                bool => arity: {
                    negated_option_names = negated_option_names ++ .{"--no-" ++ o_name[2..]};
                    break :arity .no_arg;
                },
                else => .required_arg,
            };
            option_arities = option_arities ++ .{arity};
        }

        var option_names = cmd.option_names;
        const original_options_end = option_names.len;
        option_names = option_names ++ negated_option_names;
        const negated_options_end = option_names.len;
        option_names = option_names ++ .{ "-h", "--help" };
        const help_options_end = option_names.len;
        if (@hasDecl(T, "--version")) {
            option_names = option_names ++ .{"--version"};
        }
        option_arities = option_arities ++ @as(
            [option_names.len - original_options_end]ArgsTokenizer.OptionArity,
            @splat(.no_arg),
        );

        assert(option_names.len == option_arities.len);
        break :info .{
            @Struct(.auto, null, list_field_names, list_field_types[0..], list_field_attrs[0..]),
            required_positional_count,
            optional_positional_count,
            option_names,
            option_arities,
            original_options_end,
            negated_options_end,
            help_options_end,
        };
    };

    var result: T = comptime init: {
        var result_init: T = undefined;
        for (@typeInfo(T).@"struct".fields) |f_| {
            const f: std.lang.Type.StructField = f_;
            const default_value: ?f.type = f.defaultValue() orelse switch (@typeInfo(f.type)) {
                .optional => @as(f.type, null),
                else => @as(?f.type, null),
            };
            if (default_value) |value| {
                @field(result_init, f.name) = value;
            }
        }
        break :init result_init;
    };

    var result_lists: ArrayLists = .{};
    errdefer inline for (@typeInfo(ArrayLists).@"struct".fields) |f| {
        @field(result_lists, f.name).deinit(arena);
    };

    var positional_index: usize = 0;
    var tokenizer: ArgsTokenizer = .init(args);
    while (tokenizer.nextDynamic(option_names, option_arities)) |token| switch (token) {
        .option => |option| switch (option.index) {
            inline 0...(option_names.len - 1) => |i| {
                const option_name = option_names[i];
                if (i < original_options_end) {
                    const parsed_arg = try p.parseArg(api, cmd_name, option_name, cmd.option_types[i], option.arg);
                    if (cmd.option_classes[i] == .repeated) {
                        // Repeated option
                        try @field(result_lists, option_name).append(arena, parsed_arg);
                    } else {
                        // Scalar option
                        @field(result, option_name) = parsed_arg;
                    }
                } else if (i < negated_options_end) {
                    // Negated boolean option
                    assert(option.arg == null);
                    @field(result, "--" ++ option_name["--no-".len..]) = false;
                } else if (i < help_options_end) {
                    // -h, --help
                    return try p.printHelp(T);
                } else {
                    // --version
                    return try p.printVersion(T);
                }
            },
            else => unreachable,
        },
        .end_of_options => {},
        .positional => |positional_arg| if (cmd.positional_names.len != 0) switch (positional_index) {
            inline 0...(cmd.positional_names.len - 1) => |i| {
                const positional_name = cmd.positional_names[i];
                const parsed_arg = try p.parseArg(api, cmd_name, null, cmd.positional_types[i], positional_arg);
                if (cmd.positional_classes[i] == .repeated) {
                    // Repeated positional
                    try @field(result_lists, positional_name).append(arena, parsed_arg);
                } else {
                    // Scalar positional
                    @field(result, positional_name) = parsed_arg;
                    positional_index += 1;
                }
            },
            else => {
                return try p.failIncorrectArgCount(cmd_name, required_positional_count, optional_positional_count);
            },
        } else {
            return try p.failMissingOrUnexpectedArg(cmd_name, null, positional_arg);
        },
        .invalid_option => |invalid| switch (invalid.err) {
            error.UnrecognizedOption => {
                return try p.failUnrecognized(cmd_name, "option", invalid.name.slice());
            },
            error.MissingOptionArg, error.UnexpectedOptionArg => {
                return try p.failMissingOrUnexpectedArg(cmd_name, invalid.name.slice(), invalid.arg);
            },
        },
    };

    if (positional_index < required_positional_count) {
        if (required_positional_count == 1 and optional_positional_count == 0) {
            return try p.failMissingOrUnexpectedArg(cmd_name, null, null);
        } else {
            return try p.failIncorrectArgCount(cmd_name, required_positional_count, optional_positional_count);
        }
    }

    inline for (@typeInfo(ArrayLists).@"struct".fields) |f| {
        if (@typeInfo(@FieldType(T, f.name)).pointer.sentinel()) |s| {
            @field(result, f.name) = try @field(result_lists, f.name).toOwnedSliceSentinel(arena, s);
        } else {
            @field(result, f.name) = try @field(result_lists, f.name).toOwnedSlice(arena);
        }
    }

    return result;
}

fn parseArg(p: ArgsParser, comptime api: Api, cmd_name: ?[]const u8, option_name: ?[]const u8, comptime T: type, arg: ?[]const u8) !T {
    switch (@typeInfo(T)) {
        .void => {
            assert(arg == null);
            return;
        },
        .bool => {
            assert(arg == null);
            return true;
        },
        .int => {
            return parseInt(T, arg.?) catch |err| switch (err) {
                error.InvalidCharacter => try p.failInvalidNumber(cmd_name, option_name, arg.?, "integer"),
                error.Overflow => try p.failNumberOutOfRange(cmd_name, option_name, arg.?, std.math.minInt(T), std.math.maxInt(T)),
            };
        },
        .float => {
            return parseFloat(T, arg.?) catch |err| switch (err) {
                error.InvalidCharacter => try p.failInvalidNumber(cmd_name, option_name, arg.?, "floating-point number"),
            };
        },
        .@"enum" => {
            return parseEnum(T, arg.?) catch |err| switch (err) {
                error.UnrecognizedName => try p.failInvalidChoice(cmd_name, option_name, arg.?, std.meta.fieldNames(T)),
            };
        },
        .pointer => {
            if (api.z) {
                // This is perfectly safe; the tokenizer guarantees that sentinels are preserved.
                return arg.?.ptr[0..arg.?.len :0];
            }
            return arg.?;
        },
        else => {},
    }
    comptime unreachable;
}

fn parseInt(comptime Int: type, arg: []const u8) !Int {
    return std.fmt.parseInt(Int, arg, 0);
}

fn parseFloat(comptime Float: type, arg: []const u8) !Float {
    return std.fmt.parseFloat(Float, arg);
}

fn parseEnum(comptime Enum: type, arg: []const u8) !Enum {
    return std.meta.stringToEnum(Enum, arg) orelse error.UnrecognizedName;
}

fn parseSubcommand(
    p: ArgsParser,
    comptime api: Api,
    comptime T: type,
    arena: if (api.alloc) std.mem.Allocator else void,
    args: []const (if (api.z) [:0]const u8 else []const u8),
) !T {
    _ = p;
    _ = arena;
    _ = args;
    @compileError("TODO: implement subcommand parsing");
}

fn failUnrecognized(p: ArgsParser, cmd_name: ?[]const u8, kind: []const u8, name: []const u8) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(null);
    try p.stderr.writer.print("unrecognized {s} ", .{kind});
    try p.failQuote(.yellow, name);
    return p.failSuffix(cmd_name);
}

fn failIncorrectArgCount(p: ArgsParser, cmd_name: ?[]const u8, required: usize, optional: usize) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(null);
    try p.stderr.writer.writeAll("incorrect number of arguments (expected ");
    var last = required;
    if (optional != 0) {
        if (optional == std.math.maxInt(usize)) {
            try p.stderr.writer.writeAll("at least ");
        } else {
            if (required == 0) {
                try p.stderr.writer.writeAll("at most ");
            } else {
                try p.stderr.writer.print("between {d} and ", .{required});
            }
            last = required + optional;
        }
    }
    try p.stderr.writer.print("{d})", .{last});
    return p.failSuffix(cmd_name);
}

fn failMissingOrUnexpectedArg(p: ArgsParser, cmd_name: ?[]const u8, option_name: ?[]const u8, arg: ?[]const u8) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(option_name);
    if (arg) |x| {
        try p.stderr.writer.writeAll("unexpected argument ");
        try p.failQuote(.yellow, x);
    } else {
        try p.stderr.writer.writeAll("expected an argument");
    }
    return p.failSuffix(cmd_name);
}

fn failInvalidNumber(p: ArgsParser, cmd_name: ?[]const u8, option_name: ?[]const u8, arg: []const u8, kind: []const u8) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(option_name);
    try p.stderr.writer.writeAll("argument ");
    try p.failQuote(.yellow, arg);
    try p.stderr.writer.print(" is not a recognizable {s}", .{kind});
    return p.failSuffix(cmd_name);
}

fn failNumberOutOfRange(p: ArgsParser, cmd_name: ?[]const u8, option_name: ?[]const u8, arg: []const u8, comptime min: comptime_int, comptime max: comptime_int) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(option_name);
    try p.stderr.writer.writeAll("argument ");
    try p.failQuote(.yellow, arg);
    try p.stderr.writer.writeAll(" is outside the allowable range (expected a value between ");
    try p.stderr.setColor(.bold);
    try p.stderr.writer.print("{d}", .{min});
    try p.stderr.setColor(.reset);
    try p.stderr.writer.writeAll(" and ");
    try p.stderr.setColor(.bold);
    try p.stderr.writer.print("{d}", .{max});
    try p.stderr.setColor(.reset);
    try p.stderr.writer.writeAll(" inclusive)");
    return p.failSuffix(cmd_name);
}

fn failInvalidChoice(p: ArgsParser, cmd_name: ?[]const u8, option_name: ?[]const u8, arg: []const u8, choices: []const []const u8) !noreturn {
    @branchHint(.cold);
    try p.failPrefix(option_name);
    try p.stderr.writer.writeAll("argument ");
    try p.failQuote(.yellow, arg);
    try p.stderr.writer.writeAll(" is not a recognizable choice (expected ");
    try p.failQuote(.bold, choices[0]);
    for (choices[1..(choices.len - 1)]) |choice| {
        try p.stderr.writer.writeAll(", ");
        try p.failQuote(.bold, choice);
    }
    if (choices.len > 1) {
        try p.stderr.writer.writeAll(" or ");
        try p.failQuote(.bold, choices[choices.len - 1]);
    }
    try p.stderr.writer.writeByte(')');
    return p.failSuffix(cmd_name);
}

fn failQuote(f: ArgsParser, color: std.Io.Terminal.Color, value: []const u8) !void {
    @branchHint(.cold);
    try f.stderr.setColor(color);
    try f.stderr.writer.print("'{s}'", .{value});
    try f.stderr.setColor(.reset);
}

fn failPrefix(p: ArgsParser, option_name: ?[]const u8) !void {
    @branchHint(.cold);
    try p.stderr.setColor(.bold);
    try p.stderr.setColor(.red);
    try p.stderr.writer.writeAll("error:");
    try p.stderr.setColor(.reset);
    try p.stderr.writer.writeByte(' ');
    if (option_name) |name| {
        try p.stderr.setColor(.bold);
        try p.stderr.writer.print("option {s}:", .{name});
        try p.stderr.setColor(.reset);
        try p.stderr.writer.writeByte(' ');
    }
}

fn failSuffix(p: ArgsParser, cmd_name: ?[]const u8) !noreturn {
    @branchHint(.cold);
    try p.stderr.writer.writeAll("\nTry ");
    try p.stderr.setColor(.bold);
    try p.stderr.writer.writeByte('\'');
    if (cmd_name) |name| {
        try p.stderr.writer.print("{s} ", .{name});
    }
    try p.stderr.writer.writeAll("--help'");
    try p.stderr.setColor(.reset);
    try p.stderr.writer.writeAll(" for more information.\n");
    try p.stderr.writer.flush();
    return error.Usage;
}

fn printHelp(p: ArgsParser, comptime T: type) !noreturn {
    @branchHint(.cold);
    if (!@hasDecl(T, "--help")) {
        const default_help: Help(T) = .{ .args = std.mem.zeroInit(Help(T).Args, .{}) };
        try default_help.renderHelp(p.stdout, p.program_name);
    } else if (@typeInfo(@TypeOf(T.@"--help")) == .pointer) {
        const string = T.@"--help";
        try p.stdout.writer.writeAll(string);
        if (string.len != 0 and string[string.len - 1] != '\n') {
            try p.stdout.writer.writeByte('\n');
        }
    } else if (@TypeOf(T.@"--help") == Help(T)) {
        try T.@"--help".renderHelp(p.stdout, p.program_name);
    } else {
        @compileError("unsupported '--help' type: expected '[]const u8' or 'std.cli.Help(" ++ @typeName(T) ++ ")', found '" ++ @typeName(@TypeOf(T.@"--help")) ++ "'");
    }
    try p.stdout.writer.flush();
    return error.HelpRequested;
}

fn printVersion(p: ArgsParser, comptime T: type) !noreturn {
    @branchHint(.cold);
    if (@typeInfo(@TypeOf(T.@"--version")) == .pointer) {
        const string = T.@"--version";
        try p.stdout.writer.writeAll(string);
        if (string.len != 0 and string[string.len - 1] != '\n') {
            try p.stdout.writer.writeByte('\n');
        }
    } else if (@TypeOf(T.@"--version") == std.SemanticVersion) {
        try p.stdout.writer.print("{f}\n", .{T.@"--version"});
    } else {
        @compileError("unsupported '--version' type: expected '[]const u8' or 'std.SemanticVersion', found '" ++ @typeName(@TypeOf(T.@"--version")) ++ "'");
    }
    try p.stdout.writer.flush();
    return error.VersionRequested;
}

test ArgsParser {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var discarding: std.Io.Writer.Discarding = .init(&.{});

    const AppArgs = struct {
        op: enum { sum, min, max },
        first_value: i32,
        rest_values: []const i32,
        @"--output": ?[:0]const u8,
        @"--pretty": bool = true,
        @"--verbose": ?void,
    };

    const args: []const [:0]const u8 = &.{
        "calculatinator",
        "sum",
        "--output",
        "result.txt",
        "5",
        "12",
        "-4",
        "19",
        "--no-pretty",
        "--verbose",
    };
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &discarding.writer, .mode = .no_color },
        .stderr = .{ .writer = &discarding.writer, .mode = .no_color },
        .program_name = args[0],
    };

    const parsed = try parser.parseAllocZ(AppArgs, arena_allocator.allocator(), args[1..]);

    const expected: AppArgs = .{
        .op = .sum,
        .first_value = 5,
        .rest_values = &.{ 12, -4, 19 },
        .@"--output" = "result.txt",
        .@"--pretty" = false,
        .@"--verbose" = {},
    };
    try std.testing.expectEqualDeep(expected, parsed);
}
