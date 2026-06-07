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
//! In addition to parsing command-line arguments into a struct, `ArgsParser` can
//! also recursively parse the command line into a tagged union, where each field is itself
//! a struct or tagged union that represents a subcommand.
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
        .command_name = args[0..1],
        .stdout = .{ .writer = &discarding.writer, .mode = .no_color },
        .stderr = .{ .writer = &discarding.writer, .mode = .no_color },
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
const Terminal = std.Io.Terminal;
const assert = std.debug.assert;

/// The name of the command to be parsed. The value of this field is only used for printing
/// help text and usage error messages and does not affect actual parsing.
/// For top-level commands, this is normally the name of the program obtained from `args[0]`.
/// For subcommands, this is the name of the subcommand and the names of all preceding commands;
/// for example, `&.{ "my_program", "config", "add" }`.
command_name: []const []const u8,

stdout: Terminal,
stderr: Terminal,

pub const ParseError = error{
    /// Command-line usage error.
    Usage,
    /// The user passed the `--help` option.
    HelpRequested,
    /// The user passed the `--version` option.
    VersionRequested,
} || Terminal.SetColorError || std.Io.Writer.Error;

/// Parses a slice of command-line arguments.
/// Asserts at comptime that `T` does not contain any slice fields,
/// which require dynamic memory allocation to populate.
pub fn parse(
    p: ArgsParser,
    comptime T: type,
    /// The slice of command-line arguments to parse (excluding the program/command name).
    args: []const []const u8,
) ParseError!T {
    return p.parseWithMode(T, .{ .alloc = false, .z = false }, {}, args);
}

/// Parses a slice of null-terminated command-line arguments.
/// Asserts at comptime that `T` does not contain any slice fields,
/// which require dynamic memory allocation to populate.
pub fn parseZ(
    p: ArgsParser,
    comptime T: type,
    /// The slice of command-line arguments to parse (excluding the program/command name).
    args: []const [:0]const u8,
) ParseError!T {
    return p.parseWithMode(T, .{ .alloc = false, .z = true }, {}, args);
}

pub const ParseAllocError = ParseError || std.mem.Allocator.Error;

/// Parses a slice of command-line arguments.
/// Slice fields are populated using the specified arena allocator; however, string contents are
/// not copied to new memory and will point to inside the original `args` slice.
pub fn parseAlloc(
    p: ArgsParser,
    comptime T: type,
    arena: std.mem.Allocator,
    /// The slice of command-line arguments to parse (excluding the program/command name).
    args: []const []const u8,
) ParseAllocError!T {
    return p.parseWithMode(T, .{ .alloc = true, .z = false }, arena, args);
}

/// Parses a slice of null-terminated command-line arguments.
/// Slice fields are populated using the specified arena allocator; however, string contents are
/// not copied to new memory and will point to inside the original `args` slice.
pub fn parseAllocZ(
    p: ArgsParser,
    comptime T: type,
    arena: std.mem.Allocator,
    /// The slice of command-line arguments to parse (excluding the program/command name).
    args: []const [:0]const u8,
) ParseAllocError!T {
    return p.parseWithMode(T, .{ .alloc = true, .z = true }, arena, args);
}

const ParseMode = struct { alloc: bool, z: bool };

fn parseWithMode(
    p: ArgsParser,
    comptime T: type,
    comptime mode: ParseMode,
    arena: if (mode.alloc) std.mem.Allocator else void,
    args: []const []const u8,
) !T {
    var state: State = .{
        .maybe_arena = if (mode.alloc) arena else null,
        .tokenizer = .init(args),
        .root_command_prefix = if (p.command_name.len > 1) p.command_name[0..(p.command_name.len - 1)] else &.{},
        .root_command_name = name: {
            if (@hasDecl(T, "--help") and @TypeOf(T.@"--help") == Help(T)) {
                if (T.@"--help".command_name) |help_name| break :name help_name;
            }
            break :name if (p.command_name.len != 0) p.command_name[p.command_name.len - 1] else null;
        },
        .current_subcommand_end = 0,
        .stdout = p.stdout,
        .stderr = p.stderr,
    };
    const root_parser: Specialized(T, mode) = .{ .state = &state };
    return root_parser.parse();
}

const State = struct {
    maybe_arena: ?std.mem.Allocator,
    tokenizer: ArgsTokenizer,
    root_command_prefix: []const []const u8,
    root_command_name: ?[]const u8,
    current_subcommand_end: usize,
    stdout: Terminal,
    stderr: Terminal,
};

