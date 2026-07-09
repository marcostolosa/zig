const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

fn expectBasename(input: [:0]const u8, expected: []const u8) !void {
    var buffer: [100]u8 = undefined;
    @memcpy(buffer[0..input.len], input);
    buffer[input.len] = 0;
    const res = std.mem.span(@as([*:0]const u8, @ptrCast(c.basename(@ptrCast(&buffer)))));
    try testing.expectEqualStrings(expected, res);
}

test "basename" {
    if (builtin.target.os.tag == .windows) return; // windows has backslash instead of slash
    try expectBasename("", ".");
    try expectBasename(".", ".");
    try expectBasename("..", "..");
    try expectBasename("/", "/");
    try expectBasename("////", "/");
    try expectBasename("/usr/lib", "lib");
    try expectBasename("/usr/", "usr");
    try expectBasename("//usr//lib//", "lib");
    try expectBasename("usr", "usr");
    try expectBasename("/home/user/document.txt", "document.txt");
    try expectBasename("/var/log/nginx///", "nginx");
}
