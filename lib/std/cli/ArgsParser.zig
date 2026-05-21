//! High-level API for parsing a slice of command-line arguments into a custom struct.
//!
//! Any field of the custom struct whose name begins with `@"--"` and is at least three characters
//! in length is considered to be an option field; for example, `@"--foo"` or `@"--dry-run"`.
//! The type of an option field dictates how it receives values from the command line:
//!
//! Primitive | `?T` | `[]T` | Example type       | Example command-line syntax
//! ----------|------|-------|--------------------|--------------------------------
//! Void      | Yes  | No    | `?void`            | `--foo`
//! Boolean   | Yes  | No    | `bool`             | `--foo`, `--no-foo`
//! Integer   | Yes  | Yes   | `[]i32`            | `--foo=123`, `--foo 0xff`
//! Float     | Yes  | Yes   | `f64`              | `--foo=1.5`, `--foo 1.2e-3`
//! Enum      | Yes  | Yes   | `enum { on, off }` | `--foo=on`, `--foo off`
//! String    | Yes  | Yes   | `[][]const u8`     | `--foo=c.c`, `--foo /dev/null`
//!
//! Each option field must either have an optional or slice type, or a default field value
//! (a "required option" is an oxymoron). Slice options are populated by specifying the option
//! multiple times on the command line. For scalar (non-slice) options, if the same option is
//! specified multiple times, then the last specified value is the one that gets used.
//!
//! Fields of the custom struct whose names do not begin with `@"--"` are considered to be
//! positional fields, and receives their values from the command line as positional arguments,
//! in the same order as the fields are declared. Positional fields may have any of the same types
//! as option fields except for `void` and `bool`.
//!
//! Positional fields that have optional or slice types, or default field values,
//! are considered optional and are not required to be specified on the command line.
//! All other positional fields are required to be specified. Optional positional fields must be
//! declared after all required positional fields. The last declared positional field may have
//! a slice type, in which case it is considered to be a repeated positional and will receive
//! all trailing positional arguments from the command line.
//!
//! If the parser cannot parse the provided slice of command-line arguments,
//! it will automatically print a usage error message to `stderr` and return `error.Usage`.
//!
//! If the parser encounters the option `--help`, it will automatically print help text
//! to `stdout` and return `error.HelpRequested`. The help text can be customized by having
//! the custom struct declare `pub const @"--help"` of type `[]const u8` or `std.cli.Help(T)`.
//!
//! If the custom struct declares `pub const @"--version"` of type `[]const u8` or
//! `std.SemanticVersion`, then the parser will additionally recognize the `--version` option
//! and handle it in a similar manner to `--help`, by printing the version to `stdout`
//! and returning `error.VersionRequested`.
//!
//! `ArgsParser` can be called from code like any other regular API.
//! However, if the program's `main` function is defined to take two parameters, like
//!
//! ```
//! pub fn main(init: std.process.Init, args: Args) void {}
//! ```
//!
//! then `ArgsParser` will be used to automatically parse the program's
//! command-line arguments into an instance of the custom struct `Args`.
//! When used like this, usage errors and requests for help text will be handled automatically
//! before control enters the program's `main` function.
//!
//! See also `std.cli.ArgsTokenizer` for a more low-level API that can be used to tokenize
//! command-line arguments into options and positional arguments.
const ArgsParser = @This();

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

const std = @import("std");
const ArgsTokenizer = std.cli.ArgsTokenizer;
const Help = std.cli.Help;
const assert = std.debug.assert;

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

/// Parses a slice of command-line arguments.
/// Asserts at comptime that `T` does not contain any slice fields,
/// which would require dynamic memory allocation to populate.
pub fn parse(
    p: ArgsParser,
    comptime T: type,
    args: []const []const u8,
) ParseError!T {
    return p.parseArgs(.{ .alloc = false, .z = false }, T, {}, args);
}

/// Parses a slice of null-terminated command-line arguments.
/// Asserts at comptime that `T` does not contain any slice fields,
/// which would require dynamic memory allocation to populate.
pub fn parseZ(
    p: ArgsParser,
    comptime T: type,
    args: []const [:0]const u8,
) ParseError!T {
    return p.parseArgs(.{ .alloc = false, .z = true }, T, {}, args);
}

pub const ParseAllocError = ParseError || std.mem.Allocator.Error;

/// Parses a slice of command-line arguments.
/// Slice fields are populated using the specified arena allocator;
/// however, note that string elements of fields of type `[]const []const u8`
/// are not copied and will instead point to inside the original `args` slice.
pub fn parseAlloc(
    p: ArgsParser,
    comptime T: type,
    arena: std.mem.Allocator,
    args: []const []const u8,
) ParseAllocError!T {
    return p.parseArgs(.{ .alloc = true, .z = false }, T, arena, args);
}

