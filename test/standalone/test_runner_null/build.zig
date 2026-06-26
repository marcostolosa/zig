const std = @import("std");

pub fn build(b: *std.Build) void {
    const verbose = b.option(bool, "verbose", "verbose output") orelse false;

    const test_exe = b.addTest(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.graph.host,
        }),
        .test_runner = null,
    });

    const options = b.addOptions();
    options.addOption(bool, "verbose", verbose);
    test_exe.root_module.addOptions("config", options);

    const test_step = b.step("test", "Test the program");
    b.default_step = test_step;

    const test_run = b.addRunArtifact(test_exe);
    test_run.addCheck(.{ .expect_stderr_match = "1 OK, 1 SKIP, 1 FAIL" });
    test_step.dependOn(&test_run.step);
}
