const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const ArgsTokenizer = @This();

args: []const []const u8,
outer_pos: usize,
inner_pos: usize,

/// When `true`, all tokens will be unconditionally interpreted as positional arguments.
/// Setting this to `true` when the most recently consumed token was a short no-argument option
/// may cause Illegal Behavior.
positional_only: bool,

pub fn init(args: []const []const u8) ArgsTokenizer {
    return .{
        .args = args,
        .outer_pos = 0,
        .inner_pos = 0,
        .positional_only = false,
    };
}

/// Reads the next token, consuming it and advancing the tokenizer's position.
pub fn next(
    t: *ArgsTokenizer,
    /// A tagged union that defines the set of recognized options.
    /// Field names must be in the form `@"-f"` or `@"--foo"`.
    /// Field types must be `void`, `[]const u8` or `?[]const u8`, designating each option
    /// as no-argument, required-argument or optional-argument respectively.
    comptime Option: type,
) ?Token(Option) {
    const result = t.peek(Option) orelse return null;
    t.outer_pos = result.next_outer_pos;
    t.inner_pos = result.next_inner_pos;
    t.positional_only = t.positional_only or result.token == .end_of_options;
    return result.token;
}

/// Like `next`, but the set of recognized options does not need to be statically known.
/// Reads the next token, consuming it and advancing the tokenizer's position.
/// Asserts that the lengths of `option_names` and `option_arities` are equal.
pub fn nextDynamic(
    t: *ArgsTokenizer,
    /// Option names in the form `"-f"` or `"--foo"`.
    option_names: []const []const u8,
    /// Designates each option as no-argument, required-argument or optional-argument.
    option_arities: []const OptionArity,
) ?DynamicToken {
    const result = t.peekDynamic(option_names, option_arities) orelse return null;
    t.outer_pos = result.next_outer_pos;
    t.inner_pos = result.next_inner_pos;
    t.positional_only = t.positional_only or result.token == .end_of_options;
    return result.token;
}

/// Returns the next token without consuming it or modifying the tokenizer's state.
pub fn peek(
    t: *const ArgsTokenizer,
    /// A tagged union that defines the set of recognized options.
    /// Field names must be in the form `@"-f"` or `@"--foo"`.
    /// Field types must be `void`, `[]const u8` or `?[]const u8`, designating each option
    /// as no-argument, required-argument or optional-argument respectively.
    comptime Option: type,
) ?Token(Option).PeekResult {
    const option_count = @typeInfo(Option).@"union".fields.len;
    const option_names: [option_count][]const u8, //
    const option_arities: [option_count]OptionArity //
    = comptime names_and_arities: {
        var names: [option_count][]const u8 = undefined;
        var arities: [option_count]OptionArity = undefined;
        for (&names, &arities, @typeInfo(Option).@"union".fields) |*name, *arity, field| {
            if (!isValidOptionName(field.name)) {
                @compileError("expected short or long option name in the form '-f' or '--foo', found invalid option name '" ++ field.name ++ "'");
            }
            name.* = field.name;
            arity.* = switch (@typeInfo(field.type)) {
                .void => .no_arg,
                .optional => .optional_arg,
                else => .required_arg,
            };
        }
        break :names_and_arities .{ names, arities };
    };
    const dynamic_result = t.peekDynamic(&option_names, &option_arities) orelse return null;
    return .{
        .token = switch (dynamic_result.token) {
            .option => |option| if (option_count != 0) .{
                .option = switch (option.index) {
                    inline 0...(option_count - 1) => |i| @unionInit(Option, option_names[i], switch (option_arities[i]) {
                        .no_arg => {},
                        .required_arg => option.arg.?,
                        .optional_arg => option.arg,
                    }),
                    else => unreachable,
                },
            } else unreachable,
            .end_of_options => .end_of_options,
            .positional => |arg| .{ .positional = arg },
            .invalid_option => |invalid| .{
                .invalid_option = .{
                    .err = invalid.err,
                    .name = invalid.name,
                    .tag = if (option_count != 0 and invalid.index != null) switch (invalid.index.?) {
                        inline 0...(option_count - 1) => |i| @field(Option, option_names[i]),
                        else => unreachable,
                    } else null,
                    .arg = invalid.arg,
                },
            },
        },
        .next_outer_pos = dynamic_result.next_outer_pos,
        .next_inner_pos = dynamic_result.next_inner_pos,
    };
}

