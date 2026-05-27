const std = @import("std");

const MainArgs = struct {
    one: i32,
    two: f32,
    three: ?enum { vanilla, chocolate, strawberry },
    four: []const [:0]const u8,
    @"--alfa": ?void,
    @"--bravo": bool = true,
    @"--charlie": ?i32,
    @"--delta": ?f32,
    @"--echo": ?enum { abc, def, ghi },
    @"--foxtrot": ?[:0]const u8,

    pub const @"--help": std.cli.Help(MainArgs) = .{
        .command_name = "appapp",
        .description = "Lorem ipsum...",
        .args = .{
            .one = .{ .description = "Nothing wrong with me" },
            .two = .{ .description = "Nothing wrong with me" },
            .three = .{ .description = "Something's got to give" },
            .four = .{ .description = "Something's got to give" },
            .@"--alfa" = .{ .description = "A" },
            .@"--bravo" = .{ .description = "B" },
            .@"--charlie" = .{ .description = "C" },
            .@"--delta" = .{ .description = "D" },
            .@"--echo" = .{ .description = "E" },
            .@"--foxtrot" = .{ .description = "F" },
        },
    };

    pub const @"--version": std.SemanticVersion = .{ .major = 1, .minor = 2, .patch = 0 };
};

pub fn main(init: std.process.Init, args: MainArgs) !void {
    _ = init;
    const expected: MainArgs = .{
        .one = 123,
        .two = 0.0012,
        .three = .chocolate,
        .four = &.{ "a", "bb", "ccc", "--help" },
        .@"--alfa" = {},
        .@"--bravo" = false,
        .@"--charlie" = -1,
        .@"--delta" = std.math.inf(f32),
        .@"--echo" = .ghi,
        .@"--foxtrot" = "--bravo",
    };
    try std.testing.expectEqualDeep(expected, args);
}

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test");
    b.default_step = test_step;

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build.zig"),
            .target = b.graph.host,
        }),
    });

    const run_exe_ok = b.addRunArtifact(exe);
    run_exe_ok.setName("run ok");
    run_exe_ok.addArgs(&.{
        "123",
        "1.2e-3",
        "--alfa",
        "--no-bravo",
        "chocolate",
        "--charlie=-2",
        "a",
        "--delta=inf",
        "--echo=ghi",
        "--foxtrot",
        "--bravo",
        "--charlie",
        "-1",
        "--",
        "bb",
        "ccc",
        "--help",
    });
    run_exe_ok.expectExitCode(0);
    run_exe_ok.expectStdOutEqual("");
    run_exe_ok.expectStdErrEqual("");
    test_step.dependOn(&run_exe_ok.step);

    const run_exe_fail = b.addRunArtifact(exe);
    run_exe_fail.setName("run fail");
    run_exe_fail.addArg("--asdf");
    run_exe_fail.color = .disable;
    run_exe_fail.expectExitCode(2);
    run_exe_fail.expectStdOutEqual("");
    run_exe_fail.expectStdErrEqual(
        \\error: unrecognized option '--asdf'
        \\Try 'appapp --help' for more information.
        \\
    );
    test_step.dependOn(&run_exe_fail.step);

    const run_exe_help = b.addRunArtifact(exe);
    run_exe_help.setName("run help");
    run_exe_help.addArg("--help");
    run_exe_help.color = .disable;
    run_exe_help.expectExitCode(0);
    run_exe_help.expectStdOutEqual(
        \\Usage: appapp [<option>...] [--] <one> <two> [<three> [<four>...]]
        \\
        \\Lorem ipsum...
        \\
        \\Arguments:
        \\  <one>      Nothing wrong with me
        \\  <two>      Nothing wrong with me
        \\  <three>    Something's got to give
        \\  <four>...  Something's got to give
        \\
        \\Options:
        \\  --alfa              A
        \\  --[no-]bravo        B
        \\  --charlie=<number>  C
        \\  --delta=<number>    D
        \\  --echo=<choice>     E
        \\  --foxtrot=<value>   F
        \\  -h, --help          Print this help and exit
        \\  --version           Print version and exit
        \\
    );
    run_exe_help.expectStdErrEqual("");
    test_step.dependOn(&run_exe_help.step);

    const run_exe_version = b.addRunArtifact(exe);
    run_exe_version.setName("run version");
    run_exe_version.addArg("--version");
    run_exe_version.expectExitCode(0);
    run_exe_version.expectStdOutEqual("1.2.0\n");
    run_exe_version.expectStdErrEqual("");
    test_step.dependOn(&run_exe_version.step);
}
