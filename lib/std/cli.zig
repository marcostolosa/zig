/// Command-line argument parser
const cli = @This();

const std = @import("std.zig");
const assert = std.debug.assert;
const cutPrefixSentinel = std.mem.cutPrefixSentinel;

/// A recursive representation of the commands available in a CLI.
pub const Command = struct {
    /// If this is the root command, has no effect. Example: `git`.
    /// Name of the corresponding tagged union field in `parsed.subcommands.?`.
    /// Name of the subcommand in the cli.
    /// To obtain a dashed-command like `git merge-base`, provide `.name = "merge-base"` and access with `parsed.subcommands.?.@"merge-base"`.
    name: [:0]const u8,
    /// Named arguments are arguments that begin with `--` in the CLI, or `-` for shorthands, like `git commit --message "std.cli"` or `git commit -m "std.cli"`.
    named_args: []const Argument = &.{},
    /// Positional arguments are arguments parsed by their position after the command. Like the branch name in `git branch dev/std.cli`.
    positional_args: []const Argument = &.{},
    /// The subcommands of this command. Like `commit` in `git commit`.
    subcommands: []const Command = &.{},
    /// The help text for this command. For example the text returned by `git --help`.
    /// Typically ends in a newline (`"\n"`).
    help: [:0]const u8 = "",
    /// Included only to allow easier auto-generation of help-text by libraries outside of std.
    /// Typically the single-line help sentence for subcommands.
    help_short: [:0]const u8 = "",
};

pub const Argument = struct {
    field: std.builtin.Type.StructField,
    count: Count,
    /// Included only to allow easier auto-generation of help-text by libraries outside of std.
    /// Typically the single-line help sentence next to each option in a list of options.
    help: [:0]const u8,
    /// If non-null, allows named arguments to have single character aliases.
    /// Example: `git commit -m "std.cli"` and `git commit --message` parse results are identical.
    /// Has no effect for positional arguments.
    short: ?u8,

    pub const Count = enum {
        /// If the argument is provided multiple times, the last instance is the result.
        /// Example: `git --verbose --no-verbose` results in a single false bool for `parsed.kind.args.verbose`.
        one,
        /// If the argument is provided multiple times, they are accumulated into a slice.
        /// Example: `git commit --message "Paragraph 1" --message "Paragraph 2"` results in `&.{"Paragraph 1", "Paragraph 2"}` and args.message is a `[]const []const u8` (the provided `T` must be a slice type).
        unlimited,
    };

    pub fn init(
        /// The type of the corresponding field in `parsed.kind.args`.
        ///
        /// - bool: `--verbose`, `--verbose=true`, `-v` result in true. `--no-verbose`, `--verbose=false`, `-v=false` result in false.
        /// - enum: string input corresponding to each enum field. Example: `--log-level debug` results in `.debug`.
        /// - integer: uses `std.fmt.parseInt` to parse an integer.
        /// - float: uses `std.fmt.parseFloat` to parse a float.
        /// - `[]const u8`: a string. Example: `git branch dev/std.cli` results in `"dev/std.cli"`. `[:0]const u8` is also supported.
        /// - `?T`: when the user does not provide the argument, results in `null`. `null` is the only supported default value.
        ///
        /// For `.count = .unlimited` arguments, provide a `[]T`. Example: `git add README.md build.zig.zon` can be parsed with `[]const []const u8` as `&.{"README.md", "build.zig.zon"}`.
        comptime T: type,
        comptime options: struct {
            /// Name of the corresponding field in `parsed.kind.args`.
            /// Prefixed with `--` for the CLI user.
            /// Example: `git commit --message "std.cli"` has `.name = "message"` and parsed.kind.args.message is `"std.cli"`.
            ///
            /// To obtain dashed arguments like `git commit --reset-author` provide "reset-author" and access with `parsed.kind.args.@"reset-author"`.
            name: [:0]const u8,
            count: Count = .one,
            help: [:0]const u8 = "",
            /// Arguments with default values are optional in the CLI and the default value is applied to the field before it is returned as part of `parsed.kind.args`.
            /// Optionals types (like ?i32) may only have default value null. This allows determining if a user provided argument or not. Example: `git branch dev/std.cli` has optional `?[]const u8` positional argument.
            default_value: ?T = null,
            short: ?u8 = null,
        },
    ) Argument {
        switch (options.count) {
            .one => {},
            .unlimited => {
                if (@typeInfo(T) != .pointer and @typeInfo(T).pointer.size != .slice) {
                    @compileError("Unlimited arguments must be a slice type.");
                }
            },
        }
        const default_value_ptr: ?*const anyopaque = switch (@typeInfo(T)) {
            .optional => if (options.default_value) |_| {
                @compileError("The only supported default value for optional types is null");
            } else &@as(T, null),
            else => if (options.default_value) |value| @ptrCast(@alignCast(&value)) else null,
        };

        return .{
            .field = .{
                .name = options.name,
                .type = T,
                .default_value_ptr = default_value_ptr,
                .alignment = null,
                .is_comptime = false,
            },
            .count = options.count,
            .help = options.help,
            .short = options.short,
        };
    }
};

