const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

const expectErrno = @import("../c.zig").expectErrno;

test "swab" {
    if (builtin.target.cpu.arch.isMIPS64() and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .x86_64 and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.os.tag == .netbsd) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    var a: [4]u8 = undefined;
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 4);
    try testing.expectEqualSlices(u8, "badc", &a);

    // Partial copy
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 2);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);

    // n < 1
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 0);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);
    c.swab("abcd", &a, -1);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);

    // Odd n
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 1);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);
    c.swab("abcd", &a, 3);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);
}

test "getresuid" {
    if (!builtin.target.isMuslLibC()) return error.SkipZigTest;

    const linux = std.os.linux;

    const sentinel = std.math.maxInt(linux.uid_t);
    var real: linux.uid_t = sentinel;
    var effective: linux.uid_t = sentinel;
    var saved: linux.uid_t = sentinel;

    try testing.expectEqual(@as(c_int, 0), c.getresuid(&real, &effective, &saved));
    try testing.expect(real != sentinel);
    try testing.expect(effective != sentinel);
    try testing.expect(saved != sentinel);
    try testing.expectEqual(c.getuid(), real);
    try testing.expectEqual(c.geteuid(), effective);

    // under current test scenario all three real, effective and saved would be same
    try testing.expectEqual(real, effective);
    try testing.expectEqual(real, saved);
}

test "getresuid error" {
    if (!builtin.target.isMuslLibC()) return error.SkipZigTest;

    const bad: *std.os.linux.uid_t = @ptrFromInt(8);

    // validate that behaviour is not changed
    try testing.expectEqual(@as(c_int, -1), c.getresuid(bad, bad, bad));
    try expectErrno(.FAULT);
}

test "getresgid" {
    if (!builtin.target.isMuslLibC()) return error.SkipZigTest;

    const linux = std.os.linux;

    const sentinel = std.math.maxInt(linux.gid_t);
    var real: linux.gid_t = sentinel;
    var effective: linux.gid_t = sentinel;
    var saved: linux.gid_t = sentinel;

    try testing.expectEqual(@as(c_int, 0), c.getresgid(&real, &effective, &saved));
    try testing.expect(real != sentinel);
    try testing.expect(effective != sentinel);
    try testing.expect(saved != sentinel);
    try testing.expectEqual(c.getgid(), real);
    try testing.expectEqual(c.getegid(), effective);

    // This test process is not setgid, so all three ids agree.
    try testing.expectEqual(real, effective);
    try testing.expectEqual(real, saved);
}

test "getresgid error" {
    if (!builtin.target.isMuslLibC()) return error.SkipZigTest;

    const bad: *std.os.linux.gid_t = @ptrFromInt(8);

    try testing.expectEqual(@as(c_int, -1), c.getresgid(bad, bad, bad));
    try expectErrno(.FAULT);
}