fn Specialized(comptime T: type, comptime mode: ParseMode) type {
    return struct {
        state: *State,

        fn arena(p: @This()) if (mode.alloc) std.mem.Allocator else void {
            return if (mode.alloc) p.state.maybe_arena.? else {};
        }

        const FieldClass = enum { required, optional, repeated };

        const fields: type = fields: {
            var p_names: []const [:0]const u8 = &.{};
            var p_types: []const type = &.{};
            var p_classes: []const FieldClass = &.{};
            var o_names: []const [:0]const u8 = &.{};
            var o_types: []const type = &.{};
            var o_classes: []const FieldClass = &.{};
            var subcmd_names: []const [:0]const u8 = &.{};
            switch (@typeInfo(T)) {
                .@"struct" => |struct_info| {
                    for (.{ "--help", "--version" }) |field_name| if (@hasField(T, field_name)) {
                        @compileError("option '" ++ field_name ++ "' is reserved and cannot be declared as a field");
                    };
                    for (struct_info.field_names, struct_info.field_types, struct_info.field_attrs) |f_name, f_type, f_attrs| {
                        const unwrapped_type: type, const class: FieldClass = unwrap: {
                            switch (@typeInfo(f_type)) {
                                .optional => |info| {
                                    break :unwrap .{ info.child, .optional };
                                },
                                .pointer => |info| if (info.size == .slice and !isStringSlice(info)) {
                                    break :unwrap .{ info.child, .repeated };
                                },
                                else => {},
                            }
                            break :unwrap .{ f_type, if (f_attrs.default_value_ptr != null) .optional else .required };
                        };
                        if (f_name[0] == '-') {
                            if (!ArgsTokenizer.isValidLongOptionName(f_name)) {
                                const adjective = if (ArgsTokenizer.isValidShortOptionName(f_name)) "short" else "invalid";
                                @compileError("expected long option name in the form '--foo', found " ++ adjective ++ " option name '" ++ f_name ++ "'");
                            }
                            type_ok: {
                                switch (@typeInfo(unwrapped_type)) {
                                    .void, .bool => if (class != .repeated) break :type_ok,
                                    .int, .float, .@"enum" => break :type_ok,
                                    .pointer => |info| if (isStringSlice(info)) break :type_ok,
                                    else => {},
                                }
                                @compileError("option '" ++ f_name ++ "' has unsupported type '" ++ @typeName(f_type) ++ "'");
                            }
                            if (class == .required) {
                                @compileError("scalar option '" ++ f_name ++ "' must have an optional type or a default field value");
                            }
                            if (f_type == bool) {
                                const negated_name = "--no-" ++ f_name[2..];
                                if (@hasField(T, negated_name)) {
                                    @compileError("option '" ++ negated_name ++ "' conflicts with boolean option '" ++ f_name ++ "'");
                                }
                            }
                            o_names = o_names ++ .{f_name};
                            o_types = o_types ++ .{unwrapped_type};
                            o_classes = o_classes ++ .{class};
                        } else {
                            type_ok: {
                                switch (@typeInfo(unwrapped_type)) {
                                    .int, .float, .@"enum" => break :type_ok,
                                    .pointer => |info| if (isStringSlice(info)) break :type_ok,
                                    else => {},
                                }
                                @compileError("positional '" ++ f_name ++ "' has unsupported type '" ++ @typeName(f_type) ++ "'");
                            }
                            if (p_names.len != 0) {
                                const i = p_names.len - 1;
                                if (p_classes[i] == .repeated) {
                                    @compileError("repeated positional '" ++ p_names[i] ++ "' must be declared after all other positionals");
                                }
                                if (class == .required and p_classes[i] == .optional) {
                                    @compileError("optional positional '" ++ p_names[i] ++ "' must be declared after all required positionals");
                                }
                            }
                            p_names = p_names ++ .{f_name};
                            p_types = p_types ++ .{unwrapped_type};
                            p_classes = p_classes ++ .{class};
                        }
                    }
                },
                .@"union" => |union_info| {
                    for (union_info.field_names, union_info.field_types) |f_name, f_type| {
                        if (f_name[0] == '-') {
                            @compileError("expected subcommand name, found option name '" ++ f_name ++ "'");
                        }
                        field_type_ok: {
                            switch (@typeInfo(T)) {
                                .@"struct" => break :field_type_ok,
                                .@"union" => |info| if (info.tag_type != null) break :field_type_ok,
                                else => {},
                            }
                            @compileError("subcommand '" ++ f_name ++ "' has unsupported type '" ++ @typeName(f_type) ++ "'");
                        }
                        subcmd_names = subcmd_names ++ .{f_name};
                    }
                    if (subcmd_names.len == 0) {
                        @compileError("tagged union must declare at least one subcommand field");
                    }
                },
                else => unreachable,
            }
            break :fields struct {
                const positional_names: []const [:0]const u8 = p_names;
                const positional_types: []const type = p_types;
                const positional_classes: []const FieldClass = p_classes;
                const option_names: []const [:0]const u8 = o_names;
                const option_types: []const type = o_types;
                const option_classes: []const FieldClass = o_classes;
                const subcommand_names: []const [:0]const u8 = subcmd_names;
            };
        };

        fn isStringSlice(info: std.lang.Type.Pointer) bool {
            return info.size == .slice and info.attrs.@"const" and info.child == u8 and (info.sentinel() orelse 0) == 0;
        }

        fn parse(p: @This()) !T {
            switch (@typeInfo(T)) {
                .@"struct" => return p.parseArgs(),
                .@"union" => |info| if (info.tag_type != null) return p.parseSubcommand(),
                else => {},
            }
            @compileError("expected struct or tagged union, found '" ++ @typeName(T) ++ "'");
        }

        fn parseArgs(p: @This()) !T {
            const ArrayLists: type, //
            const required_positional_count: usize, //
            const optional_positional_count: usize, //
            const option_names: []const [:0]const u8, //
            const option_arities: []const ArgsTokenizer.OptionArity, //
            const original_options_end: usize, //
            const negated_options_end: usize, //
            const help_options_end: usize //
            = comptime info: {
                assert(fields.subcommand_names.len == 0);
                var list_field_names: []const [:0]const u8 = &.{};
                var list_field_types: []const type = &.{};
                var list_field_attrs: []const std.lang.Type.Struct.FieldAttributes = &.{};
                var required_positional_count: usize = 0;
                var optional_positional_count: usize = 0;
                for (fields.positional_names, fields.positional_types, fields.positional_classes, 0..) |p_name, p_type, p_class, i| {
                    switch (p_class) {
                        .required => {
                            assert(optional_positional_count == 0);
                            required_positional_count += 1;
                        },
                        .optional => {
                            optional_positional_count += 1;
                        },
                        .repeated => {
                            assert(i == fields.positional_names.len - 1);
                            optional_positional_count = std.math.maxInt(usize);
                            list_field_names = list_field_names ++ .{p_name};
                            list_field_types = list_field_types ++ .{std.ArrayList(p_type)};
                            list_field_attrs = list_field_attrs ++ .{@as(
                                std.lang.Type.Struct.FieldAttributes,
                                .{ .default_value_ptr = &std.ArrayList(p_type).empty },
                            )};
                        },
                    }
                }

                var option_arities: []const ArgsTokenizer.OptionArity = &.{};
                var negated_option_names: []const [:0]const u8 = &.{};
                for (fields.option_names, fields.option_types, fields.option_classes) |o_name, o_type, o_class| {
                    if (o_class == .repeated) {
                        list_field_names = list_field_names ++ .{o_name};
                        list_field_types = list_field_types ++ .{std.ArrayList(o_type)};
                        list_field_attrs = list_field_attrs ++ .{@as(
                            std.lang.Type.Struct.FieldAttributes,
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

                var option_names = fields.option_names;
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
                const struct_info = @typeInfo(T).@"struct";
                for (struct_info.field_names, struct_info.field_types, struct_info.field_attrs) |f_name, f_type, f_attrs| {
                    const default_value: ?f_type = f_attrs.defaultValue(f_type) orelse switch (@typeInfo(f_type)) {
                        .optional => @as(f_type, null),
                        else => @as(?f_type, null),
                    };
                    if (default_value) |value| {
                        @field(result_init, f_name) = value;
                    }
                }
                break :init result_init;
            };

            var result_lists: ArrayLists = .{};
            errdefer inline for (@typeInfo(ArrayLists).@"struct".field_names) |f_name| {
                @field(result_lists, f_name).deinit(p.arena());
            };

            var positional_index: usize = 0;
            while (p.state.tokenizer.nextDynamic(option_names, option_arities)) |token| switch (token) {
                .option => |option| switch (option.index) {
                    inline 0...(option_names.len - 1) => |i| {
                        const option_name = option_names[i];
                        if (i < original_options_end) {
                            const parsed_arg = try p.parseArg(option_name, fields.option_types[i], option.arg);
                            if (fields.option_classes[i] == .repeated) {
                                // Repeated option
                                try @field(result_lists, option_name).append(p.arena(), parsed_arg);
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
                            return try p.printHelp();
                        } else {
                            // --version
                            return try p.printVersion();
                        }
                    },
                    else => unreachable,
                },
                .end_of_options => {},
                .positional => |positional_arg| if (fields.positional_names.len != 0) switch (positional_index) {
                    inline 0...(fields.positional_names.len - 1) => |i| {
                        const positional_name = fields.positional_names[i];
                        const parsed_arg = try p.parseArg(null, fields.positional_types[i], positional_arg);
                        if (fields.positional_classes[i] == .repeated) {
                            // Repeated positional
                            try @field(result_lists, positional_name).append(p.arena(), parsed_arg);
                        } else {
                            // Scalar positional
                            @field(result, positional_name) = parsed_arg;
                            positional_index += 1;
                        }
                    },
                    else => {
                        return try p.failIncorrectArgCount(required_positional_count, optional_positional_count);
                    },
                } else {
                    return try p.failMissingOrUnexpectedArg(null, positional_arg);
                },
                .invalid_option => |invalid| switch (invalid.err) {
                    error.UnrecognizedOption => {
                        return try p.failUnrecognizedOptionOrCommand("option", invalid.name.slice());
                    },
                    error.MissingOptionArg, error.UnexpectedOptionArg => {
                        return try p.failMissingOrUnexpectedArg(invalid.name.slice(), invalid.arg);
                    },
                },
            };

            if (positional_index < required_positional_count) {
                if (required_positional_count == 1 and optional_positional_count == 0) {
                    return try p.failMissingOrUnexpectedArg(null, null);
                } else {
                    return try p.failIncorrectArgCount(required_positional_count, optional_positional_count);
                }
            }

            inline for (@typeInfo(ArrayLists).@"struct".field_names) |f_name| {
                if (@typeInfo(@FieldType(T, f_name)).pointer.sentinel()) |s| {
                    @field(result, f_name) = try @field(result_lists, f_name).toOwnedSliceSentinel(p.arena(), s);
                } else {
                    @field(result, f_name) = try @field(result_lists, f_name).toOwnedSlice(p.arena());
                }
            }

            return result;
        }

        fn parseArg(p: @This(), option_name: ?[]const u8, comptime Arg: type, arg: ?[]const u8) !Arg {
            switch (@typeInfo(Arg)) {
                .void => {
                    assert(arg == null);
                    return;
                },
                .bool => {
                    assert(arg == null);
                    return true;
                },
                .int => {
                    return std.fmt.parseInt(Arg, arg.?, 0) catch |err| switch (err) {
                        error.InvalidCharacter => try p.failInvalidNumber(option_name, arg.?, "integer"),
                        error.Overflow => try p.failNumberOutOfRange(option_name, arg.?, std.math.minInt(Arg), std.math.maxInt(Arg)),
                    };
                },
                .float => {
                    return std.fmt.parseFloat(Arg, arg.?) catch |err| switch (err) {
                        error.InvalidCharacter => try p.failInvalidNumber(option_name, arg.?, "floating-point number"),
                    };
                },
                .@"enum" => {
                    return std.meta.stringToEnum(Arg, arg.?) orelse {
                        try p.failInvalidChoice(option_name, arg.?, @typeInfo(Arg).@"enum".field_names);
                    };
                },
                .pointer => {
                    if (mode.z) {
                        // This is perfectly safe; the tokenizer guarantees that sentinels are preserved.
                        return arg.?.ptr[0..arg.?.len :0];
                    }
                    return arg.?;
                },
                else => comptime unreachable,
            }
        }

        fn parseSubcommand(p: @This()) !T {
            const option_names: []const [:0]const u8, //
            const option_arities: []const ArgsTokenizer.OptionArity, //
            const help_options_end: usize //
            = comptime info: {
                assert(fields.positional_names.len == 0);
                assert(fields.option_names.len == 0);
                var option_names: []const [:0]const u8 = &.{ "-h", "--help" };
                const help_options_end = option_names.len;
                if (@hasDecl(T, "--version")) {
                    option_names = option_names ++ .{"--version"};
                }
                const option_arities: *const [option_names.len]ArgsTokenizer.OptionArity = &@splat(.no_arg);
                break :info .{
                    option_names,
                    option_arities,
                    help_options_end,
                };
            };

            const token = p.state.tokenizer.nextDynamic(option_names, option_arities) orelse {
                try p.failMissingOrUnexpectedArg(null, null);
            };
            switch (token) {
                .option => |option| switch (option.index) {
                    inline 0...(option_names.len - 1) => |i| if (i < help_options_end) {
                        return try p.printHelp();
                    } else {
                        return try p.printVersion();
                    },
                    else => unreachable,
                },
                .end_of_options => {
                    // '--' is not recognized as the end-of-options delimiter in this position
                    return try p.failUnrecognizedOptionOrCommand("option", "--");
                },
                .positional => |actual_subcmd_name| inline for (fields.subcommand_names) |recognized_subcmd_name| {
                    if (std.mem.eql(u8, recognized_subcmd_name, actual_subcmd_name)) {
                        p.state.current_subcommand_end += 1;
                        const child_parser: Specialized(@FieldType(T, recognized_subcmd_name), mode) = .{ .state = p.state };
                        return @unionInit(T, recognized_subcmd_name, try child_parser.parse());
                    }
                } else {
                    return try p.failUnrecognizedOptionOrCommand("command", actual_subcmd_name);
                },
                .invalid_option => |invalid| switch (invalid.err) {
                    error.UnrecognizedOption => {
                        return try p.failUnrecognizedOptionOrCommand("option", invalid.name.slice());
                    },
                    error.MissingOptionArg => unreachable,
                    error.UnexpectedOptionArg => {
                        return try p.failMissingOrUnexpectedArg(invalid.name.slice(), invalid.arg);
                    },
                },
            }
        }

        fn failUnrecognizedOptionOrCommand(p: @This(), noun: []const u8, name: []const u8) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(null);
            try term.writer.print("unrecognized {s} ", .{noun});
            try p.failQuote(.yellow, name);
            return p.failSuffix();
        }

        fn failIncorrectArgCount(p: @This(), required: usize, optional: usize) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(null);
            try term.writer.writeAll("incorrect number of arguments (expected ");
            var last = required;
            if (optional != 0) {
                if (optional == std.math.maxInt(usize)) {
                    try term.writer.writeAll("at least ");
                } else {
                    if (required == 0) {
                        try term.writer.writeAll("at most ");
                    } else {
                        try term.writer.print("between {d} and ", .{required});
                    }
                    last = required + optional;
                }
            }
            try term.writer.print("{d})", .{last});
            return p.failSuffix();
        }

        fn failMissingOrUnexpectedArg(p: @This(), option_name: ?[]const u8, arg: ?[]const u8) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(option_name);
            if (arg) |x| {
                try term.writer.writeAll("unexpected argument ");
                try p.failQuote(.yellow, x);
            } else {
                try term.writer.writeAll("expected an argument");
            }
            return p.failSuffix();
        }

        fn failInvalidNumber(p: @This(), option_name: ?[]const u8, arg: []const u8, noun: []const u8) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(option_name);
            try term.writer.writeAll("argument ");
            try p.failQuote(.yellow, arg);
            try term.writer.print(" is not a recognizable {s}", .{noun});
            return p.failSuffix();
        }

        fn failNumberOutOfRange(p: @This(), option_name: ?[]const u8, arg: []const u8, comptime min: comptime_int, comptime max: comptime_int) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(option_name);
            try term.writer.writeAll("argument ");
            try p.failQuote(.yellow, arg);
            try term.writer.writeAll(" is outside the allowable range (expected a value between ");
            try term.setColor(.bold);
            try term.writer.print("{d}", .{min});
            try term.setColor(.reset);
            try term.writer.writeAll(" and ");
            try term.setColor(.bold);
            try term.writer.print("{d}", .{max});
            try term.setColor(.reset);
            try term.writer.writeAll(" inclusive)");
            return p.failSuffix();
        }

        fn failInvalidChoice(p: @This(), option_name: ?[]const u8, arg: []const u8, choices: []const []const u8) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try p.failPrefix(option_name);
            try term.writer.writeAll("argument ");
            try p.failQuote(.yellow, arg);
            try term.writer.writeAll(" is not a recognizable choice (expected ");
            try p.failQuote(.bold, choices[0]);
            for (choices[1..(choices.len - 1)]) |choice| {
                try term.writer.writeAll(", ");
                try p.failQuote(.bold, choice);
            }
            if (choices.len > 1) {
                try term.writer.writeAll(" or ");
                try p.failQuote(.bold, choices[choices.len - 1]);
            }
            try term.writer.writeByte(')');
            return p.failSuffix();
        }

        fn failPrefix(p: @This(), option_name: ?[]const u8) !void {
            @branchHint(.cold);
            const term = p.state.stderr;
            try term.setColor(.bold);
            try term.setColor(.red);
            try term.writer.writeAll("error:");
            try term.setColor(.reset);
            try term.writer.writeByte(' ');
            if (option_name) |name| {
                try term.setColor(.bold);
                try term.writer.print("option {s}:", .{name});
                try term.setColor(.reset);
                try term.writer.writeByte(' ');
            }
        }

        fn failSuffix(p: @This()) !noreturn {
            @branchHint(.cold);
            const term = p.state.stderr;
            try term.writer.writeAll("\nTry ");
            try term.setColor(.bold);
            try term.writer.writeByte('\'');
            for (p.state.root_command_prefix) |name| {
                try term.writer.print("{s} ", .{name});
            }
            if (p.state.root_command_name) |name| {
                try term.writer.print("{s} ", .{name});
            }
            for (p.state.tokenizer.args[0..p.state.current_subcommand_end]) |name| {
                try term.writer.print("{s} ", .{name});
            }
            try term.writer.writeAll("--help'");
            try term.setColor(.reset);
            try term.writer.writeAll(" for more information.\n");
            try term.writer.flush();
            return error.Usage;
        }

        fn failQuote(p: @This(), color: Terminal.Color, value: []const u8) !void {
            @branchHint(.cold);
            const term = p.state.stderr;
            try term.setColor(color);
            try term.writer.print("'{s}'", .{value});
            try term.setColor(.reset);
        }

        fn printHelp(p: @This()) !noreturn {
            @branchHint(.cold);
            const term = p.state.stdout;
            const help: *const Help(T) = help: {
                if (!@hasDecl(T, "--help")) {
                    break :help comptime &.{ .args = std.mem.zeroInit(Help(T).Args, .{}) };
                }
                if (@TypeOf(T.@"--help") == Help(T)) {
                    break :help &T.@"--help";
                }
                if (@typeInfo(@TypeOf(T.@"--help")) == .pointer) {
                    const string = T.@"--help";
                    try term.writer.writeAll(string);
                    if (string.len != 0 and string[string.len - 1] != '\n') {
                        try term.writer.writeByte('\n');
                    }
                    try term.writer.flush();
                    return error.HelpRequested;
                }
                @compileError("unsupported '--help' type: expected '[]const u8' or 'std.cli.Help(" ++ @typeName(T) ++ ")', found '" ++ @typeName(@TypeOf(T.@"--help")) ++ "'");
            };
            try term.setColor(.bold);
            try term.writer.writeAll("Usage:");
            try term.setColor(.reset);
            for (p.state.root_command_prefix) |name| {
                try term.writer.writeByte(' ');
                try term.setColor(.bold);
                try term.writer.writeAll(name);
                try term.setColor(.reset);
            }
            if (p.state.root_command_name) |name| {
                try term.writer.writeByte(' ');
                try term.setColor(.bold);
                try term.writer.writeAll(name);
                try term.setColor(.reset);
            }
            for (p.state.tokenizer.args[0..p.state.current_subcommand_end]) |name| {
                try term.writer.writeByte(' ');
                try term.setColor(.bold);
                try term.writer.writeAll(name);
                try term.setColor(.reset);
            }
            try renderUsageTokens(term, .reset, " [<option>...]", .reset);
            switch (@typeInfo(T)) {
                .@"struct" => {
                    var brackets: usize = 0;
                    var max_positional_width: ?usize = null;
                    inline for (fields.positional_names, fields.positional_classes) |p_name, p_class| @"continue": {
                        const arg_help: Help(T).Arg = @field(help.args, p_name);
                        if (p_class != .required and arg_help.hidden) break :@"continue";
                        if (max_positional_width == null) {
                            try renderUsageTokens(term, .reset, " [--]", .reset);
                        }
                        try term.writer.writeByte(' ');
                        if (p_class != .required) {
                            try term.writer.writeByte('[');
                            brackets += 1;
                        }
                        const display = arg_help.display orelse defaultPositionalDisplay(p_name, p_class);
                        try renderUsageTokens(term, .reset, display, .reset);
                        max_positional_width = @max(max_positional_width orelse 0, display.len);
                    }
                    if (brackets != 0) {
                        try term.writer.splatByteAll(']', brackets);
                    }
                    if (help.description) |description| {
                        try term.writer.print("\n\n{s}", .{description});
                    }
                    if (max_positional_width) |max_width| {
                        try term.writer.writeAll("\n\n");
                        try term.setColor(.bold);
                        try term.writer.writeAll("Arguments:");
                        try term.setColor(.reset);
                        inline for (fields.positional_names, fields.positional_classes) |p_name, p_class| @"continue": {
                            const arg_help: Help(T).Arg = @field(help.args, p_name);
                            if (p_class != .required and arg_help.hidden) break :@"continue";
                            try term.writer.writeAll("\n  ");
                            const display = arg_help.display orelse defaultPositionalDisplay(p_name, p_class);
                            try renderUsageTokens(term, .reset, display, .reset);
                            if (arg_help.description) |description| {
                                try term.writer.splatByteAll(' ', max_width - display.len + 2);
                                try term.writer.writeAll(description);
                            }
                        }
                    }
                },
                .@"union" => {
                    try renderUsageTokens(term, .reset, " <command> [<argument>...]", .reset);
                    if (help.description) |description| {
                        try term.writer.print("\n\n{s}", .{description});
                    }
                    var max_subcommand_width: ?usize = null;
                    inline for (fields.subcommand_names) |subcmd_name| @"continue": {
                        const subcmd_help: Help(T).Arg = @field(help.args, subcmd_name);
                        if (subcmd_help.hidden) break :@"continue";
                        max_subcommand_width = @max(max_subcommand_width orelse 0, subcmd_name.len);
                    }
                    if (max_subcommand_width) |max_width| {
                        try term.writer.writeAll("\n\n");
                        try term.setColor(.bold);
                        try term.writer.writeAll("Commands:");
                        try term.setColor(.reset);
                        inline for (fields.subcommand_names) |subcmd_name| @"continue": {
                            const subcmd_help: Help(T).Arg = @field(help.args, subcmd_name);
                            if (subcmd_help.hidden) break :@"continue";
                            try term.writer.writeAll("\n  ");
                            try term.setColor(.bold);
                            try term.writer.writeAll(subcmd_name);
                            try term.setColor(.reset);
                            if (subcmd_help.description) |description| {
                                try term.writer.splatByteAll(' ', max_width - subcmd_name.len + 2);
                                try term.writer.writeAll(description);
                            }
                        }
                    }
                },
                else => comptime unreachable,
            }
            try term.writer.writeAll("\n\n");
            try term.setColor(.bold);
            try term.writer.writeAll("Options:");
            try term.setColor(.reset);
            var max_option_width: usize = "-h, --help".len;
            inline for (fields.option_names, fields.option_types) |o_name, o_type| @"continue": {
                const arg_help: Help(T).Arg = @field(help.args, o_name);
                if (arg_help.hidden) break :@"continue";
                var width: usize = o_name.len;
                switch (o_type) {
                    void => {},
                    bool => {
                        width += "[no-]".len;
                    },
                    else => {
                        const display = arg_help.display orelse defaultOptionDisplay(o_type);
                        width += "=".len + display.len;
                    },
                }
                max_option_width = @max(max_option_width, width);
            }
            inline for (fields.option_names, fields.option_types) |o_name, o_type| @"continue": {
                const arg_help: Help(T).Arg = @field(help.args, o_name);
                if (arg_help.hidden) break :@"continue";
                try term.writer.writeAll("\n  ");
                var width: usize = o_name.len;
                try term.setColor(.bold);
                try term.writer.writeAll("--");
                if (o_type == bool) {
                    width += "[no-]".len;
                    try renderUsageTokens(term, .bold, "[no-]", .bold);
                }
                try term.writer.writeAll(o_name[2..]);
                if (o_type == void or o_type == bool) {
                    try term.setColor(.reset);
                } else {
                    try term.writer.writeByte('=');
                    const display = arg_help.display orelse defaultOptionDisplay(o_type);
                    width += "=".len + display.len;
                    try renderUsageTokens(term, .bold, display, .reset);
                }
                if (arg_help.description) |description| {
                    try term.writer.splatByteAll(' ', max_option_width - width + 2);
                    try term.writer.writeAll(description);
                }
            }
            try term.writer.writeAll("\n  ");
            try term.setColor(.bold);
            try term.writer.writeAll("-h");
            try term.setColor(.reset);
            try term.writer.writeAll(", ");
            try term.setColor(.bold);
            try term.writer.writeAll("--help");
            try term.setColor(.reset);
            try term.writer.splatByteAll(' ', max_option_width - "-h, --help".len + 2);
            try term.writer.writeAll("Print this help and exit");
            if (@hasDecl(T, "--version")) {
                try term.writer.writeAll("\n  ");
                try renderUsageTokens(term, .reset, "--version", .reset);
                try term.writer.splatByteAll(' ', max_option_width - "--version".len + 2);
                try term.writer.writeAll("Print version and exit");
            }
            try term.writer.writeByte('\n');
            try term.writer.flush();
            return error.HelpRequested;
        }

        fn printVersion(p: @This()) !noreturn {
            @branchHint(.cold);
            const term = p.state.stdout;
            if (@TypeOf(T.@"--version") == std.SemanticVersion) {
                try term.writer.print("{f}\n", .{T.@"--version"});
            } else if (@typeInfo(@TypeOf(T.@"--version")) == .pointer) {
                const string = T.@"--version";
                try term.writer.writeAll(string);
                if (string.len != 0 and string[string.len - 1] != '\n') {
                    try term.writer.writeByte('\n');
                }
            } else {
                @compileError("unsupported '--version' type: expected '[]const u8' or 'std.SemanticVersion', found '" ++ @typeName(@TypeOf(T.@"--version")) ++ "'");
            }
            try term.writer.flush();
            return error.VersionRequested;
        }

        /// Styles commands/arguments/options in a usage message,
        /// roughly according to the conventions prescribed by man-pages(7):
        ///
        /// > [...] boldface is used for as-is text and italics are used to indicate replaceable
        /// > arguments. Brackets ([]) surround optional arguments, vertical bars (|) separate
        /// > choices, and ellipses (...) can be repeated.
        ///
        /// <https://man7.org/linux/man-pages/man7/man-pages.7.html>
        fn renderUsageTokens(term: Terminal, start_color: Terminal.Color, tokens: []const u8, end_color: Terminal.Color) !void {
            @branchHint(.cold);
            var color: Terminal.Color = start_color;
            var i: usize = 0;
            while (i < tokens.len) switch (tokens[i]) {
                ' ', '(', ')', '[', ']', '|' => {
                    if (color != .reset) {
                        try term.setColor(.reset);
                        color = .reset;
                    }
                    try term.writer.writeByte(tokens[i]);
                    i += 1;
                },
                '.' => {
                    if (tokens.len - i >= 3 and tokens[i + 1] == '.' and tokens[i + 2] == '.') {
                        if (color != .reset) {
                            try term.setColor(.reset);
                            color = .reset;
                        }
                        try term.writer.writeAll("...");
                        i += 3;
                    } else {
                        if (color != .bold) {
                            if (color != .reset) {
                                try term.setColor(.reset);
                            }
                            try term.setColor(.bold);
                            color = .bold;
                        }
                        try term.writer.writeByte(tokens[i]);
                        i += 1;
                    }
                },
                '<' => {
                    if (color != .reset) {
                        try term.setColor(.reset);
                        color = .reset;
                    }
                    // 'std.Io.Terminal.Color' is currently missing italics
                    // (and other common SGR styles).
                    if (term.mode == .escape_codes) {
                        try term.writer.writeAll("\x1b[3m");
                    }
                    const end = (std.mem.findScalarPos(u8, tokens, i, '>') orelse tokens.len - 1) + 1;
                    try term.writer.writeAll(tokens[i..end]);
                    i = end;
                    try term.setColor(.reset);
                    color = .reset;
                },
                else => {
                    if (color != .bold) {
                        if (color != .reset) {
                            try term.setColor(.reset);
                        }
                        try term.setColor(.bold);
                        color = .bold;
                    }
                    try term.writer.writeByte(tokens[i]);
                    i += 1;
                },
            };
            if (color != end_color) {
                if (color != .reset and end_color != .reset) {
                    try term.setColor(.reset);
                }
                try term.setColor(end_color);
            }
        }

        fn defaultPositionalDisplay(comptime p_name: []const u8, comptime p_class: FieldClass) []const u8 {
            @branchHint(.cold);
            return comptime display: {
                var copy = p_name[0..].*;
                std.mem.replaceScalar(u8, &copy, '_', '-');
                break :display "<" ++ copy ++ ">" ++ (if (p_class == .repeated) "..." else "");
            };
        }

        fn defaultOptionDisplay(comptime o_type: type) []const u8 {
            @branchHint(.cold);
            return comptime switch (@typeInfo(o_type)) {
                .void, .bool => unreachable, // These don't take arguments
                .int, .float => "<number>",
                .@"enum" => "<choice>",
                .pointer => "<value>",
                else => unreachable, // Unsupported
            };
        }
    };
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
const noop_terminal: Terminal = .{ .writer = &noop_writer, .mode = .no_color };
const quiet_parser: ArgsParser = .{
    .command_name = &.{},
    .stdout = noop_terminal,
    .stderr = noop_terminal,
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
        .command_name = &.{"app"},
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
    };

    const Args = struct {
        foo: [:0]const u8,
        @"--bar": ?[:0]const u8,
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
    try std.testing.expectError(error.HelpRequested, parser.parseZ(Args, &.{"--help"}));
    try std.testing.expectEqualStrings(expected_help, writer.written());

    try std.testing.expectError(error.HelpRequested, quiet_parser.parseZ(Args, &.{"-h"}));
    try std.testing.expectError(error.HelpRequested, quiet_parser.parseZ(Args, &.{"-help"}));
    try std.testing.expectError(error.HelpRequested, quiet_parser.parseZ(Args, &.{ "123", "--help", "--asdf" }));
}

