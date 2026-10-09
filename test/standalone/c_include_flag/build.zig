const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    // The header is found through the include path, not relative to the build root.
    exe.root_module.addIncludePath(b.path("include"));
    exe.root_module.addCSourceFile(.{
        .file = b.path("test.c"),
        .flags = &.{ "-include", "header.h" },
    });
    exe.root_module.link_libc = true;

    const run_c_cmd = b.addRunArtifact(exe);
    run_c_cmd.expectExitCode(0);
    run_c_cmd.skip_foreign_checks = true;
    test_step.dependOn(&run_c_cmd.step);
}