/// Like `peek`, but the set of recognized options does not need to be statically known.
/// Returns the next token without consuming it or modifying the tokenizer's state.
/// Asserts that the lengths of `option_names` and `option_arities` are equal.
pub fn peekDynamic(
    t: *const ArgsTokenizer,
    /// Option names in the form `"-f"` or `"--foo"`.
    option_names: []const []const u8,
    /// Designates each option as no-argument, required-argument or optional-argument.
    option_arities: []const OptionArity,
) ?DynamicToken.PeekResult {
    if (t.positional_only) {
        const arg = t.peekPositional() orelse return null;
        return .{
            .token = .{ .positional = arg },
            .next_outer_pos = t.outer_pos + 1,
            .next_inner_pos = 0,
        };
    }

    const args = t.args;
    var outer = t.outer_pos;
    var inner = t.inner_pos;
    const actual_option_name: InvalidOptionName = option_name: {
        if (inner != 0) {
            if (inner != args[outer].len) {
                // '-xf' (stacked)
                defer inner += 1;
                break :option_name .{ .short = .{ '-', args[outer][inner] } };
            }
            outer += 1;
            inner = 0;
        }
        if (outer == args.len) {
            // EOF
            return null;
        }
        if (args[outer].len < 2 or args[outer][0] != '-' or std.ascii.isDigit(args[outer][1])) {
            // Positional argument
            return .{
                .token = .{ .positional = args[outer] },
                .next_outer_pos = outer + 1,
                .next_inner_pos = 0,
            };
        }
        if (args[outer][1] != '-') {
            // '-f'
            inner = 2;
            break :option_name .{ .short = args[outer][0..2].* };
        }
        if (args[outer].len == 2) {
            // '--'
            return .{
                .token = .end_of_options,
                .next_outer_pos = outer + 1,
                .next_inner_pos = 0,
            };
        }
        if (std.mem.findScalarPos(u8, args[outer], 2, '=')) |eq| {
            // '--foo=bar'
            inner = eq + 1;
            break :option_name .{ .long = args[outer][0..eq] };
        }
        // '--foo'
        defer outer += 1;
        break :option_name .{ .long = args[outer] };
    };

    const arity: OptionArity, //
    const index: ?usize //
    = for (option_names, option_arities, 0..) |recognized_name, arity, i| {
        if (std.mem.eql(u8, recognized_name, actual_option_name.slice())) {
            break .{ arity, i };
        }
    } else .{ .optional_arg, null };

    const arg: ?[]const u8 = arg: {
        switch (actual_option_name) {
            .short => {
                if (inner != args[outer].len) {
                    if (arity == .no_arg) {
                        // '-fx' (stacked)
                        break :arg null;
                    }
                    // '-fbar'
                } else {
                    if (arity != .no_arg) {
                        outer += 1;
                        inner = 0;
                    }
                    if (arity != .required_arg or outer == args.len) {
                        // '-f'
                        break :arg null;
                    }
                    // '-f bar'
                }
            },
            .long => {
                if (inner == 0 and (arity != .required_arg or outer == args.len)) {
                    // '--foo'
                    break :arg null;
                }
                // '--foo=bar' or '--foo bar'
            },
        }
        defer {
            outer += 1;
            inner = 0;
        }
        break :arg args[outer][inner..];
    };

    const err: InvalidOptionError =
        if (index == null)
            error.UnrecognizedOption
        else if (arity == .required_arg and arg == null)
            error.MissingOptionArg
        else if (arity == .no_arg and arg != null)
            error.UnexpectedOptionArg
        else {
            return .{
                .token = .{ .option = .{ .index = index.?, .arg = arg } },
                .next_outer_pos = outer,
                .next_inner_pos = inner,
            };
        };

    return .{
        .token = .{ .invalid_option = .{
            .err = err,
            .name = actual_option_name,
            .index = index,
            .arg = arg,
        } },
        .next_outer_pos = outer,
        .next_inner_pos = inner,
    };
}