/// Represents the result of CLI parsing.
///
/// When the user requests help, `parsed.kind == .help`, otherwise the named and positional arguments are accessible in `parsed.kind.args`.
/// Subcommands are accessible in `parsed.subcommand`.
pub fn Parsed(comptime command: Command) type {
    const ArgsStruct = blk: {
        const num_args = command.named_args.len + command.positional_args.len;
        var field_types: [num_args]type = undefined;
        var field_names: [num_args][]const u8 = undefined;
        var field_attrs: [num_args]std.builtin.Type.StructField.Attributes = undefined;
        inline for (&field_types, &field_names, &field_attrs, command.named_args ++ command.positional_args) |*field_type, *field_name, *field_attr, arg| {
            field_type.* = arg.field.type;
            field_name.* = arg.field.name;
            field_attr.* = .{
                .@"comptime" = arg.field.is_comptime,
                .@"align" = arg.field.alignment,
                .default_value_ptr = arg.field.default_value_ptr,
            };
        }
        break :blk @Struct(
            .auto,
            null,
            &field_names,
            &field_types,
            &field_attrs,
        );
    };

    const SubcommandTaggedUnion = blk: {
        var field_types: [command.subcommands.len]type = undefined;
        var field_names: [command.subcommands.len][]const u8 = undefined;
        inline for (&field_types, &field_names, command.subcommands) |*field_type, *field_name, subcommand| {
            field_type.* = Parsed(subcommand);
            field_name.* = subcommand.name;
        }
        const field_attrs: [command.subcommands.len]std.builtin.Type.UnionField.Attributes = @splat(.{});
        const bits = if (field_names.len != 0) std.math.log2_int_ceil(usize, field_names.len) else 0;
        const TagInt = @Int(.unsigned, bits);
        comptime var field_values: [field_names.len]TagInt = undefined;
        comptime for (0..field_names.len) |id| {
            field_values[id] = @intCast(id);
        };
        const E = @Enum(TagInt, .exhaustive, &field_names, &field_values);
        break :blk @Union(
            .auto,
            E,
            &field_names,
            &field_types,
            &field_attrs,
        );
    };

    return struct {
        kind: union(enum) {
            /// Help requested by user with `--help`.
            help,
            /// The named and positional arguments.
            /// Each argument is a field in this struct.
            args: ArgsStruct,
        },
        /// null when no subcommand provided.
        /// Each union field is a subcommand.
        subcommand: ?SubcommandTaggedUnion,
    };
}

pub const ParseError = error{
    /// Malformed input from the user.
    /// Example: `git commit --not-a-valid-option`.
    Usage,
    OutOfMemory,
};

pub const ParseOptions = struct {
    /// Call std.process.exit when there is a usage error.
    exit_usage_error: bool = false,
    /// Provide information about why a usage error occurred to stderr.
    /// Errors when writing to stderr are silently ignored.
    render_usage_errors: bool = false,
    /// Call std.process.exit when the user requests help with --help.
    exit_help: bool = false,
    /// Provide help information to stdout when the user requests help with --help.
    /// Errors when writing to stdout are silently ignored.
    render_help: bool = false,
};

