const std = @import("../std.zig");
const cli = @import("../cli.zig");

const git: cli.Command = .{
    .name = "git",
    .help = "A super long help page...\n",
    .help_short = "A version control system.",
    .named_args = &.{
        .init(bool, .{ .name = "paginate", .short = 'p', .default_value = false, .help = "Enable pagination." }),
        // this is a fictional argument
        .init(std.log.Level, .{ .name = "log-level", .short = 'l', .default_value = .warn, .help = "Set log level.\nOne of debug, warn, error.\n" }),
        // this is a fictional argument
        .init([]const bool, .{ .name = "verbose", .count = .unlimited, .short = 'v', .default_value = &.{true}, .help = "Increase verbosity.\n" }),
    },
    .subcommands = &.{
        .{
            .name = "clone",
            .named_args = &.{
                // this is a fictional argument
                .init(f32, .{ .name = "timeout-s", .count = .one, .default_value = 10.0 }),
            },
            .positional_args = &.{
                .init([]const u8, .{ .name = "url", .count = .one, .help = "The git URL to clone." }),
            },
            .help_short = "Download a repository.",
            .help = "Download a repository.\nUse a git URL.\n",
        },
        .{
            .name = "add",
            .positional_args = &.{
                .init([]const [:0]const u8, .{ .name = "files", .count = .unlimited }),
            },
            .help_short = "Stage files.",
        },
        .{
            .name = "commit",
            .named_args = &.{
                .init([]const [:0]const u8, .{ .name = "message", .short = 'm', .count = .unlimited }),
                .init(?[:0]const u8, .{ .name = "author", .count = .one }),
                .init(bool, .{ .name = "verbose", .count = .one, .short = 'v', .help = "Be verbose.", .default_value = false }),
            },
            .help_short = "Commit staged changes.",
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
            .help_short = "Create a branch.",
        },
        .{
            .name = "log",
            .named_args = &.{
                .init(?u32, .{ .name = "max-count", .count = .one }),
                .init(bool, .{ .name = "remove-empty", .count = .one }),
                // this is a fictional argument
                .init([]const bool, .{ .name = "verbose", .count = .unlimited, .short = 'v', .default_value = &.{}, .help = "Increase verbosity.\n" }),
            },
        },
        .{
            .name = "init",
            .positional_args = &.{
                .init([:0]const u8, .{ .name = "directory", .count = .one, .default_value = "." }),
            },
            .help_short = "Create a repository.",
        },
        .{
            .name = "diff",
            .positional_args = &.{
                .init([:0]const u8, .{ .name = "path1", .count = .one }),
                .init([:0]const u8, .{ .name = "path2", .count = .one, .help = "The second path to diff." }),
            },
            .help_short = "Compare files.",
            .help = "Compare two files.\nReturns differences in patch diff format.\n",
        },
    },
};

test "parseAlloc.named.bool" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parseAlloc.named.bool.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate=true" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parseAlloc.named.bool.suffix.false" {
    const raw: []const [:0]const u8 = &.{ "git", "--paginate=false" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(!parsed.kind.args.paginate);
}

test "parseAlloc.named.bool.no" {
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(!parsed.kind.args.paginate);
}

test "parseAlloc.named.bool.no.suffix" {
    // this functionality intentionally not included
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate=true" };
    const parsed = cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.named.bool.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-p" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

test "parseAlloc.named.bool.last_wins" {
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate", "--paginate" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.paginate);
}

// this functionality intentionally omitted
test "parseAlloc.named.bool.short.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "-p=true" };
    const parsed = cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.named.bool.unlimited.default" {
    const raw: []const [:0]const u8 = &.{"git"};
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expect(parsed.kind.args.verbose[0]);
    try std.testing.expectEqual(1, parsed.kind.args.verbose.len);
}

test "parseAlloc.named.bool.unlimited" {
    const raw: []const [:0]const u8 = &.{ "git", "--verbose", "--no-verbose" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expect(parsed.kind.args.verbose[0]);
    try std.testing.expect(!parsed.kind.args.verbose[1]);
    try std.testing.expectEqual(2, parsed.kind.args.verbose.len);
}

test "parseAlloc.named.string.unlimited" {
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
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings("Added cli to the std library!", parsed.subcommand.?.commit.kind.args.message[0]);
    try std.testing.expectEqualStrings("I hope it works!", parsed.subcommand.?.commit.kind.args.message[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.commit.kind.args.message.len);
}

test "parseAlloc.named.string.unlimited.suffix" {
    const raw: []const [:0]const u8 = &.{
        "git",
        "commit",
        "--message=Added cli to the std library!",
        "-m",
        "I hope it works!",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings("Added cli to the std library!", parsed.subcommand.?.commit.kind.args.message[0]);
    try std.testing.expectEqualStrings("I hope it works!", parsed.subcommand.?.commit.kind.args.message[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.commit.kind.args.message.len);
}

test "parseAlloc.positional.optional.string" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "dev/std.cli" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{ .render_usage_errors = true });
    try std.testing.expectEqualStrings("dev/std.cli", parsed.subcommand.?.branch.kind.args.branch_name.?);
}

test "parseAlloc.positional.optional.string.null" {
    const raw: []const [:0]const u8 = &.{ "git", "branch" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{ .render_usage_errors = true });
    try std.testing.expect(parsed.subcommand.?.branch.kind.args.branch_name == null);
}

test "parseAlloc.named.optional.int" {
    const raw: []const [:0]const u8 = &.{ "git", "log", "--max-count", "4", "--no-remove-empty" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual(4, parsed.subcommand.?.log.kind.args.@"max-count".?);
    try std.testing.expectEqual(false, parsed.subcommand.?.log.kind.args.@"remove-empty");
}

test "parseAlloc.named.float" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--timeout-s", "30.1", "https://example.com/repo.git" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual(30.1, parsed.subcommand.?.clone.kind.args.@"timeout-s");
}

test "parseAlloc.positional.string.unlimited.required_missing" {
    const raw: []const [:0]const u8 = &.{ "git", "add" };
    const parsed = cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.positional.string.unlimited" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "README.md", "build.zig" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual("README.md", parsed.subcommand.?.add.kind.args.files[0]);
    try std.testing.expectEqual("build.zig", parsed.subcommand.?.add.kind.args.files[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.add.kind.args.files.len);
}

test "parseAlloc.positional.string.one.default_value" {
    const raw: []const [:0]const u8 = &.{ "git", "init" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqualStrings(".", parsed.subcommand.?.init.kind.args.directory);
}

test "parseAlloc.positional.string.one" {
    const raw: []const [:0]const u8 = &.{ "git", "init", "src/lib" };
    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqualStrings("src/lib", parsed.subcommand.?.init.kind.args.directory);
}

test "parseAlloc.help" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.kind == .help);
}

test "parseAlloc.help.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-h" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.kind == .help);
}

test "parseAlloc.subcommand.help" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.subcommand.?.clone.kind == .help);
}

