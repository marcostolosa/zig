const std = @import("../std.zig");
const cli = @import("../cli.zig");

const git: cli.Command = .{
    .name = "git",
    .help = "A super long help page...\n",
    .help_short = "A version control system.",
    .named_args = &.{
        .init(bool, .{ .name = "paginate", .short = 'p', .default_value = false }),
        // this is a fictional argument
        .init(std.log.Level, .{ .name = "log-level", .short = 'l', .default_value = .warn }),
        // this is a fictional argument
        .init([]const bool, .{ .name = "verbose", .count = .unlimited, .default_value = &.{true} }),
    },
    .subcommands = &.{
        .{
            .name = "clone",
            .named_args = &.{
                // this is a fictional argument
                .init(f32, .{ .name = "timeout-s", .count = .one, .default_value = 10.0 }),
            },
            .positional_args = &.{
                .init([]const u8, .{ .name = "url", .count = .one }),
            },
        },
        .{
            .name = "add",
            .positional_args = &.{
                .init([]const [:0]const u8, .{ .name = "files", .count = .unlimited }),
            },
        },
        .{
            .name = "commit",
            .named_args = &.{
                .init([]const [:0]const u8, .{ .name = "message", .short = 'm', .count = .unlimited }),
                .init(?[:0]const u8, .{ .name = "author", .count = .one }),
            },
        },
        .{
            .name = "branch",
            .help = "Create a branch.\n",
            .positional_args = &.{
                .init(?[:0]const u8, .{ .name = "branch_name", .count = .one }),
            },
            .named_args = &.{
                .init(bool, .{ .name = "verbose", .short = 'v', .count = .one, .default_value = false }),
            },
        },
        .{
            .name = "log",
            .named_args = &.{
                .init(?u32, .{ .name = "max-count", .count = .one }),
            },
        },
        .{
            .name = "init",
            .positional_args = &.{
                .init([:0]const u8, .{ .name = "directory", .count = .one, .default_value = "." }),
            },
        },
    },
};

test "parse.named.bool" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parse.named.bool.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate=true" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parse.named.bool.suffix.false" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate=false" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(!parsed.kind.args.paginate);
}

test "parse.named.bool.no" {
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(!parsed.kind.args.paginate);
}

test "parse.named.bool.no.suffix" {
    // this functionality intentionally not included
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate=true" };
    const parsed = cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parse.named.bool.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-p" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parse.named.bool.last_wins" {
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate", "--paginate" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parse.named.bool.short.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "-p=true" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parse.named.bool.unlimited.default" {
    const raw: []const [:0]const u8 = &.{"git"};
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.verbose[0]);
    try std.testing.expectEqual(1, parsed.kind.args.verbose.len);
}

test "parse.named.bool.unlimited" {
    const raw: []const [:0]const u8 = &.{ "git", "--verbose", "--no-verbose" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expect(parsed.kind.args.verbose[0]);
    try std.testing.expect(!parsed.kind.args.verbose[1]);
    try std.testing.expectEqual(2, parsed.kind.args.verbose.len);
}

test "parse.named.string.unlimited" {
    const raw: []const [:0]const u8 = &.{
        "git",
        "commit",
        "--message",
        "Added cli to the std library!",
        "--message",
        "I hope it works!",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings("Added cli to the std library!", parsed.subcommand.?.commit.kind.args.message[0]);
    try std.testing.expectEqualStrings("I hope it works!", parsed.subcommand.?.commit.kind.args.message[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.commit.kind.args.message.len);
}

test "parse.named.string.unlimited.suffix" {
    const raw: []const [:0]const u8 = &.{
        "git",
        "commit",
        "--message=Added cli to the std library!",
        "-m=I hope it works!",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings("Added cli to the std library!", parsed.subcommand.?.commit.kind.args.message[0]);
    try std.testing.expectEqualStrings("I hope it works!", parsed.subcommand.?.commit.kind.args.message[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.commit.kind.args.message.len);
}

test "parse.positional.optional.string" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "dev/std.cli" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{ .render_usage_errors = true });
    try std.testing.expectEqualStrings("dev/std.cli", parsed.subcommand.?.branch.kind.args.branch_name.?);
}

test "parse.positional.optional.string.null" {
    const raw: []const [:0]const u8 = &.{ "git", "branch" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{ .render_usage_errors = true });
    try std.testing.expect(parsed.subcommand.?.branch.kind.args.branch_name == null);
}

test "parse.named.optional.int" {
    const raw: []const [:0]const u8 = &.{ "git", "log", "--max-count", "4" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual(4, parsed.subcommand.?.log.kind.args.@"max-count".?);
}

test "parse.named.float" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--timeout-s", "30.1", "https://example.com/repo.git" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual(30.1, parsed.subcommand.?.clone.kind.args.@"timeout-s");
}

test "parse.positional.string.unlimited.required_missing" {
    const raw: []const [:0]const u8 = &.{ "git", "add" };
    const parsed = cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parse.positional.string.unlimited" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "README.md", "build.zig" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual("README.md", parsed.subcommand.?.add.kind.args.files[0]);
    try std.testing.expectEqual("build.zig", parsed.subcommand.?.add.kind.args.files[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.add.kind.args.files.len);
}

test "parse.positional.string.one.default_value" {
    const raw: []const [:0]const u8 = &.{ "git", "init" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqualStrings(".", parsed.subcommand.?.init.kind.args.directory);
}

test "parse.positional.string.one" {
    const raw: []const [:0]const u8 = &.{ "git", "init", "src/lib" };
    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqualStrings("src/lib", parsed.subcommand.?.init.kind.args.directory);
}

test "parse.help" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.kind == .help);
}

test "parse.help.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-h" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.kind == .help);
}

test "parse.subcommand.help" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--help" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.subcommand.?.clone.kind == .help);
}

test "parse.subcommand.help.short" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "-h" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.subcommand.?.clone.kind == .help);
}

test "parse.positional.string.positional_sigil" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--", "--verbose" };

    const parsed = try cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual("--verbose", parsed.subcommand.?.branch.kind.args.branch_name.?);
    try std.testing.expectEqual(false, parsed.subcommand.?.branch.kind.args.verbose);
}

test "parse.switch_on_subcommand" {
    const raw: []const [:0]const u8 = &.{ "git", "branch" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    switch (parsed.subcommand.?) {
        .branch => {},
        else => try std.testing.expect(false),
    }
}

test "helpPage" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    const expected: []const u8 = "A super long help page...\n";
    try std.testing.expectEqualStrings(expected, cli.helpPage(git, parsed));
}

test "helpPage.subcommand" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--help" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});

    const expected2: []const u8 = "Create a branch.\n";
    try std.testing.expectEqualStrings(expected2, cli.helpPage(git, parsed));
}

test "parse.named.enum" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level", "debug" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parse.named.enum.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level=debug" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parse.named.enum.suffix.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l=debug" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parse.named.enum.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l", "debug" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parse.options.named.enum.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l", "debug" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{
        .exit_help = true,
        .render_help = true,
        .exit_usage_error = true,
        .render_usage_errors = true,
    });
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parse.unknown_named_is_not_positional" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "-x", "debug" };
    const parsed = cli.parse(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parse.dash_is_valid_positional" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "-" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings(parsed.subcommand.?.add.kind.args.files[0], "-");
}
