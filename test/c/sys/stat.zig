const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std");
const c = std.c;
const errno = c.errno;
const path = std.Io.Dir.path;

const testing = std.testing;
const io = testing.io;
const allocator = testing.allocator;
const tmpDir = testing.tmpDir;
const expectEqual = testing.expectEqual;

test "chmod" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest; // no chmod

    var tmp = tmpDir(.{});
    defer tmp.cleanup();
    // Relies on tmpDir internals
    const dir_path = try path.joinZ(allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer allocator.free(dir_path);

    try expectEqual(.SUCCESS, errno(c.chmod(dir_path, 0o700)));
    try expectEqual(0o700, (try tmp.dir.stat(io)).permissions.toMode() & 0o777);

    try expectEqual(.SUCCESS, errno(c.chmod(dir_path, 0o755)));
    try expectEqual(0o755, (try tmp.dir.stat(io)).permissions.toMode() & 0o777);

    const file = try tmp.dir.createFile(io, "test_file", .{ .permissions = .fromMode(0o600) });
    defer file.close(io);
    const file_path = try path.joinZ(allocator, &.{ dir_path, "test_file" });
    defer allocator.free(file_path);

    try expectEqual(.SUCCESS, errno(c.chmod(file_path, 0o444)));
    try expectEqual(0o444, (try file.stat(io)).permissions.toMode() & 0o777);

    try expectEqual(.SUCCESS, errno(c.chmod(file_path, 0o754)));
    try expectEqual(0o754, (try file.stat(io)).permissions.toMode() & 0o777);

    try expectEqual(.SUCCESS, errno(c.chmod(file_path, 0o776)));
    try expectEqual(0o776, (try file.stat(io)).permissions.toMode() & 0o777);
}

test "mkdir" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest; // no mkdir

    var tmp = tmpDir(.{});
    defer tmp.cleanup();
    // Relies on tmpDir internals
    const dir_path = try path.joinZ(allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer allocator.free(dir_path);
    try expectEqual(.EXIST, errno(c.mkdir(dir_path, 0o755)));

    const new_dir_path = try path.joinZ(allocator, &.{ dir_path, "test_dir" });
    defer allocator.free(new_dir_path);
    try expectEqual(.SUCCESS, errno(c.mkdir(new_dir_path, 0o755)));
    var new_dir = try tmp.dir.openDir(io, "test_dir", .{});
    defer new_dir.close(io);
}

test "mkdirat" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest; // no mkdirat

    var tmp = tmpDir(.{});
    defer tmp.cleanup();
    // Relies on tmpDir internals
    const dir_path = try path.joinZ(allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer allocator.free(dir_path);
    try expectEqual(.EXIST, errno(c.mkdirat(c.AT.FDCWD, dir_path, 0o755)));

    try expectEqual(.SUCCESS, errno(c.mkdirat(tmp.dir.handle, "test_dir", 0o755)));
    var new_dir = try tmp.dir.openDir(io, "test_dir", .{});
    defer new_dir.close(io);
}
