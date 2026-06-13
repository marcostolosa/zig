const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

fn expectDirname(input: [:0]const u8, expected: []const u8) !void {
    var buffer: [100]u8 = undefined;
    @memcpy(buffer[0..input.len], input);
    buffer[input.len] = 0;
    const res = std.mem.span(@as([*:0]const u8, @ptrCast(c.dirname(@ptrCast(&buffer)))));
    try testing.expectEqualStrings(expected, res);
}

test "dirname" {
    if (builtin.target.os.tag == .windows) return; // windows has backslash instead of slash
    try expectDirname("", ".");
    try expectDirname(".", ".");
    try expectDirname("..", ".");
    try expectDirname("/", "/");
    try expectDirname("////", "/");
    try expectDirname("/usr/lib", "/usr");
    try expectDirname("/usr/", "/");
    try expectDirname("//usr//lib//", "//usr");
    try expectDirname("usr", ".");
    try expectDirname("/home/user/document.txt", "/home/user");
    try expectDirname("/var/log/nginx///", "/var/log");
}
