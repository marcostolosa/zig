const std = @import("../std.zig");
const cli = @import("../cli.zig");

test "Parsed.sanity" {

    // this can parse the following examples:
    //
    // * `git --log_level warn clone http://example.com`
    // * `git add hello.txt world.txt`
    const clone: cli.Command = .{
        .name = "clone",
        .positional_args = &.{
            .init([]const u8, .{ .name = "url", .count = .one }),
        },
    };
    const add: cli.Command = .{
        .name = "add",
        .positional_args = &.{
            .init([]const []const u8, .{ .name = "files", .count = .unlimited }),
        },
    };
    const base_command: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init([]const u8, .{ .name = "log_level", .count = .one }),
        },
        .subcommands = &.{ clone, add },
    };

    _ = cli.Parsed(base_command);
}

test "parse.named.bool" {
    const raw: []const [:0]const u8 = &.{ "git", "--verbose", "--no-dry-run" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init(bool, .{ .name = "verbose", .count = .one }),
            .init(bool, .{ .name = "dry-run", .count = .one }),
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.args.verbose);
    try std.testing.expect(!parsed.args.@"dry-run");
}

test "parse.named.bool.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--verbose=true", "--dry-run=false" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init(bool, .{ .name = "verbose", .count = .one }),
            .init(bool, .{ .name = "dry-run", .count = .one }),
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.args.verbose);
    try std.testing.expect(!parsed.args.@"dry-run");
}

test "parse.named.bool.short" {
    const raw: []const [:0]const u8 = &.{ "git", "-v", "--no-dry-run" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init(bool, .{ .name = "verbose", .count = .one, .short = 'v' }),
            .init(bool, .{ .name = "dry-run", .count = .one }),
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.args.verbose);
    try std.testing.expect(!parsed.args.@"dry-run");
}

test "parse.named.bool.multi" {
    const raw: []const [:0]const u8 = &.{ "git", "--verbose", "--verbose" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init([]bool, .{ .name = "verbose", .count = .unlimited }),
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expect(parsed.args.verbose[0]);
    try std.testing.expect(parsed.args.verbose[1]);
    try std.testing.expectEqual(2, parsed.args.verbose.len);
}

test "parse.named.slice.const.u8.multi" {
    const raw: []const [:0]const u8 = &.{
        "git",
        "commit",
        "--message",
        "Added cli to the std library!",
        "--message",
        "I hope it works!",
    };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{.{
            .name = "commit",
            .named_args = &.{
                .init([]const []const u8, .{ .name = "message", .count = .unlimited }),
            },
        }},
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual("Added cli to the std library!", parsed.subcommand.?.commit.args.message[0]);
    try std.testing.expectEqual("I hope it works!", parsed.subcommand.?.commit.args.message[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.commit.args.message.len);
}

test "parse.named.slice.const.u8" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "--message", "added cli to the std library!" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{.{
            .name = "commit",
            .named_args = &.{
                .init([]const u8, .{ .name = "message", .count = .one }),
            },
        }},
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual("added cli to the std library!", parsed.subcommand.?.commit.args.message);
}

test "parse.named.slice.const.u8.null_terminated" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "--message", "added cli to the std library!" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{.{
            .name = "commit",
            .named_args = &.{
                .init([:0]const u8, .{ .name = "message", .count = .one }),
            },
        }},
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual("added cli to the std library!", parsed.subcommand.?.commit.args.message);
}

test "parse.named.slice.const.u8.c_null_terminated" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "--message", "added cli to the std library!" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{.{
            .name = "commit",
            .named_args = &.{
                .init([:0]const u8, .{ .name = "message", .count = .one }),
            },
        }},
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual("added cli to the std library!", parsed.subcommand.?.commit.args.message);
}

test "parse.named.slice.const.u8.c_null_terminated.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "commit", "--message=added cli to the std library!" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{.{
            .name = "commit",
            .named_args = &.{
                .init([:0]const u8, .{ .name = "message", .count = .one }),
            },
        }},
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqualStrings("added cli to the std library!", parsed.subcommand.?.commit.args.message);
}