test "--help: std.cli.Help" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .command_name = &.{"app"},
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
    };

    const Args = struct {
        foo: [:0]const u8,
        @"--bar": ?[:0]const u8,
        pub const @"--help": std.cli.Help(@This()) = .{
            .command_name = "command",
            .description = "A descriptive description.",
            .args = .{
                .foo = .{ .description = "Foo foo" },
                .@"--bar" = .{ .description = "Bar bar" },
            },
        };
    };
    const expected_help =
        \\Usage: command [<option>...] [--] <foo>
        \\
        \\A descriptive description.
        \\
        \\Arguments:
        \\  <foo>  Foo foo
        \\
        \\Options:
        \\  --bar=<value>  Bar bar
        \\  -h, --help     Print this help and exit
        \\
    ;
    try std.testing.expectError(error.HelpRequested, parser.parseZ(Args, &.{"--help"}));
    try std.testing.expectEqualStrings(expected_help, writer.written());
}

test "--version: string" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .command_name = &.{"app"},
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
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
        .command_name = &.{"app"},
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
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
        .command_name = &.{"app"},
        .stdout = .{ .writer = &failing, .mode = .no_color },
        .stderr = .{ .writer = &writer.writer, .mode = .no_color },
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

test "subcommands: parsing" {
    const Command = union(enum) {
        one: struct {
            a: i32,
            @"--foo": ?[]const u8,
        },
        two: union(enum) {
            three: struct {
                b: i32,
                @"--bar": ?[]const u8,
            },
            four: struct {
                c: i32,
                @"--baz": ?[]const u8,
            },
        },
    };
    const args: []const []const u8 = &.{ "two", "four", "123", "--baz", "xyz" };
    const expected: Command = .{
        .two = .{
            .four = .{
                .c = 123,
                .@"--baz" = "xyz",
            },
        },
    };
    const actual = try quiet_parser.parse(Command, args);
    try std.testing.expectEqualDeep(expected, actual);
}