/// Parse the operating-system provided arguments according to the grammer defined in command.
/// The lifetime of args must exceed the return value (return value may point to args).
pub fn parse(
    comptime command: Command,
    arena: std.mem.Allocator,
    /// See std.process.Args.toSlice
    /// Index 0 must be populated and will be skipped.
    args: []const [:0]const u8,
    options: ParseOptions,
) ParseError!Parsed(command) {
    var iter: Iterator = .init(args);
    _ = iter.next(); // consume argv index 0, which is this executable's path.

    const parsed = try parseRecursive(command, arena, &iter, options);

    if (options.render_help and helpWanted(parsed)) {
        var io_impl: std.Io.Threaded = .init_single_threaded;
        const io = io_impl.io();
        var buf: [1024]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(io, &buf);
        const writer: *std.Io.Writer = &stdout.interface;
        writer.writeAll(helpPage(command, parsed)) catch {};
        writer.flush() catch {};
    }
    if (options.exit_help and helpWanted(parsed)) {
        std.process.exit(1);
    }
    return parsed;
}

test parse {
    const command: Command = .{
        .name = "git",
        .help =
        \\A version control system.
        \\
        \\Options:
        \\  --log-level   One of err, warn, info, debug.
        \\
        \\Subcommands:
        \\  branch: create a branch
        \\  commit: commit changes to the repository
        ,
        .named_args = &.{
            .init(std.log.Level, .{ .name = "log-level", .default_value = .err }),
        },
        .subcommands = &.{
            .{
                .name = "branch",
                .positional_args = &.{
                    .init([]const u8, .{ .name = "branch_name" }),
                },
            },
            .{
                .name = "commit",
                .named_args = &.{
                    .init([]const u8, .{ .name = "message", .short = 'm' }),
                },
            },
        },
    };
    const parsed = try parse(
        command,
        std.testing.failing_allocator,
        &.{"git"},
        .{},
    );
    try std.testing.expect(parsed.kind.args.@"log-level" == .err);

    const parsed2 = try parse(
        command,
        std.testing.failing_allocator,
        &.{ "git", "--help" },
        .{},
    );
    try std.testing.expect(parsed2.kind == .help);
    try std.testing.expect(parsed2.subcommand == null);

    const parsed3 = try parse(
        command,
        std.testing.failing_allocator,
        &.{ "git", "--log-level=debug" },
        .{},
    );
    try std.testing.expectEqual(.debug, parsed3.kind.args.@"log-level");
    try std.testing.expect(parsed3.subcommand == null);

    const parsed4 = try parse(
        command,
        std.testing.failing_allocator,
        &.{ "git", "commit", "-m", "std.cli" },
        .{},
    );
    try std.testing.expect(parsed4.subcommand.? == .commit);
    try std.testing.expectEqualStrings("std.cli", parsed4.subcommand.?.commit.kind.args.message);

    const parsed5 = try parse(
        command,
        std.testing.failing_allocator,
        &.{ "git", "branch", "dev/std.cli" },
        .{},
    );
    try std.testing.expect(parsed5.subcommand.? == .branch);
    try std.testing.expectEqualStrings("dev/std.cli", parsed5.subcommand.?.branch.kind.args.branch_name);

    const parsed6 = parse(
        command,
        std.testing.failing_allocator,
        &.{ "git", "--not-an-option", "branch", "dev/std.cli" },
        .{},
    );
    try std.testing.expectError(error.Usage, parsed6);
}

fn validateCommand(comptime command: Command) void {
    // Multiple optional positionals makes parsing ambiguous.
    var last_optional_positional: ?[]const u8 = null;
    inline for (command.positional_args) |arg| {
        if (arg.field.defaultValue() != null) {
            if (last_optional_positional) |other_optional_positional_name| {
                @compileError("multiple optional positional arguments is prohibited. Offenders: " ++
                    other_optional_positional_name ++
                    " " ++
                    arg.field.name);
            }
            last_optional_positional = arg.field.name;
        }
    }

    // Multiple unimited positional args is ambiguous.
    var last_positional_unlimited: ?[]const u8 = null;
    inline for (command.positional_args) |arg| {
        if (arg.count == .unlimited) {
            if (last_positional_unlimited) |other_positional_unlimited_name| {
                @compileError("multiple unlimited positional arguments is prohibited. Offenders: " ++
                    other_positional_unlimited_name ++
                    ", " ++
                    arg.field.name);
            }
            last_positional_unlimited = arg.field.name;
        }
    }

    // require unique shorthand
    inline for (command.positional_args ++ command.named_args, 0..) |lhs_arg, i| {
        inline for (command.positional_args ++ command.named_args, 0..) |rhs_arg, j| {
            if (i == j) continue;
            if (lhs_arg.short != null and rhs_arg.short != null and lhs_arg.short.? == rhs_arg.short.?) {
                @compileError("Arguments with the same shorthand are prohibited. Offenders: " ++
                    "--" ++ lhs_arg.field.name ++ " (-" ++ [_]u8{lhs_arg.short.?} ++
                    "), " ++
                    "--" ++ rhs_arg.field.name ++ " (-" ++ [_]u8{rhs_arg.short.?} ++ ")");
            }
        }
    }
}

