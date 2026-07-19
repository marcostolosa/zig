const std = @import("std");

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "Test");
    b.default_step = test_step;

    const lib = b.addExecutable(.{
        .name = "lib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            // Optimizing for size removes debugging custom sections.
            // This allows our main.zig to assert that the wasm binary's custom sections
            // exactly match those defined in lib.zig.
            .optimize = .ReleaseSmall,
        }),
    });
    lib.entry = .disabled;

    const main = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.standardTargetOptions(.{}),
        }),
    });

    const build_options = b.addOptions();
    build_options.addOptionPath("wasm_path", lib.getEmittedBin());
    main.root_module.addOptions("build_options", build_options);

    main.step.dependOn(&lib.step);

    b.installArtifact(lib);
    b.installArtifact(main);

    const run_step = b.addRunArtifact(main);
    b.default_step.dependOn(&run_step.step);
}