/// Reads the next token interpreted as a positional argument,
/// consuming it and advancing the tokenizer's position.
/// Asserts that the most recently consumed token was not a short no-argument option.
pub fn nextPositional(t: *ArgsTokenizer) ?[]const u8 {
    const arg = t.peekPositional() orelse return null;
    t.outer_pos += 1;
    return arg;
}

/// Returns the next token interpreted it as a positional argument,
/// without consuming it or modifying the tokenizer's state.
/// Asserts that the most recently consumed token was not a short no-argument option.
pub fn peekPositional(t: *const ArgsTokenizer) ?[]const u8 {
    assert(t.inner_pos == 0);
    if (t.outer_pos == t.args.len) return null;
    return t.args[t.outer_pos];
}

/// Returns a slice of the remaining tokens interpreted as positional arguments,
/// without consuming them or modifying the tokenizer's state.
/// Asserts that the most recently consumed token was not a short no-argument option.
pub fn restPositional(t: *const ArgsTokenizer) []const []const u8 {
    assert(t.inner_pos == 0);
    return t.args[t.outer_pos..];
}

pub const OptionArity = enum {
    no_arg,
    required_arg,
    optional_arg,
};

pub fn Token(comptime Option: type) type {
    return union(enum) {
        option: Option,
        /// The `--` end-of-options delimiter.
        end_of_options: void,
        positional: []const u8,
        invalid_option: InvalidOption,

        pub const OptionTag = @typeInfo(Option).@"union".tag_type.?;

        pub const InvalidOption = struct {
            err: InvalidOptionError,
            name: InvalidOptionName,
            tag: ?OptionTag,
            arg: ?[]const u8,
        };

        /// In addition to the token, also includes positioning information for the tokenizer.
        pub const PeekResult = struct {
            token: Token(Option),
            next_outer_pos: usize,
            next_inner_pos: usize,
        };
    };
}

pub const DynamicToken = union(enum) {
    option: Option,
    /// The `--` end-of-options delimiter.
    end_of_options: void,
    positional: []const u8,
    invalid_option: InvalidOption,

    pub const Option = struct {
        /// Index into `option_names`/`option_arities`.
        index: usize,
        arg: ?[]const u8,
    };

    pub const InvalidOption = struct {
        err: InvalidOptionError,
        name: InvalidOptionName,
        /// Index into `option_names`/`option_arities`.
        index: ?usize,
        arg: ?[]const u8,
    };

    /// In addition to the token, also includes positioning information for the tokenizer.
    pub const PeekResult = struct {
        token: DynamicToken,
        next_outer_pos: usize,
        next_inner_pos: usize,
    };
};

pub const InvalidOptionError = error{
    UnrecognizedOption,
    MissingOptionArg,
    UnexpectedOptionArg,
};

pub const InvalidOptionName = union(enum) {
    short: [2]u8,
    long: []const u8,

    pub fn slice(name: *const InvalidOptionName) []const u8 {
        return switch (name.*) {
            .short => &name.short,
            .long => name.long,
        };
    }
};

test ArgsTokenizer {
    const Option = union(enum) {
        @"--amend": void,
        @"-m": []const u8,
        @"--message": []const u8,
    };
    var amend: bool = false;
    var message: ?[]const u8 = null;

    var positionals: std.ArrayList([]const u8) = .empty;
    defer positionals.deinit(std.testing.allocator);

    const args: []const []const u8 = &.{ "git", "commit", "--amend", "-mFix bugs" };
    var tokenizer: std.cli.ArgsTokenizer = .init(args);

    const program_name = tokenizer.nextPositional();
    while (tokenizer.next(Option)) |token| switch (token) {
        .option => |option| switch (option) {
            .@"--amend" => {
                amend = true;
            },
            .@"-m", .@"--message" => |arg| {
                message = arg;
            },
        },
        .end_of_options => {},
        .positional => |arg| {
            try positionals.append(std.testing.allocator, arg);
        },
        .invalid_option => |invalid| {
            return invalid.err;
        },
    };

    try std.testing.expectEqualStrings("git", program_name orelse "");
    try std.testing.expectEqual(1, positionals.items.len);
    try std.testing.expectEqualStrings("commit", positionals.items[0]);
    try std.testing.expectEqual(true, amend);
    try std.testing.expectEqualStrings("Fix bugs", message orelse "");
}