fn usageErrorExit(options: ParseOptions, comptime format: []const u8, args: anytype) error{Usage} {
    if (options.render_usage_errors) {
        std.log.err(format, args);
        std.log.err("Provide only --help for help.", .{});
    }
    if (options.exit_usage_error) std.process.exit(1);
    return error.Usage;
}

/// Returns the help page for the active command or subcommand.
pub fn helpPage(comptime command: Command, parsed: Parsed(command)) [:0]const u8 {
    if (parsed.subcommand) |subcommand| {
        switch (subcommand) {
            inline else => |value, tag| {
                inline for (command.subcommands) |subcommand_config| {
                    if (comptime std.mem.eql(u8, subcommand_config.name, @tagName(tag))) {
                        return helpPage(subcommand_config, value);
                    }
                }
            },
        }
        unreachable;
    } else return command.help;
}

/// True when no usage error and `--help` was provided as part of the arguments
pub fn helpWanted(parsed: anytype) bool {
    switch (parsed.kind) {
        .help => return true,
        .args => {},
    }
    if (parsed.subcommand) |subcommand| {
        switch (subcommand) {
            inline else => |value| return helpWanted(value),
        }
    }
    return false;
}

const Iterator = struct {
    args: []const [:0]const u8,
    idx: usize,
    fn init(args: []const [:0]const u8) Iterator {
        return .{ .args = args, .idx = 0 };
    }
    fn next(self: *Iterator) ?[:0]const u8 {
        if (self.idx == self.args.len) return null;
        defer self.idx += 1;
        return self.args[self.idx];
    }
};

/// Generates a struct with fields of type ArrayList(T) for each unlimited argument.
/// During parsing, instances of unlimited arguments are accumulated in the corresponding
/// arraylist.
fn UnlimitedArgStruct(comptime command: Command) type {
    var num_unlimited: usize = 0;
    for (command.named_args ++ command.positional_args) |arg| {
        switch (arg.count) {
            .unlimited => num_unlimited += 1,
            .one => {},
        }
    }

    var field_types: [num_unlimited]type = undefined;
    var field_names: [num_unlimited][]const u8 = undefined;
    var field_attrs: [num_unlimited]std.builtin.Type.StructField.Attributes = undefined;

    var num_populated: usize = 0;
    inline for (command.named_args ++ command.positional_args) |arg| {
        switch (arg.count) {
            .unlimited => {
                field_types[num_populated] = std.ArrayList(std.meta.Child(arg.field.type));
                field_names[num_populated] = arg.field.name;
                field_attrs[num_populated] = .{ .default_value_ptr = &std.ArrayList(std.meta.Child(arg.field.type)).empty };
                num_populated += 1;
            },
            .one => continue,
        }
    }
    comptime assert(num_populated == num_unlimited);

    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}

const Defined = enum { defined, undefined };

/// Generates a struct with fields of type Defined for each argument.
/// Used during parsing to track which arguments have been provided by the user
/// and enforce that required arguments are provided.
fn DefinedArgStruct(comptime command: Command) type {
    const num_args = command.named_args.len + command.positional_args.len;
    var field_types: [num_args]type = @splat(Defined);
    var field_names: [num_args][]const u8 = undefined;
    var field_attrs: [num_args]std.builtin.Type.StructField.Attributes = @splat(.{ .default_value_ptr = &Defined.undefined });
    inline for (command.named_args ++ command.positional_args, &field_names) |arg, *field_name| {
        field_name.* = arg.field.name;
    }
    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}

