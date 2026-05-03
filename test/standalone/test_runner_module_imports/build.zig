const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
    });
    const module1 = b.createModule(.{ .root_source_file = b.path("module1.zig") });
    const module2 = b.createModule(.{ .root_source_file = b.path("module2.zig") });

    module2.addImport("module1", module1);
    test_mod.addImport("module2", module2);

    const t = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("test_runner.zig"),
            .mode = .simple,
        },
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(t).step);
    b.default_step = test_step;
}