test "subcommands: --help and --version" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .command_name = &.{"app"},
        .stdout = .{ .writer = &writer.writer, .mode = .no_color },
        .stderr = .{ .writer = &failing, .mode = .no_color },
    };

    const Command = union(enum) {
        one: struct {},
        two: struct {},
        three: struct {},
        four: union(enum) {
            five: struct {},
            six: struct {},
            pub const @"--help": std.cli.Help(@This()) = .{
                .command_name = "this-should-not-be-printed",
                .description = "This is a subcommand.",
                .args = .{
                    .five = .{ .description = "Cinco" },
                    .six = .{ .description = "Seis" },
                },
            };
            pub const @"--version": std.SemanticVersion = .{ .major = 0, .minor = 2, .patch = 3 };
        },
        pub const @"--help": std.cli.Help(@This()) = .{
            .command_name = "root",
            .args = .{
                .one = .{},
                .two = .{},
                .three = .{},
                .four = .{},
            },
        };
        pub const @"--version": std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };
    };
    const expected_help =
        \\Usage: root four [<option>...] <command> [<argument>...]
        \\
        \\This is a subcommand.
        \\
        \\Commands:
        \\  five  Cinco
        \\  six   Seis
        \\
        \\Options:
        \\  -h, --help  Print this help and exit
        \\  --version   Print version and exit
        \\
    ;
    try std.testing.expectError(error.HelpRequested, parser.parse(Command, &.{ "four", "--help" }));
    try std.testing.expectEqualStrings(expected_help, writer.written());
    writer.clearRetainingCapacity();
    const expected_version =
        \\0.2.3
        \\
    ;
    try std.testing.expectError(error.VersionRequested, parser.parse(Command, &.{ "four", "--version" }));
    try std.testing.expectEqualStrings(expected_version, writer.written());
}