fn parseRecursive(
    comptime command: Command,
    arena: std.mem.Allocator,
    iter: *Iterator,
    options: ParseOptions,
) ParseError!Parsed(command) {
    comptime validateCommand(command);

    // parsing will fill the resulting args one field at a time
    var result_args: @FieldType(@FieldType(Parsed(command), "kind"), "args") = undefined;
    // as we fill the args, track what we have defined so undefined is not leaked to return value
    var defined: DefinedArgStruct(command) = .{};
    var result_subcommand: @FieldType(Parsed(command), "subcommand") = null;
    var unlimited_args: UnlimitedArgStruct(command) = .{};

    // args with default values are not required so they are filled in here first.
    // If found during parsing later, the default values are overwritten with the user-provided values.
    inline for (command.named_args ++ command.positional_args) |arg| {
        @field(result_args, arg.field.name) = arg.field.defaultValue() orelse continue;
        @field(defined, arg.field.name) = .defined;
    }

    var began_positional: bool = false;
    next_os_arg: while (iter.next()) |os_arg| {
        if (!began_positional) {
            // encountering a lone "--" sigil means the rest of the args are positional
            if (std.mem.eql(u8, "--", os_arg)) {
                began_positional = true;
                continue :next_os_arg;
            }

            if (std.mem.eql(u8, "--help", os_arg)) {
                return .{ .kind = .help, .subcommand = result_subcommand };
            }

            inline for (command.named_args) |arg| {
                const Value = switch (arg.count) {
                    .one => arg.field.type,
                    .unlimited => std.meta.Child(arg.field.type),
                };
                var value: union(enum) { found: Value, not_found } = .not_found;

                if (@typeInfo(Value) == .bool) {
                    if (std.mem.eql(u8, os_arg, "--" ++ arg.field.name)) {
                        value = .{ .found = true };
                    } else if (std.mem.eql(u8, os_arg, "--no-" ++ arg.field.name)) {
                        value = .{ .found = false };
                    } else if (arg.short != null and std.mem.eql(u8, os_arg, "-" ++ [_]u8{arg.short.?})) {
                        value = .{ .found = true };
                    } else if (cutPrefixSentinel(u8, 0, os_arg, "--" ++ arg.field.name ++ "=")) |suffix| {
                        value = .{ .found = try parseValue(options, Value, suffix) };
                    } else {
                        value = .not_found;
                    }
                } else {
                    if (std.mem.eql(u8, os_arg, "--" ++ arg.field.name)) {
                        value = .{
                            .found = try parseValue(options, Value, iter.next() orelse return usageErrorExit(
                                options,
                                "Missing argument for option: {s}",
                                .{"--" ++ arg.field.name},
                            )),
                        };
                    } else if (cutPrefixSentinel(u8, 0, os_arg, "--" ++ arg.field.name ++ "=")) |suffix| {
                        value = .{ .found = try parseValue(options, Value, suffix) };
                    } else if (arg.short != null and std.mem.eql(u8, os_arg, "-" ++ [_]u8{arg.short.?})) {
                        value = .{ .found = try parseValue(options, Value, iter.next() orelse return usageErrorExit(
                            options,
                            "Missing argument for option: {s}",
                            .{"-" ++ [_]u8{arg.short.?}},
                        )) };
                    } else if (arg.short != null) {
                        if (cutPrefixSentinel(u8, 0, os_arg, "-" ++ [_]u8{arg.short.?} ++ "=")) |suffix| {
                            value = .{ .found = try parseValue(options, Value, suffix) };
                        }
                    }
                }
                switch (value) {
                    .found => |found_value| {
                        switch (arg.count) {
                            .one => @field(result_args, arg.field.name) = found_value,
                            .unlimited => try @field(unlimited_args, arg.field.name).append(arena, found_value),
                        }
                        @field(defined, arg.field.name) = .defined;
                        continue :next_os_arg;
                    },
                    .not_found => {},
                }
            }

            inline for (command.subcommands) |subcommand| {
                if (std.mem.eql(u8, os_arg, subcommand.name)) {
                    const U = std.meta.Child(@TypeOf(result_subcommand));
                    result_subcommand = @unionInit(U, subcommand.name, try parseRecursive(subcommand, arena, iter, options));
                    continue :next_os_arg;
                }
            }
            // "-" is sometimes used as a positional argument to signify stdin, so it is allowed.
            // Otherwise the user is required to explicitly begin positional with sigil "--" if they want
            // to have a positional argument that begins with "-".
            if (std.mem.startsWith(u8, os_arg, "-") and !std.mem.eql(u8, os_arg, "-")) {
                return usageErrorExit(options, "unexpected argument: {s}", .{os_arg});
            }
        }
        began_positional = true;
        inline for (command.positional_args) |arg| {
            skip: switch (arg.count) {
                .one => {
                    if (@field(defined, arg.field.name) == .defined) break :skip;
                    const value = try parseValue(options, arg.field.type, os_arg);
                    @field(result_args, arg.field.name) = value;
                    @field(defined, arg.field.name) = .defined;
                    continue :next_os_arg;
                },
                .unlimited => {
                    const value = try parseValue(options, std.meta.Child(arg.field.type), os_arg);
                    try @field(unlimited_args, arg.field.name).append(arena, value);
                    @field(defined, arg.field.name) = .defined;
                    continue :next_os_arg;
                },
            }
        }

        return usageErrorExit(options, "unexpected argument: {s}", .{os_arg});
    }

    inline for (comptime std.meta.fieldNames(@TypeOf(defined))) |arg_name| {
        switch (@field(defined, arg_name)) {
            .defined => {},
            .undefined => {
                inline for (command.named_args) |arg| {
                    if (comptime std.mem.eql(u8, arg.field.name, arg_name)) {
                        return usageErrorExit(options, "missing required named argument: {s}", .{"--" ++ arg.field.name});
                    }
                }
                inline for (command.positional_args) |arg| {
                    if (comptime std.mem.eql(u8, arg.field.name, arg_name)) {
                        return usageErrorExit(options, "missing required positional argument: {s}", .{arg.field.name});
                    }
                }
                comptime unreachable;
            },
        }
    }

    inline for (comptime std.meta.fieldNames(@TypeOf(unlimited_args))) |field_name| {
        if (@field(unlimited_args, field_name).items.len > 0) {
            @field(result_args, field_name) = try @field(unlimited_args, field_name).toOwnedSlice(arena);
        }
    }

    inline for (comptime std.meta.fieldNames(@TypeOf(defined))) |arg_name| {
        assert(@field(defined, arg_name) == .defined);
    }

    return .{
        .kind = .{ .args = result_args },
        .subcommand = result_subcommand,
    };
}