/// Note that the parameters order is the opposite of most `std.testing` functions!
fn expectToken(comptime Option: type, actual: ?Token(Option), expected: ?Token(Option)) !void {
    try testing.expectEqualDeep(expected, actual);
}

/// Note that the parameters order is the opposite of most `std.testing` functions!
fn expectDynamicToken(actual: ?DynamicToken, expected: ?DynamicToken) !void {
    try testing.expectEqualDeep(expected, actual);
}

fn initInvalidOption(
    comptime Option: type,
    err: InvalidOptionError,
    name: []const u8,
    tag: ?@typeInfo(Option).@"union".tag_type.?,
    arg: ?[]const u8,
) Token(Option) {
    return .{ .invalid_option = .{
        .err = err,
        .name = if (name.len == 2) .{ .short = name[0..2].* } else .{ .long = name },
        .tag = tag,
        .arg = arg,
    } };
}

fn initDynamicInvalidOption(
    err: InvalidOptionError,
    name: []const u8,
    index: ?usize,
    arg: ?[]const u8,
) DynamicToken {
    return .{ .invalid_option = .{
        .err = err,
        .name = if (name.len == 2) .{ .short = name[0..2].* } else .{ .long = name },
        .index = index,
        .arg = arg,
    } };
}

const TestOption = union(enum) {
    @"-n": void,
    @"--no": void,
    @"-r": []const u8,
    @"--required": []const u8,
    @"-o": ?[]const u8,
    @"--optional": ?[]const u8,
};

test "separate short options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-n", "-n", "-r", "-r", "-o", "-o" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "-r" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), null);
}

test "stacked short options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-nn", "-n", "-nr", "-r", "-no", "-o", "-rr", "-r", "-ro", "-o", "-oo", "-o" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "-r" } });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "r" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "-ro" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = "o" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = null } });
    try expectToken(O, t.next(O), null);
}

test "unrecognized short options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-x", "-xxx", "-nx", "-nxxx" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-x", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-x", null, "xx"));
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-x", null, null));
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-x", null, "xx"));
    try expectToken(O, t.next(O), null);
}

test "short options do not use equals signs" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-r=22", "-o=33", "-n=11" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "=22" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-o" = "=33" } });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-=", null, "11"));
    try expectToken(O, t.next(O), null);
}

test "negative numbers are classified as positionals" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-1", "-876", "-0nro" });
    try expectToken(O, t.next(O), .{ .positional = "-1" });
    try expectToken(O, t.next(O), .{ .positional = "-876" });
    try expectToken(O, t.next(O), .{ .positional = "-0nro" });
    try expectToken(O, t.next(O), null);
}

test "separate long options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "--no", "--no", "--required", "--required", "--optional", "--optional" });
    try expectToken(O, t.next(O), .{ .option = .@"--no" });
    try expectToken(O, t.next(O), .{ .option = .@"--no" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "--required" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = null } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = null } });
    try expectToken(O, t.next(O), null);
}

test "equals signed long options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "--no=123", "--no=--no", "--required=123", "--required=--no", "--optional=123", "--optional=--no" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnexpectedOptionArg, "--no", .@"--no", "123"));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnexpectedOptionArg, "--no", .@"--no", "--no"));
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "123" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "--no" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = "123" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = "--no" } });
    try expectToken(O, t.next(O), null);
}

test "unrecognized long options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "--xyz", "--xyz=abc" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--xyz", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--xyz", null, "abc"));
    try expectToken(O, t.next(O), null);
}