test "subcommands: usage errors" {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    var writer: std.Io.Writer.Allocating = .init(arena_allocator.allocator());
    var failing: std.Io.Writer = .failing;
    const parser: std.cli.ArgsParser = .{
        .command_name = &.{"app"},
        .stdout = .{ .writer = &failing, .mode = .no_color },
        .stderr = .{ .writer = &writer.writer, .mode = .no_color },
    };

    const Command = union(enum) {
        one: struct {},
        two: struct {},
        three: struct {},
        four: union(enum) {
            five: struct {
                @"--foo": ?u8,
                pub const @"--help": std.cli.Help(@This()) = .{
                    .command_name = "this-should-not-be-printed",
                    .args = .{
                        .@"--foo" = .{},
                    },
                };
            },
            six: struct {},
            pub const @"--help": std.cli.Help(@This()) = .{
                .command_name = "this-should-not-be-printed",
                .args = .{
                    .five = .{},
                    .six = .{},
                },
            };
        },
    };
    try std.testing.expectError(error.Usage, parser.parse(Command, &.{}));
    try std.testing.expectEqualStrings(
        \\error: expected an argument
        \\Try 'app --help' for more information.
        \\
    , writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Command, &.{"--foo"}));
    try std.testing.expectEqualStrings(
        \\error: unrecognized option '--foo'
        \\Try 'app --help' for more information.
        \\
    , writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Command, &.{"four"}));
    try std.testing.expectEqualStrings(
        \\error: expected an argument
        \\Try 'app four --help' for more information.
        \\
    , writer.written());
    writer.clearRetainingCapacity();
    try std.testing.expectError(error.Usage, parser.parse(Command, &.{ "four", "five", "--foo=-1" }));
    try std.testing.expectEqualStrings(
        \\error: option --foo: argument '-1' is outside the allowable range (expected a value between 0 and 255 inclusive)
        \\Try 'app four five --help' for more information.
        \\
    , writer.written());
}
