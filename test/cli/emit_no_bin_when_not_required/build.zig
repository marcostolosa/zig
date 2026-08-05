const std = @import("std");

pub fn build(b: *std.Build) void {
    const check_step = b.step("check", "Check it");
    b.default_step = check_step;

    // executable that should build and link fine
    const runnable_exe = b.addExecutable(.{
        .name = "runnable",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runnable.zig"),
            .optimize = .debug,
            .target = b.graph.host,
        }),
    });

    // make "check" produce the above bin
    const run_step = b.addRunArtifact(runnable_exe);
    check_step.dependOn(&run_step.step);

    // executable that fails with linkage error
    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .optimize = .debug,
            .target = b.graph.host,
        }),
    });

    // depend on compulation but don't install the binary
    check_step.dependOn(&exe.step);

    // if this artifact gets built - the test will fail with linkage error
    b.installArtifact(exe);
}