test "parse.named.int" {
    const raw: []const [:0]const u8 = &.{ "git", "log", "--max-count", "4" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "log",
                .named_args = &.{
                    .init(u32, .{ .name = "max-count", .count = .one }),
                },
            },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(4, parsed.subcommand.?.log.args.@"max-count");
}

test "parse.named.float" {
    // NOTE: git clone does not actually have a timeout parameter,
    // but this should serve as a realistic example for parsing a float argument.
    const raw: []const [:0]const u8 = &.{ "git", "clone", "--timeout-s", "30.1" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "clone",
                .named_args = &.{
                    .init(f32, .{ .name = "timeout-s", .count = .one }),
                },
            },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(30.1, parsed.subcommand.?.clone.args.@"timeout-s");
}

test "parse.positional.slice.const.u8" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "dev/awesome-feature" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "branch",
                .positional_args = &.{
                    .init([]const u8, .{ .name = "branch_name", .count = .one }),
                },
            },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual("dev/awesome-feature", parsed.subcommand.?.branch.args.branch_name);
}

test "parse.positional.slice.const.u8.multi" {
    const raw: []const [:0]const u8 = &.{ "git", "add", "README.md", "build.zig" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "add",
                .positional_args = &.{
                    .init([][]const u8, .{ .name = "files", .count = .unlimited }),
                },
            },
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual("README.md", parsed.subcommand.?.add.args.files[0]);
    try std.testing.expectEqual("build.zig", parsed.subcommand.?.add.args.files[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.add.args.files.len);
}

test "parse.positional.multi.default" {
    const raw: []const [:0]const u8 = &.{ "git", "add" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "add",
                .positional_args = &.{
                    .init([]const []const u8, .{ .name = "files", .count = .unlimited, .default_value = &.{ "README.md", "build.zig" } }),
                },
            },
        },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try cli.parse(git, arena.allocator(), raw, .{});
    try std.testing.expectEqual("README.md", parsed.subcommand.?.add.args.files[0]);
    try std.testing.expectEqual("build.zig", parsed.subcommand.?.add.args.files[1]);
    try std.testing.expectEqual(2, parsed.subcommand.?.add.args.files.len);
}

test "parse.help" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const git: cli.Command = .{ .name = "git" };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expect(parsed.args.help);
}

test "parse.positional.slice.const.u8.positional_sigil" {
    const raw: []const [:0]const u8 = &.{ "git", "branch", "--", "--verbose" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{
                .name = "branch",
                .positional_args = &.{
                    .init(bool, .{ .name = "verbose", .count = .one, .default_value = false }),
                    .init([]const u8, .{ .name = "branch_name", .count = .one }),
                },
            },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual("--verbose", parsed.subcommand.?.branch.args.branch_name);
    try std.testing.expectEqual(false, parsed.subcommand.?.branch.args.verbose);
}

test "parse.switch_on_subcommand" {
    const raw: []const [:0]const u8 = &.{ "git", "branch" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{ .name = "branch" },
            .{ .name = "add" },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});

    switch (parsed.subcommand.?) {
        .branch => {},
        .add => try std.testing.expect(false),
    }
}

test "printHelp" {
    const raw: []const [:0]const u8 = &.{ "git", "--help" };
    const git: cli.Command = .{
        .name = "git",
        .subcommands = &.{
            .{ .name = "branch", .help = "create a branch" },
            .{ .name = "add", .help = "add files to be committed" },
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try cli.printHelp(git, parsed, &writer);

    const expected: []const u8 =
        \\
        \\Usage: git ...
        \\
        \\
        \\Subcommands:
        \\  branch: create a branch
        \\  add: add files to be committed
        \\
    ;
    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "parse.named.enum" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level", "debug" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init(std.log.Level, .{ .name = "log-level", .count = .one }),
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.args.@"log-level");
}

test "parse.named.enum.suffix" {
    const raw: []const [:0]const u8 = &.{ "git", "--log-level=debug" };
    const git: cli.Command = .{
        .name = "git",
        .named_args = &.{
            .init(std.log.Level, .{ .name = "log-level", .count = .one }),
        },
    };
    const parsed = try cli.parse(git, std.testing.allocator, raw, .{});
    try std.testing.expectEqual(.debug, parsed.args.@"log-level");
}