test "long options cannot be stacked" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "--non", "--nono", "--no--no", "--requiredn", "--requiredno", "--required--no", "--optionaln", "--optionalno", "--optional--no" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--non", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--nono", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--no--no", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--requiredn", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--requiredno", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--required--no", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--optionaln", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--optionalno", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--optional--no", null, null));
    try expectToken(O, t.next(O), null);
}

test "long options cannot be abbreviated" {
    const O = union(enum) { @"--unambiguous", @"--unabbreviated" };
    var t: ArgsTokenizer = .init(&.{ "--un", "--unabbr" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--un", null, null));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--unabbr", null, null));
    try expectToken(O, t.next(O), null);
}

test "long option names containing digits and hyphens" {
    const O = union(enum) { @"--1", @"--765", @"--sk8er-boi" };
    var t: ArgsTokenizer = .init(&.{ "--1", "--765", "--sk8er-boi" });
    try expectToken(O, t.next(O), .{ .option = .@"--1" });
    try expectToken(O, t.next(O), .{ .option = .@"--765" });
    try expectToken(O, t.next(O), .{ .option = .@"--sk8er-boi" });
    try expectToken(O, t.next(O), null);
}

test "esoteric option names" {
    const O = union(enum) { @"-=", @"---", @"- ", @"-- ", @"-_", @"--_" };
    var t: ArgsTokenizer = .init(&.{ "-=", "---", "- ", "-- ", "-_", "--_" });
    try expectToken(O, t.next(O), .{ .option = .@"-=" });
    try expectToken(O, t.next(O), .{ .option = .@"---" });
    try expectToken(O, t.next(O), .{ .option = .@"- " });
    try expectToken(O, t.next(O), .{ .option = .@"-- " });
    try expectToken(O, t.next(O), .{ .option = .@"-_" });
    try expectToken(O, t.next(O), .{ .option = .@"--_" });
    try expectToken(O, t.next(O), null);
}

test "invalid option names" {
    // The dynamic API doesn't validate option names, which means that it's possible to define
    // options with invalid names that will only be recognized under certain circumstances.
    // (But why would someone do that?)
    const n = &[_][]const u8{ "-n", "--", "-1", "--foo=bar", "-abc", "x", "xyz" };
    const k: *const [n.len]OptionArity = &.{ .no_arg, .optional_arg, .optional_arg, .optional_arg, .optional_arg, .optional_arg, .optional_arg };
    var t: ArgsTokenizer = .init(&.{ "-1", "-1n", "--", "--n", "-n-", "-n--", "-n1", "-n11", "---", "--=", "--=11", "--foo", "--foo=bar", "-abc=1", "x1", "xyz=1" });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "-1" });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "-1n" });
    try expectDynamicToken(t.nextDynamic(n, k), .end_of_options);
    t.positional_only = false;
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "--n", null, null));
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 0, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 0, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = "-" } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 0, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 2, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 0, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 2, .arg = "1" } });
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "---", null, null));
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = "" } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = "11" } });
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "--foo", null, null));
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "--foo", null, "bar"));
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "-a", null, "bc=1"));
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "x1" });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "xyz=1" });
    try expectDynamicToken(t.nextDynamic(n, k), null);
    // When not defined, options with invalid names are handled as unrecognized as usual.
    // This could result in confusing "unrecognized option '--'" messages, but it is what it is.
    const O = union(enum) { @"-n" };
    t = .init(&.{ "-n-", "-n--", "-n1", "-n11", "--=", "--=11" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--", null, null));
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--", null, "-"));
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-1", null, null));
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-1", null, "1"));
    // Can't use 'initInvalidOption' for these because the tokenizer classifies them as long.
    try expectToken(O, t.next(O), .{ .invalid_option = .{ .err = error.UnrecognizedOption, .name = .{ .long = "--" }, .tag = null, .arg = "" } });
    try expectToken(O, t.next(O), .{ .invalid_option = .{ .err = error.UnrecognizedOption, .name = .{ .long = "--" }, .tag = null, .arg = "11" } });
    try expectToken(O, t.next(O), null);
}

test "end-of-options" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-n", "--no", "--", "-n", "--no", "--", "-n", "--no", "--" });
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"--no" });
    try expectToken(O, t.next(O), .end_of_options);
    try testing.expect(t.positional_only);
    try expectToken(O, t.next(O), .{ .positional = "-n" });
    try expectToken(O, t.next(O), .{ .positional = "--no" });
    try expectToken(O, t.next(O), .{ .positional = "--" });
    t.positional_only = false;
    try expectToken(O, t.next(O), .{ .option = .@"-n" });
    try expectToken(O, t.next(O), .{ .option = .@"--no" });
    try expectToken(O, t.next(O), .end_of_options);
    try testing.expect(t.positional_only);
    try expectToken(O, t.next(O), null);
}

