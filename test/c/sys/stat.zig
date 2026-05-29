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