/// Parses a slice of null-terminated command-line arguments.
/// Slice fields are populated using the specified arena allocator;
/// however, note that string elements of fields of type `[]const []const u8`
/// are not copied and will instead point to inside the original `args` slice.
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

fn noopDrain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    _ = w;
    const slice = data[0 .. data.len - 1];
    const pattern = data[slice.len];
    var written: usize = pattern.len * splat;
    for (slice) |bytes| written += bytes.len;
    return written;
}

var noop_writer: std.Io.Writer = .{ .buffer = &.{}, .vtable = &.{ .drain = noopDrain } };
const noop_terminal: std.Io.Terminal = .{ .writer = &noop_writer, .mode = .no_color };
const quiet_parser: ArgsParser = .{
    .stdout = noop_terminal,
    .stderr = noop_terminal,
    .program_name = null,
};

test "integers" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const Args = struct {
        p0: i32,
        p1: u32,
        p2: i96,
        p3: u31,
        p4: u0,
        p5: []u8,
        @"--o0": ?i32,
        @"--o1": ?u32,
        @"--o2": ?i96,
        @"--o3": ?u31,
        @"--o4": ?u0,
        @"--o5": []u8,
    };
    const args: []const []const u8 = &.{
        "--o0=999",
        "12_345",
        "0b0101_1010",
        "0x7fff_ffff_ffff_ffff_ffff_ffff",
        "0o765",
        "--o0=-123",
        "--o1=+123",
        "--o2",
        "-0XC0FFEE",
        "--o3=0O0",
        "0B0",
        "--o5=0x7a",
        "1",
        "--o5=0x69",
        "2",
        "--o5=0x67",
        "3",
    };
    var expected_p5: [3]u8 = .{ 1, 2, 3 };
    var expected_o5: [3]u8 = .{ 122, 105, 103 };
    const expected: Args = .{
        .p0 = 12345,
        .p1 = 90,
        .p2 = 39614081257132168796771975167,
        .p3 = 501,
        .p4 = 0,
        .p5 = &expected_p5,
        .@"--o0" = -123,
        .@"--o1" = 123,
        .@"--o2" = -12648430,
        .@"--o3" = 0,
        .@"--o4" = null,
        .@"--o5" = &expected_o5,
    };
    const actual = try quiet_parser.parseAlloc(Args, arena_allocator.allocator(), args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "floats" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const Args = struct {
        p0: f16,
        p1: f32,
        p2: f128,
        p3: []const f64,
        @"--o0": ?f80,
        @"--o1": ?f80,
        @"--o2": f32 = 100,
        @"--o3": []const f32,
    };
    const args: []const []const u8 = &.{
        "--o0",
        "+1",
        "--o1",
        "-1",
        "123",
        "-0_0_0.1_2_3",
        "1.2e-3",
        "0x1.2p-3",
        "--o3=0X7fff_ffee",
        "--o3=001e100",
        "0.0e+0",
    };
    const expected: Args = .{
        .p0 = 123,
        .p1 = -0.123,
        .p2 = 0.0012,
        .p3 = &.{ 0.140625, 0 },
        .@"--o0" = 1,
        .@"--o1" = -1,
        .@"--o2" = 100,
        .@"--o3" = &.{ 2147483648, std.math.inf(f32) },
    };
    const actual = try quiet_parser.parseAlloc(Args, arena_allocator.allocator(), args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "special floats" {
    const Args = struct {
        p0: f32 = 0,
        @"--o0": f32 = 0,
        @"--o1": f32 = 0,
        p1: f32 = 0,
        @"--o2": f32 = 0,
        @"--o3": f32 = 0,
        p2: f32 = 0,
        @"--o4": f32 = 0,
        @"--o5": f32 = 0,
        p3: f32 = 0,
        @"--o6": f32 = 0,
        @"--o7": f32 = 0,
    };
    const args: []const []const u8 = &.{
        "0",
        "--o0=+0.0",
        "--o1=-0x0",
        "inf",
        "--o2=+INF",
        "--o3=-Inf",
        "infinity",
        "--o4=+inFINIty",
        "--o5=-Infinity",
        "nan",
        "--o6=+NaN",
        "--o7=-nAn",
    };
    const actual = try quiet_parser.parse(Args, args);
    try std.testing.expectEqual(0x00000000, @as(u32, @bitCast(actual.p0)));
    try std.testing.expectEqual(0x00000000, @as(u32, @bitCast(actual.@"--o0")));
    try std.testing.expectEqual(0x80000000, @as(u32, @bitCast(actual.@"--o1")));
    try std.testing.expectEqual(std.math.inf(f32), actual.p1);
    try std.testing.expectEqual(std.math.inf(f32), actual.@"--o2");
    try std.testing.expectEqual(-std.math.inf(f32), actual.@"--o3");
    try std.testing.expectEqual(std.math.inf(f32), actual.p2);
    try std.testing.expectEqual(std.math.inf(f32), actual.@"--o4");
    try std.testing.expectEqual(-std.math.inf(f32), actual.@"--o5");
    try std.testing.expect(std.math.isNan(actual.p3));
    try std.testing.expect(std.math.isNan(actual.@"--o6"));
    try std.testing.expect(std.math.isNan(actual.@"--o7"));
}

test "enums" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const E = enum { one, two, three, @"--four" };
    const Args = struct {
        pos: []const E,
        @"--opt": []const E,
        @"--four": bool = false,
    };
    const args: []const []const u8 = &.{
        "one",
        "two",
        "--opt=three",
        "--opt",
        "--four",
        "--four",
        "--",
        "--four",
    };
    const expected: Args = .{
        .pos = &.{ .one, .two, .@"--four" },
        .@"--opt" = &.{ .three, .@"--four" },
        .@"--four" = true,
    };
    const actual = try quiet_parser.parseAlloc(Args, arena_allocator.allocator(), args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "strings" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const Args = struct {
        p0: []const u8,
        p1: [:0]const u8,
        p2: []const []const u8,
        @"--o0": ?[]const u8,
        @"--o1": ?[:0]const u8,
        @"--o2": []const [:0]const u8,
    };
    const args: []const [:0]const u8 = &.{
        "--o0",
        "abc",
        "--o1",
        "def",
        "--o2",
        "ghi",
        "--o2",
        "jkl",
        "--",
        "mno",
        "--o2",
        "pqr",
        "tuv",
        "wxy",
        "zzz",
    };
    const expected: Args = .{
        .p0 = "mno",
        .p1 = "--o2",
        .p2 = &.{ "pqr", "tuv", "wxy", "zzz" },
        .@"--o0" = "abc",
        .@"--o1" = "def",
        .@"--o2" = &.{ "ghi", "jkl" },
    };
    const actual = try quiet_parser.parseAllocZ(Args, arena_allocator.allocator(), args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "void options" {
    const Args = struct {
        @"--aaa": void = {},
        @"--bbb": ?void,
        @"--ccc": ?void,
    };
    const args: []const []const u8 = &.{ "--aaa", "--bbb" };
    const expected: Args = .{ .@"--aaa" = {}, .@"--bbb" = {}, .@"--ccc" = null };
    const actual = try quiet_parser.parse(Args, args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "boolean options" {
    const Args = struct {
        @"--aaa": bool = false,
        @"--bbb": bool = true,
        @"--ccc": ?bool,
        @"--ddd": ?bool,
    };
    const args: []const []const u8 = &.{ "--no-ccc", "--aaa", "--no-bbb" };
    const expected: Args = .{ .@"--aaa" = true, .@"--bbb" = false, .@"--ccc" = false, .@"--ddd" = null };
    const actual = try quiet_parser.parse(Args, args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "sentinel-terminated slices" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const Args = struct {
        pos: [:0xff]u8,
        @"--o1": [:-1]const i32,
        @"--o2": [:65535]const u16,
    };
    const args: []const []const u8 = &.{ "--o1=1", "--o1=2", "0xA", "0xB", "0xC", "--o1", "3" };
    var expected_pos: [3:0xff]u8 = .{ 0xA, 0xB, 0xC };
    const expected: Args = .{
        .pos = &expected_pos,
        .@"--o1" = &.{ 1, 2, 3 },
        .@"--o2" = &.{},
    };
    const actual = try quiet_parser.parseAlloc(Args, arena_allocator.allocator(), args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "--help: string" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
        .program_name = "app",
    };

    const Args = struct {
        foo: []const u8,
        @"--bar": ?[]const u8,
        pub const @"--help" =
            \\Lorem ipsum
            \\dolor sit amet.
        ;
    };
    const expected_help = // The parser ensures that the text is printed with a trailing newline
        \\Lorem ipsum
        \\dolor sit amet.
        \\
    ;
    try std.testing.expectError(error.HelpRequested, parser.parse(Args, &.{"--help"}));
    try std.testing.expectEqualStrings(expected_help, writer.written());

    try std.testing.expectError(error.HelpRequested, quiet_parser.parse(Args, &.{"-h"}));
    try std.testing.expectError(error.HelpRequested, quiet_parser.parse(Args, &.{"-help"}));
    try std.testing.expectError(error.HelpRequested, quiet_parser.parse(Args, &.{ "123", "--help", "--asdf" }));
}

test "--help: std.cli.Help" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
        .program_name = "app",
    };

    const Args = struct {
        foo: []const u8,
        @"--bar": ?[]const u8,
        pub const @"--help": std.cli.Help(@This()) = .{
            .command_name = "command",
            .summary = "A summary summary.",
            .args = .{
                .foo = .{ .description = "Foo foo" },
                .@"--bar" = .{ .description = "Bar bar" },
            },
        };
    };
    const expected_help =
        \\Usage: command [<option>...] [--] <foo>
        \\
        \\A summary summary.
        \\
        \\Arguments:
        \\  <foo>  Foo foo
        \\
        \\Options:
        \\  --bar=<value>  Bar bar
        \\  -h, --help     Print this help and exit
        \\
    ;
    try std.testing.expectError(error.HelpRequested, parser.parse(Args, &.{"--help"}));
    try std.testing.expectEqualStrings(expected_help, writer.written());
}

test "--version: string" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
        .program_name = "app",
    };

    const Args = struct {
        foo: []const u8,
        @"--bar": ?[]const u8,
        pub const @"--version" =
            \\program.exe 0.1.2
            \\Crappyright (💩) 20XX John Doe
        ;
    };
    const expected_version = // The parser ensures that the text is printed with a trailing newline
        \\program.exe 0.1.2
        \\Crappyright (💩) 20XX John Doe
        \\
    ;
    try std.testing.expectError(error.VersionRequested, parser.parse(Args, &.{"--version"}));
    try std.testing.expectEqualStrings(expected_version, writer.written());

    try std.testing.expectError(error.VersionRequested, quiet_parser.parse(Args, &.{ "--version", "--help" }));
    try std.testing.expectError(error.VersionRequested, quiet_parser.parse(Args, &.{ "123", "--version", "--asdf" }));
}

test "--version: std.SemanticVersion" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
        .program_name = "app",
    };

    const Args = struct {
        pub const @"--version": std.SemanticVersion = .{
            .major = 1,
            .minor = 0,
            .patch = 0,
            .pre = "beta",
            .build = "exp.sha.5114f85",
        };
    };
    const expected_version =
        \\1.0.0-beta+exp.sha.5114f85
        \\
    ;
    try std.testing.expectError(error.VersionRequested, parser.parse(Args, &.{"--version"}));
    try std.testing.expectEqualStrings(expected_version, writer.written());
}

test "usage errors" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .stdout = .{ .writer = &failing, .mode = .no_color },
        .stderr = .{ .writer = &writer.writer, .mode = .no_color },
        .program_name = "app",
    };

    const Args = struct {
        a: []const u8,
        b: []const u8,
        c: ?[]const u8,
        d: ?[]const u8,
        @"--one": ?i16,
        @"--two": ?f32,
        @"--three": ?enum { foo, bar, baz },

        fn expectUsageError(expected_first_line: []const u8, actual: []const u8) !void {
            var it = std.mem.splitScalar(u8, actual, '\n');
            try std.testing.expectEqualStrings(expected_first_line, it.first());
            try std.testing.expectEqualStrings("Try 'app --help' for more information.", it.next() orelse return error.TestFailed);
            try std.testing.expectEqualStrings("", it.next() orelse return error.TestFailed); // Trailing newline
            try std.testing.expect(it.next() == null);
        }
    };
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--no-one"}));
    try Args.expectUsageError("error: unrecognized option '--no-one'", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{}));
    try Args.expectUsageError("error: incorrect number of arguments (expected between 2 and 4)", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--one"}));
    try Args.expectUsageError("error: option --one: expected an argument", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--help=me"}));
    try Args.expectUsageError("error: option --help: unexpected argument 'me'", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--one=01_2__3"}));
    try Args.expectUsageError("error: option --one: argument '01_2__3' is not a recognizable integer", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--two=infinitinity"}));
    try Args.expectUsageError("error: option --two: argument 'infinitinity' is not a recognizable floating-point number", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--one=0x8000"}));
    try Args.expectUsageError("error: option --one: argument '0x8000' is outside the allowable range (expected a value between -32768 and 32767 inclusive)", writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Args, &.{"--three=xyz"}));
    try Args.expectUsageError("error: option --three: argument 'xyz' is not a recognizable choice (expected 'foo', 'bar' or 'baz')", writer.written());
}