test "end-of-options-like option-arguments" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-r--", "-r", "--", "--required=--", "--required", "--", "-x--", "--xyz=--" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "--" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "--" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "--" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "--" } });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "-x", null, "--"));
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnrecognizedOption, "--xyz", null, "--"));
    try expectToken(O, t.next(O), null);
}

test "positionals" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "/usr/bin", "@foo", "-", "" });
    try expectToken(O, t.next(O), .{ .positional = "/usr/bin" });
    try expectToken(O, t.next(O), .{ .positional = "@foo" });
    try expectToken(O, t.next(O), .{ .positional = "-" });
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), null);
}

test "forced positionals" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "--required", "-n", "-n", "-r", "-r", "123" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "-n" } });
    try testing.expectEqualDeep("-n", t.nextPositional());
    try testing.expectEqualDeep("-r", t.peekPositional());
    try testing.expectEqualDeep(@as([]const []const u8, &.{ "-r", "-r", "123" }), t.restPositional());
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "-r" } });
    try expectToken(O, t.next(O), .{ .positional = "123" });
    try expectToken(O, t.next(O), null);
}

test "empty string arguments" {
    const O = TestOption;
    var t: ArgsTokenizer = .init(&.{ "-r", "", "--no", "", "--no=", "", "--required", "", "--required=", "", "--optional", "", "--optional=", "" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"-r" = "" } });
    try expectToken(O, t.next(O), .{ .option = .@"--no" });
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), initInvalidOption(O, error.UnexpectedOptionArg, "--no", .@"--no", ""));
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "" } });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--required" = "" } });
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = null } });
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), .{ .option = .{ .@"--optional" = "" } });
    try expectToken(O, t.next(O), .{ .positional = "" });
    try expectToken(O, t.next(O), null);
}

test "NUL bytes" {
    // Option names containing NUL bytes are very dubious because NUL bytes will never be present
    // in a real argv. Regardless, having this test case helps codify that the tokenizer
    // always uses the 'len' field of slices to determine where arguments end, never NUL bytes.
    const n = &[_][]const u8{ "-n", "-\x00", "--\x00" };
    const k: *const [n.len]OptionArity = &.{ .no_arg, .optional_arg, .optional_arg };
    var t: ArgsTokenizer = .init(&.{ "-\x00", "-\x00\x00", "-n\x00", "--\x00", "--\x00=\x00", "--\x00\x00", "\x00--" });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = "\x00" } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 0, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 2, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 2, .arg = "\x00" } });
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "--\x00\x00", null, null));
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "\x00--" });
    try expectDynamicToken(t.nextDynamic(n, k), null);
}

