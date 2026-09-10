const std = @import("std");

/// Tests parity between `Step.Run` response file APIs and regular args APIs.
/// See also the `run_args` standalone test.
pub fn build(b: *std.Build) void {
    const step = b.step("test", "Test");
    b.default_step = step;

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.graph.host,
        }),
    });

    // Passthru options introduce side effects to the Run step, which is undesirable for tests.
    // Therefore, they are disabled when running the full standalone test suite,
    // but can be enabled when running this build.zig directly.
    const test_passthru = b.option(bool, "test_passthru", "Test passthru options") orelse false;

    const wf = b.addWriteFiles();
    const wf_file = wf.add("file", "content");
    const wf_dir = wf.getDirectory().path(b, "dir");

    for (@as([]const bool, &.{ true, false })) |make_absolute| {
        const path_arg_options: std.Build.Step.Run.PathArgOptions = .{
            .prefix = "path^",
            .suffix = "$",
            .make_absolute = make_absolute,
        };

        const run_exe = b.addRunArtifact(exe);
        step.dependOn(&run_exe.step);
        run_exe.setName(if (make_absolute) "run abs" else "run rel");
        run_exe.addArg(if (make_absolute) "abs" else "rel");
        const rsp = run_exe.addResponseFileArg("args.rsp", path_arg_options);

        rsp.addArg("eins");
        run_exe.addArg("eins");

        rsp.addArgs(&.{ "zwei", "guten Morgen" });
        run_exe.addArgs(&.{ "zwei", "guten Morgen" });

        rsp.addArtifactArg(exe, path_arg_options);
        run_exe.addArg("exe");

        _ = rsp.addOutputFileArg("out-file", path_arg_options);
        run_exe.addArg("out-file");

        rsp.addFileArg(wf_file, path_arg_options);
        run_exe.addArg("file");

        _ = rsp.addOutputDirectoryArg("out-dir", path_arg_options);
        run_exe.addArg("out-dir");

        rsp.addDirectoryArg(wf_dir, path_arg_options);
        run_exe.addArg("dir");

        _ = rsp.addDepFileOutputArg("deps.d", path_arg_options);
        run_exe.addArg("deps");

        const nested = rsp.addResponseFileArg("nested.rsp", path_arg_options);
        run_exe.addArg("nested");

        rsp.addFileContentArg(wf_file, .{ .prefix = "^", .suffix = "$" });
        run_exe.addArg("^content$");

        if (test_passthru) {
            rsp.addPassthruArgs();
            run_exe.addPassthruArgs();
        }

        const flags: std.Build.Step.Run.ToggleFlags = .{ .enabled = "1", .disabled = "0" };
        rsp.addThirdPartyEnabledArgDarling(flags);
        run_exe.addThirdPartyEnabledArgDarling(flags);
        rsp.addThirdPartyEnabledArgQemu(flags);
        run_exe.addThirdPartyEnabledArgQemu(flags);
        rsp.addThirdPartyEnabledArgRosetta(flags);
        run_exe.addThirdPartyEnabledArgRosetta(flags);
        rsp.addThirdPartyEnabledArgWasmtime(flags);
        run_exe.addThirdPartyEnabledArgWasmtime(flags);
        rsp.addThirdPartyEnabledArgWine(flags);
        run_exe.addThirdPartyEnabledArgWine(flags);

        // Test that backslashes and quotes in response files are escaped in a portable way.
        nested.addArg(
            \\\a\"b\\c\\"d\
        );
        run_exe.expectStdErrEqual(
            \\""\\"a"\\"\"b"\\""\\"c"\\""\\"\"d"\\""
            \\
        );

        run_exe.expectExitCode(0);
    }
}