test "parseAlloc.subcommand.help.short" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "-h" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.subcommand.?.clone.kind == .help);
}

test "parseAlloc.positional.string.positional_sigil" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--", "--verbose" };

    const parsed = try cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectEqual("--verbose", parsed.subcommand.?.branch.kind.args.branch_name.?);
    try std.testing.expectEqual(false, parsed.subcommand.?.branch.kind.args.verbose);
}

test "parseAlloc.switch_on_subcommand" {
    const raw: []const [:0]const u8 = &.{ "git", "branch" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    switch (parsed.subcommand.?) {
        .branch => {},
        else => try std.testing.expect(false),
    }
}

test "writeHelpVerbatim" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 = "A super long help page...\n";
    try cli.writeHelpVerbatim(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpVerbatim.subcommand" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 = "Create a branch.\n";
    try cli.writeHelpVerbatim(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "parseAlloc.named.enum" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level", "debug" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parseAlloc.named.enum.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level=debug" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

// This functionality intentionally omitted.
test "parseAlloc.named.enum.suffix.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l=debug" };
    const parsed = cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.named.enum.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l", "debug" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parseAlloc.named.short_cluster_with_arg" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "-vm", "std.cli" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual(true, parsed.subcommand.?.commit.kind.args.verbose);
    try std.testing.expectEqualStrings("std.cli", parsed.subcommand.?.commit.kind.args.message[0]);
    try std.testing.expectEqual(1, parsed.subcommand.?.commit.kind.args.message.len);
}

test "parseAlloc.named.short_cluster_no_arg" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "-vvvvv" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual(true, parsed.subcommand.?.branch.kind.args.verbose);
}

test "parseAlloc.named.short_cluster_unlimited_bool_no_arg" {
    const raw: []const [:0]const u8 = &.{ "git", "-vvv", "--no-verbose", "--verbose", "branch", "-vvvvv" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual(true, parsed.subcommand.?.branch.kind.args.verbose);
    try std.testing.expectEqualSlices(bool, parsed.kind.args.verbose, &.{ true, true, true, false, true });
}

test "parseAlloc.named.short_cluster_unlimited_with_arg" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "-vm", "std.cli", "-vm", "Super cool!" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual(true, parsed.subcommand.?.commit.kind.args.verbose);
    try std.testing.expectEqualSlices([:0]const u8, parsed.subcommand.?.commit.kind.args.message, &.{ "std.cli", "Super cool!" });
}

test "parseAlloc.named.short_cluster_wrong_order" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "-mv", "std.cli", "-vm", "Super cool!" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.named.short_cluster_missing_arg" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "-vm" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.named.short_cluster_unlimited_with_arg_has_dashes" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "-vm", "std.cli", "-vm", "-v" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual(true, parsed.subcommand.?.commit.kind.args.verbose);
    try std.testing.expectEqualSlices([:0]const u8, parsed.subcommand.?.commit.kind.args.message, &.{ "std.cli", "-v" });
}