test "non-ASCII code points" {
    // The tokenizer is not Unicode-aware and only processes raw bytes.
    // This means that non-ASCII long options are supported, but not short options,
    // and that invalid short option tokens may contain truncated UTF-8 sequences.
    const n = &[_][]const u8{ "-π", "--åäö", "--🀄" };
    const k: *const [n.len]OptionArity = &.{ .optional_arg, .optional_arg, .optional_arg };
    var t: ArgsTokenizer = .init(&.{
        "-π", // U+03C0 GREEK SMALL LETTER PI (not a short option)
        "-७", // U+096D DEVANAGARI DIGIT SEVEN (Unicode category Nd Decimal_Number)
        "−−", // U+2212 MINUS SIGN (different from U+002D HYPHEN-MINUS)
        "--åäö",
        "--🀄=ざわ･･",
    });
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "-π"[0..2], null, "-π"[2..]));
    try expectDynamicToken(t.nextDynamic(n, k), initDynamicInvalidOption(error.UnrecognizedOption, "-७"[0..2], null, "-७"[2..]));
    try expectDynamicToken(t.nextDynamic(n, k), .{ .positional = "−−" });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 1, .arg = null } });
    try expectDynamicToken(t.nextDynamic(n, k), .{ .option = .{ .index = 2, .arg = "ざわ･･" } });
    try expectDynamicToken(t.nextDynamic(n, k), null);
}

test "ends of returned arguments remain fixed to the ends of the original input" {
    // The tokenizer guarantees that the ends of returned positional/option arguments
    // always point to the same location in memory as the endpoints of the original input.
    // If the caller knows that the tokenizer was initialized from a `[]const [:0]const u8` slice,
    // then they can safely `@ptrCast` returned arguments to `[:0]const u8`.
    // (However, it is NOT safe to cast slices pointed to by 'token.invalid_option.name'!)
    var buf = "-r111\x00--required=222\x00-x333\x00--no=444\x00555".*;
    const args: []const [:0]u8 = &.{
        buf[0..5 :0],
        buf[6..20 :0],
        buf[21..26 :0],
        buf[27..35 :0],
        buf[36..39 :0],
    };
    const O = TestOption;
    var t: ArgsTokenizer = .init(args);
    var token = t.next(O);
    try expectToken(O, token, .{ .option = .{ .@"-r" = "111" } });
    var actual_arg: [:0]const u8 = @ptrCast(token.?.option.@"-r");
    try testing.expectEqual(args[0]["-r".len..].ptr, actual_arg.ptr);
    token = t.next(O);
    try expectToken(O, token, .{ .option = .{ .@"--required" = "222" } });
    actual_arg = @ptrCast(token.?.option.@"--required");
    try testing.expectEqual(args[1]["--required=".len..].ptr, actual_arg.ptr);
    token = t.next(O);
    try expectToken(O, token, initInvalidOption(O, error.UnrecognizedOption, "-x", null, "333"));
    actual_arg = @ptrCast(token.?.invalid_option.arg.?);
    try testing.expectEqual(args[2]["-x".len..].ptr, actual_arg.ptr);
    token = t.next(O);
    try expectToken(O, token, initInvalidOption(O, error.UnexpectedOptionArg, "--no", .@"--no", "444"));
    actual_arg = @ptrCast(token.?.invalid_option.arg.?);
    try testing.expectEqual(args[3]["--no=".len..].ptr, actual_arg.ptr);
    token = t.next(O);
    try expectToken(O, token, .{ .positional = "555" });
    actual_arg = @ptrCast(token.?.positional);
    try testing.expectEqual(args[4].ptr, actual_arg.ptr);
    token = t.next(O);
    try expectToken(O, token, null);
}

test "empty sets of options" {
    // 'union(enum) {}' should not be a compile error.
    const t: ArgsTokenizer = .init(&.{});
    if (t.peek(union(enum) {})) |result| switch (result.token) {
        .option => comptime unreachable,
        .end_of_options => {},
        .positional => {},
        .invalid_option => {},
    };
    if (t.peekDynamic(&.{}, &.{})) |result| switch (result.token) {
        .option => unreachable,
        .end_of_options => {},
        .positional => {},
        .invalid_option => {},
    };
}

pub fn isValidOptionName(name: []const u8) bool {
    return isValidShortOptionName(name) or isValidLongOptionName(name);
}

pub fn isValidShortOptionName(name: []const u8) bool {
    return name.len == 2 and name[0] == '-' and !(name[1] == '-' or std.ascii.isDigit(name[1]));
}

pub fn isValidLongOptionName(name: []const u8) bool {
    return name.len > 2 and name[0] == '-' and name[1] == '-' and std.mem.findScalarPos(u8, name, 2, '=') == null;
}
