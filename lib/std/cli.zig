/// Command-line argument parser
const cli = @This();

const std = @import("std.zig");
const assert = std.debug.assert;
const cutPrefixSentinel = std.mem.cutPrefixSentinel;

pub const Argument = struct {
    field: std.builtin.Type.StructField,
    count: Count,
    help: [:0]const u8,
    short: ?u8,

    pub const Count = enum { one, unlimited };

    /// For `.count = .unlimited` arguments, the provided `T` must be a slice.
    pub fn init(
        comptime T: type,
        comptime options: struct {
            name: [:0]const u8,
            count: Count = .one,
            help: [:0]const u8 = "",
            default_value: ?T = null,
            short: ?u8 = null,
        },
    ) Argument {
        switch (options.count) {
            .one => {},
            .unlimited => {
                if (@typeInfo(T) != .pointer and @typeInfo(T).pointer.size != .slice) {
                    @compileError("unlimited arguments must be a slice.");
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

pub const Command = struct {
    /// If this is the root command, this is the name of the executable shows in the help text.
    ///
    /// Example: "git"
    name: [:0]const u8,
    named_args: []const Argument = &.{},
    positional_args: []const Argument = &.{},
    subcommands: []const Command = &.{},
    help: [:0]const u8 = "",
    prologue: [:0]const u8 = "",
    epilogue: [:0]const u8 = "",
};

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
            &field_names ++ [1][]const u8{"help"},
            &field_types ++ [1]type{bool},
            &field_attrs ++ [1]std.builtin.Type.StructField.Attributes{.{ .default_value_ptr = &false }},
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
        /// The named and positional arguments.
        /// Each argument is a field in this struct.
        args: ArgsStruct,
        /// null when no subcommand provided.
        /// Each union field is a subcommand.
        subcommand: ?SubcommandTaggedUnion,
    };
}

/// Lifetime of args must exceed the return value (return value may point to args).
pub fn parseExit(
    comptime command: Command,
    arena: std.mem.Allocator,
    /// See std.process.Args.toSlice
    /// Index 0 must be populated and will be skipped.
    args: []const [:0]const u8,
) noreturn!Parsed(command) {
    var iter: Iterator = .init(args);
    _ = iter.next(); // consume argv index 0, which is this executable's path.

    const result = parseRecursive(command, arena, &iter, .{
        .exit = true,
        .render_errors = true,
        .render_help = true,
    });

    if (result) |parsed| {
        if (helpWanted(parsed)) {
            var io_impl: std.Io.Threaded = .init_single_threaded;
            var buf: [1024]u8 = undefined;
            var stdout: std.Io.File.Writer = .init(.stdout(), io_impl.io(), &buf);
            const writer: *std.Io.Writer = &stdout.interface;
            printHelp(command, parsed, writer) catch std.process.exit(1);
            std.process.exit(1);
        } else return parsed;
    } else |err| switch (err) {
        error.Usage => unreachable,
        error.OutOfMemory => {
            std.log.err("out of memory");
            std.process.exit(1);
        },
    }
}

pub const ParseError = error{
    /// Malformed input from the user.
    Usage,
    OutOfMemory,
};

pub const ParseOptions = struct {
    /// Call std.process.exit when there is a usage error.
    exit_on_usage_error: bool = false,
    /// Provide information about why a usage error occurred to stderr.
    render_usage_errors: bool = false,
    /// Call std.process.exit when the user requests help with --help.
    exit_on_help: bool = false,
    /// Provide help information to stdout when the user requests help with --help.
    render_help: bool = false,
};

/// Lifetime of args must exceed the return value (return value may point to args).
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

    const result = parseRecursive(command, arena, &iter, options);

    if (result) |parsed| {
        if (options.render_help and helpWanted(parsed)) {
            var io_impl: std.Io.Threaded = .init_single_threaded;
            var buf: [1024]u8 = undefined;
            var stdout: std.Io.File.Writer = .init(.stdout(), io_impl.io(), &buf);
            const writer: *std.Io.Writer = &stdout.interface;
            printHelp(command, parsed, writer) catch std.process.exit(1);
        }
        if (options.exit_on_help and helpWanted(parsed)) {
            std.process.exit(1);
        }
        return parsed;
    } else |err| return err;
}

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
        std.log.err("Add --help for help.", .{});
    }
    if (options.exit_on_usage_error) std.process.exit(1);
    return error.Usage;
}

/// Prints help for the active command.
pub fn printHelp(comptime command: Command, parsed: Parsed(command), out: *std.Io.Writer) !void {
    const command_help = descendToHelpPage("", command, parsed);
    try out.writeAll("\n");
    try out.writeAll(command_help);
    try out.flush();
}

