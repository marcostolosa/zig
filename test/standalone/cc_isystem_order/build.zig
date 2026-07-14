const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test zig cc -isystem ordering");
    b.default_step = test_step;

    // An explicit glibc version makes this a cross target even on x86_64 Linux,
    // so a successful include_next cannot be supplied by native host paths.
    const common_args = [_][]const u8{
        b.graph.zig_exe,
        "cc",
        "-target",
        "x86_64-linux-gnu.2.28",
        "-c",
    };

    const joined = b.addSystemCommand(&common_args);
    joined.addDirectoryArg2(b.path("override"), .{ .prefix = "-isystem", .make_absolute = true });
    joined.addFileArg2(b.path("test.c"), .{ .make_absolute = true });
    joined.addArg("-o");
    _ = joined.addOutputFileArg2("joined.o", .{});
    joined.setCwd(.cache_root);
    test_step.dependOn(&joined.step);

    const separate = b.addSystemCommand(&common_args);
    separate.addArg("-isystem");
    separate.addDirectoryArg2(b.path("override"), .{ .make_absolute = true });
    separate.addFileArg2(b.path("test.c"), .{ .make_absolute = true });
    separate.addArg("-o");
    _ = separate.addOutputFileArg2("separate.o", .{});
    separate.setCwd(.cache_root);
    test_step.dependOn(&separate.step);

    // Building WASI libc adds target headers through per-source flags. Those
    // internal headers must remain after the compiler's builtin headers.
    const wasi = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "cc",
        "-target",
        "wasm32-wasi-musl",
    });
    wasi.addFileArg2(b.path("wasi.c"), .{ .make_absolute = true });
    wasi.addArg("-o");
    _ = wasi.addOutputFileArg2("wasi.wasm", .{});
    wasi.setCwd(.cache_root);
    test_step.dependOn(&wasi.step);
}