test "parseAlloc.options.named.enum.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-l", "debug" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{
        .exit_help = true,
        .render_help = .verbatim,
        .exit_usage_error = true,
        .render_usage_errors = true,
    });
    try std.testing.expectEqual(.debug, parsed.kind.args.@"log-level");
}

test "parseAlloc.unknown_named_is_not_positional" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "-x", "debug" };
    const parsed = cli.parseAlloc(git, std.testing.failing_allocator, raw, .{});
    try std.testing.expectError(error.Usage, parsed);
}

test "parseAlloc.dash_is_valid_positional" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "-" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings(parsed.subcommand.?.add.kind.args.files[0], "-");
}

test "parseAlloc.named_argument_may_come_after_positional" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "dev/std.cli", "-v" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    try std.testing.expectEqualStrings(parsed.subcommand.?.branch.kind.args.branch_name.?, "dev/std.cli");
    try std.testing.expectEqual(true, parsed.subcommand.?.branch.kind.args.verbose);
}

test "descentPath" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "-" };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parseAlloc(git, arena.allocator(), raw, .{});
    const path = cli.descentPath(git, parsed);
    try std.testing.expectEqualStrings("git", path[0]);
    try std.testing.expectEqualStrings("add", path[1]);
    try std.testing.expectEqual(2, path.len);
}

test "writeHelpGenerated.snapshot.0" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git [OPTIONS] [SUBCOMMAND]
        \\
        \\A super long help page...
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
        \\  -p, --paginate, --no-paginate
        \\    Enable pagination.
        \\    Default: false
        \\
        \\  -l, --log-level [err|warn|info|debug]
        \\    Set log level.
        \\    One of debug, warn, error.
        \\    Default: warn
        \\
        \\  -v, --verbose, --no-verbose
        \\    Increase verbosity.
        \\    Default: true
        \\
        \\SUBCOMMANDS
        \\  clone
        \\    Download a repository.
        \\
        \\  add
        \\    Stage files.
        \\
        \\  commit
        \\    Commit staged changes.
        \\
        \\  branch
        \\    Create a branch.
        \\
        \\  log
        \\
        \\  init
        \\    Create a repository.
        \\
        \\  diff
        \\    Compare files.
        \\
    ;

    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.1" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git add  <files ...>
        \\
        \\POSITIONAL ARGUMENTS
        \\  files
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.2" {
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git clone [OPTIONS] <url>
        \\
        \\Download a repository.
        \\Use a git URL.
        \\
        \\POSITIONAL ARGUMENTS
        \\  url
        \\    The git URL to clone.
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
        \\  --timeout-s [number]
        \\    Default: 10
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.3" {
    const raw: []const [:0]const u8 = &.{ "git", "init", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git init  [directory]
        \\
        \\POSITIONAL ARGUMENTS
        \\  directory
        \\    Default: "."
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.4" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git commit [OPTIONS]
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
        \\  -m, --message [string]
        \\
        \\  --author [string]
        \\
        \\  -v, --verbose, --no-verbose
        \\    Be verbose.
        \\    Default: false
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.5" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git branch [OPTIONS] [branch_name]
        \\
        \\Create a branch.
        \\
        \\POSITIONAL ARGUMENTS
        \\  branch_name
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
        \\  -v, --verbose, --no-verbose
        \\    Default: false
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.6" {
    const raw: []const [:0]const u8 = &.{ "git", "log", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git log [OPTIONS]
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
        \\  --max-count [integer]
        \\
        \\  --remove-empty, --no-remove-empty
        \\
        \\  -v, --verbose, --no-verbose
        \\    Increase verbosity.
        \\    Default: <empty>
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "writeHelpGenerated.subcommand.snapshot.7" {
    const raw: []const [:0]const u8 = &.{ "git", "diff", "--help" };
    const parsed = try cli.parseAlloc(git, std.testing.allocator, raw, .{});
    var buf: [1024]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    const expected: []const u8 =
        \\Usage: git diff  <path1> <path2>
        \\
        \\Compare two files.
        \\Returns differences in patch diff format.
        \\
        \\POSITIONAL ARGUMENTS
        \\  path1
        \\  path2
        \\    The second path to diff.
        \\
        \\OPTIONS
        \\  -h, --help
        \\    Print this help and exit.
        \\
    ;
    try cli.writeHelpGenerated(git, parsed, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test "parse.named.bool.no" {
    const git_no_alloc: cli.Command = .{
        .name = "git",
        .help = "A super long help page...\n",
        .help_short = "A version control system.",
        .named_args = &.{
            .init(bool, .{ .name = "paginate", .short = 'p', .default_value = false, .help = "Enable pagination." }),
            // this is a fictional argument
            .init(std.log.Level, .{ .name = "log-level", .short = 'l', .default_value = .warn, .help = "Set log level.\nOne of debug, warn, error.\n" }),
        },
    };
    const raw: []const [:0]const u8 = &.{ "git", "--no-paginate" };
    const parsed = try cli.parse(git_no_alloc, raw, .{});
    try std.testing.expect(!parsed.kind.args.paginate);
}