fn descendToHelpPage(comptime descent_path: []const u8, comptime command: Command, parsed: Parsed(command)) [:0]const u8 {
    const this_descent = if (comptime std.mem.eql(u8, descent_path, "")) command.name else descent_path ++ " " ++ command.name;
    if (parsed.subcommand) |subcommand| {
        switch (subcommand) {
            inline else => |value, tag| {
                inline for (command.subcommands) |subcommand_config| {
                    if (std.mem.eql(u8, subcommand_config.name, @tagName(tag))) {
                        return descendToHelpPage(this_descent, subcommand_config, value);
                    }
                }
            },
        }
        unreachable;
    } else return comptime helpPage(this_descent, command);
}

inline fn helpPage(comptime descent_path: []const u8, comptime command: Command) [:0]const u8 {
    var content: [:0]const u8 = std.fmt.comptimePrint("Usage: {s} ...\n\n", .{descent_path});

    if (command.prologue.len > 0) {
        content = content ++ "\n" ++ command.prologue ++ "\n";
    }

    if (command.positional_args.len > 0) {
        content = content ++ "\nPositional Arguments:\n";
        inline for (command.positional_args) |arg| {
            content = content ++ "  " ++ arg.field.name ++ ": " ++ arg.help ++ "\n";
        }
    }
    if (command.named_args.len > 0) {
        content = content ++ "\nNamed Arguments:\n";
        inline for (command.named_args) |arg| {
            content = content ++ "  --" ++ arg.field.name ++ ": " ++ arg.help ++ "\n";
        }
    }

    if (command.subcommands.len > 0) {
        content = content ++ "\nSubcommands:\n";
        inline for (command.subcommands) |subcommand| {
            content = content ++ "  " ++ subcommand.name ++ ": " ++ subcommand.help ++ "\n";
        }
    }

    if (command.epilogue.len > 0) {
        content = content ++ "\n" ++ command.epilogue ++ "\n";
    }

    return content;
}

pub fn helpWanted(parsed: anytype) bool {
    if (parsed.args.help) {
        return true;
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

fn parseRecursive(
    comptime command: Command,
    arena: std.mem.Allocator,
    iter: *Iterator,
    options: ParseOptions,
) ParseError!Parsed(command) {
    comptime validateCommand(command);

    // parsing will fill the resulting args one field at a time
    var result_args: @FieldType(Parsed(command), "args") = undefined;
    // as we fill the args, track what we have defined so undefined is not leaked to return value
    const Defined = enum { defined, undefined };
    var fields_defined: [command.named_args.len + command.positional_args.len]Defined = @splat(.undefined);
    var result_subcommand: @FieldType(Parsed(command), "subcommand") = null;

    var unlimited_args: UnlimitedArgStruct(command) = .{};

    // args with default values are not required so they are filled in here first.
    // If found during parsing later, the default values are overwritten with the user-provided values.
    inline for (command.named_args ++ command.positional_args, 0..) |arg, i| {
        @field(result_args, arg.field.name) = arg.field.defaultValue() orelse continue;
        fields_defined[i] = .defined;
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
                @field(result_args, "help") = true;
                continue :next_os_arg;
            }

            inline for (command.named_args, 0..) |arg, i| {
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
                        fields_defined[i] = .defined;
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
        }
        began_positional = true;
        inline for (command.positional_args, 0..) |arg, i| {
            skip: switch (arg.count) {
                .one => {
                    if (fields_defined[i] == .defined) break :skip;
                    const value = try parseValue(options, arg.field.type, os_arg);
                    @field(result_args, arg.field.name) = value;
                    fields_defined[i] = .defined;
                    continue :next_os_arg;
                },
                .unlimited => {
                    const value = try parseValue(options, std.meta.Child(arg.field.type), os_arg);
                    try @field(unlimited_args, arg.field.name).append(arena, value);
                    fields_defined[i] = .defined;
                    continue :next_os_arg;
                },
            }
        }

        return usageErrorExit(options, "unexpected argument: {s}", .{os_arg});
    }

    inline for (fields_defined[0..command.named_args.len], command.named_args) |defined, arg| {
        switch (defined) {
            .undefined => {
                return usageErrorExit(options, "missing required named argument: {s}", .{"--" ++ arg.field.name});
            },
            .defined => {},
        }
    }

    inline for (fields_defined[command.named_args.len..], command.positional_args) |defined, arg| {
        switch (defined) {
            .undefined => {
                return usageErrorExit(options, "missing required positional argument: {s}", .{arg.field.name});
            },
            .defined => {},
        }
    }

    inline for (comptime std.meta.fieldNames(@TypeOf(unlimited_args))) |field_name| {
        if (@field(unlimited_args, field_name).items.len > 0) {
            @field(result_args, field_name) = try @field(unlimited_args, field_name).toOwnedSlice(arena);
        }
    }

    assert(std.mem.allEqual(Defined, &fields_defined, .defined));
    return .{
        .args = result_args,
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
                    }
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
