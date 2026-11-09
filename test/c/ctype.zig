const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "toupper" {
    try testing.expectEqual('A', c.toupper('a'));
    try testing.expectEqual('A', c.toupper('A'));
    try testing.expectEqual('!', c.toupper('!'));
    try testing.expectEqual(c.EOF, c.toupper(c.EOF));
}

test "tolower" {
    try testing.expectEqual('a', c.tolower('A'));
    try testing.expectEqual('a', c.tolower('a'));
    try testing.expectEqual('!', c.tolower('!'));
    try testing.expectEqual(c.EOF, c.tolower(c.EOF));
}