fn parseValue(options: ParseOptions, comptime T: type, buf: [:0]const u8) error{Usage}!T {
    switch (@typeInfo(T)) {
        .bool => {
            if (std.mem.eql(u8, "true", buf)) return true;
            if (std.mem.eql(u8, "false", buf)) return false;
            if (std.mem.eql(u8, "1", buf)) return true;
            if (std.mem.eql(u8, "0", buf)) return false;
            if (std.mem.eql(u8, "yes", buf)) return true;
            if (std.mem.eql(u8, "no", buf)) return false;
            if (std.mem.eql(u8, "y", buf)) return true;
            if (std.mem.eql(u8, "n", buf)) return false;
            return usageErrorExit(
                options,
                "Invalid input for argument of type bool: {s}",
                .{buf},
            );
        },
        .int => return std.fmt.parseInt(T, buf, 0) catch return usageErrorExit(
            options,
            "Invalid input for argument of type {s}: {s}",
            .{ @typeName(T), buf },
        ),
        .float => return std.fmt.parseFloat(T, buf) catch return usageErrorExit(
            options,
            "Invalid input for argument of type {s}: {s}",
            .{ @typeName(T), buf },
        ),
        .pointer => |pointer| {
            switch (pointer.size) {
                .slice, .c, .many => {
                    if (pointer.child == u8) {
                        return buf;
                    } else comptime unreachable; // unsupported type for cli argument value parsing
                },
                else => comptime unreachable, // unsupported type for cli argument value parsing
            }
        },
        .@"enum" => return std.meta.stringToEnum(T, buf) orelse return usageErrorExit(
            options,
            "Invalid input for argument of type {s}: {s}",
            .{ @typeName(T), buf },
        ),
        .optional => |info| return try parseValue(options, info.child, buf),
        else => comptime unreachable, // unsupported type for cli argument value parsing
    }
}

test {
    _ = @import("cli/test.zig");
}
