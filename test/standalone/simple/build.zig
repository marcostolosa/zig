const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const step = b.step("test", "Run simple standalone test cases");
    b.default_step = step;

    const skip_debug = b.option(bool, "skip_debug", "Skip debug builds") orelse false;
    const skip_release_safe = b.option(bool, "skip_release_safe", "Skip release-safe builds") orelse false;
    const skip_release_fast = b.option(bool, "skip_release_fast", "Skip release-fast builds") orelse false;
    const skip_release_small = b.option(bool, "skip_release_small", "Skip release-small builds") orelse false;

    var optimize_modes_buf: [4]std.builtin.Optimize = undefined;
    var optimize_modes_len: usize = 0;
    if (!skip_debug) {
        optimize_modes_buf[optimize_modes_len] = .debug;
        optimize_modes_len += 1;
    }
    if (!skip_release_safe) {
        optimize_modes_buf[optimize_modes_len] = .safe;
        optimize_modes_len += 1;
    }
    if (!skip_release_fast) {
        optimize_modes_buf[optimize_modes_len] = .fast;
        optimize_modes_len += 1;
    }
    if (!skip_release_small) {
        optimize_modes_buf[optimize_modes_len] = .small;
        optimize_modes_len += 1;
    }
    const optimize_modes = optimize_modes_buf[0..optimize_modes_len];

    for (cases) |case| {
        for (optimize_modes) |optimize| {
            if (!case.all_modes and optimize != .debug) continue;
            if (case.os_filter) |os_tag| {
                if (os_tag != builtin.os.tag) continue;
            }

            const resolved_target = b.resolveTargetQuery(case.target);

            if (case.file_type == .exe or case.file_type == .exe_and_obj) {
                const exe = b.addExecutable(.{
                    .name = std.fs.path.stem(case.src_path),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(case.src_path),
                        .optimize = optimize,
                        .target = resolved_target,
                        .link_libc = case.link_libc,
                    }),
                });
                if (case.emit_type == .bin) _ = exe.getEmittedBin();
                if (case.emit_type == .@"asm") _ = exe.getEmittedAsm();
                if (case.emit_type == .llvm_ir_and_llvm_bc) {
                    _ = exe.getEmittedLlvmIr();
                    _ = exe.getEmittedLlvmBc();
                }

                step.dependOn(&exe.step);
            }

            if (case.file_type == .obj or case.file_type == .exe_and_obj) {
                const obj = b.addObject(.{
                    .name = std.fs.path.stem(case.src_path),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(case.src_path),
                        .optimize = optimize,
                        .target = resolved_target,
                        .link_libc = case.link_libc,
                    }),
                });
                if (case.emit_type == .bin) _ = obj.getEmittedBin();
                if (case.emit_type == .@"asm") _ = obj.getEmittedAsm();
                if (case.emit_type == .llvm_ir_and_llvm_bc) {
                    _ = obj.getEmittedLlvmIr();
                    _ = obj.getEmittedLlvmBc();
                }

                step.dependOn(&obj.step);
            }
        }
    }
}

const FileType = enum {
    exe,
    obj,
    exe_and_obj,
};

const EmitType = enum {
    bin,
    @"asm",
    llvm_ir_and_llvm_bc,
};

const Case = struct {
    src_path: []const u8,
    link_libc: bool = false,
    all_modes: bool = false,
    target: std.Target.Query = .{},
    file_type: FileType = .exe,
    emit_type: EmitType = .bin,
    /// Run only on this OS.
    os_filter: ?std.Target.Os.Tag = null,
};

const cases = [_]Case{
    .{
        .src_path = "emit_asm_no_bin.zig",
        .file_type = .obj,
        .emit_type = .@"asm",
    },
    .{
        .src_path = "emit_llvm_no_bin.zig",
        .file_type = .obj,
        .emit_type = .llvm_ir_and_llvm_bc,
    },
    .{
        .src_path = "hello_world/hello.zig",
        .all_modes = true,
    },
    .{
        .src_path = "hello_world/hello_libc.zig",
        .link_libc = true,
        .all_modes = true,
    },
    .{ .src_path = "cat.zig" },
    .{ .src_path = "guess_number.zig" },
    .{ .src_path = "std_enums_big_enums.zig" },
};
