const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize: std.builtin.OptimizeMode = .Debug;

    const exe = b.addExecutable(.{
        .name = "cdb_exe",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("main.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            },
        ),
    });
    exe.root_module.addCSourceFile(.{
        .file = b.path("foo.c"),
        .flags = &.{"-Wall"},
    });
    exe.root_module.addCSourceFiles(.{
        .files = &.{ "bar.c", "baz.c" },
        .flags = &.{ "-Wall", "-Werror" },
    });
    const cc_exe = exe.getCompileCommandsJson();

    const lib = b.addLibrary(.{
        .name = "cdb_lib",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("obj_or_lib.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            },
        ),
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("foo.c"),
        .flags = &.{"-Wno-pedantic"},
    });
    lib.root_module.addCSourceFiles(.{
        .files = &.{"baz.c"},
        .flags = &.{"-Wall"},
    });
    const cc_lib = lib.getCompileCommandsJson();

    const obj = b.addObject(.{
        .name = "cdb_obj",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("obj_or_lib.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            },
        ),
    });
    obj.root_module.addCSourceFile(.{
        .file = b.path("foo.c"),
        .flags = &.{"-Wno-pedantic"},
    });
    obj.root_module.addCSourceFiles(.{
        .files = &.{"baz.c"},
        .flags = &.{"-Wall"},
    });
    const cc_obj = obj.getCompileCommandsJson();

    const test_exe = b.addObject(.{
        .name = "cdb_test",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("main.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            },
        ),
    });
    test_exe.root_module.addCSourceFile(.{
        .file = b.path("bar.c"),
        .flags = &.{"-Werror"},
    });
    test_exe.root_module.addCSourceFiles(.{
        .files = &.{"foo.c"},
        .flags = &.{},
    });
    const cc_test = test_exe.getCompileCommandsJson();

    const check_exe = b.addExecutable(.{
        .name = "check",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .root_source_file = b.path("check.zig"),
        }),
    });

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;
    test_step.dependOn(addCheck(b, check_exe, b.path("exe_expected.json"), cc_exe));
    test_step.dependOn(addCheck(b, check_exe, b.path("lib_expected.json"), cc_lib));
    test_step.dependOn(addCheck(b, check_exe, b.path("obj_expected.json"), cc_obj));
    test_step.dependOn(addCheck(b, check_exe, b.path("test_expected.json"), cc_test));
}

fn addCheck(
    b: *std.Build,
    check_exe: *std.Build.Step.Compile,
    expected_json: std.Build.LazyPath,
    compdb_json: std.Build.LazyPath,
) *std.Build.Step {
    const run_check = b.addRunArtifact(check_exe);
    run_check.addFileArg(expected_json);
    run_check.addFileArg(compdb_json);
    return &run_check.step;
}
