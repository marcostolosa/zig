const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    if (builtin.os.tag == .windows) return; // TODO: libfuzzer support for windows
    if (builtin.os.tag == .openbsd) return; // https://codeberg.org/ziglang/zig/issues/30728

    const run_step = b.step("test", "Run unit tests");
    run_step.dependOn(&b.addRunArtifact(b.addTest(.{
        // There is currently no way to make the fuzz test run in fuzzing mode without "--fuzz".
        // However, this test still provides coverage for running through the corpus.
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
        .use_llvm = true, // #23423
    })).step);
    b.default_step = run_step;
}
