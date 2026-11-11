const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "strncmp" {
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("b"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("c"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("b"), @ptrCast("a"), 1) > 0);
    try testing.expect(c.strncmp(@ptrCast("\xff"), @ptrCast("\x02"), 1) > 0);
}

test "strchr" {
    var str: [254:0]u8 = undefined;
    for (&str, 1..) |*p, i| p.* = @intCast(i + 1);
    const str_char: [*:0]const c_char = @ptrCast(&str);

    for (0..str.len) |i| {
        try testing.expectEqual(str_char[i..], c.strchr(str_char, str[i]));
    }

    try testing.expectEqual(null, c.strchr(@ptrCast("123456789"), '0'));
}

test "strchrnul" {
    if (builtin.target.os.tag == .windows or builtin.target.os.tag == .openbsd) return; // strchrnul not available
    var str: [254:0]u8 = undefined;
    for (&str, 1..) |*p, i| p.* = @intCast(i + 1);
    const str_char: [*:0]const c_char = @ptrCast(&str);

    for (0..str.len) |i| {
        try testing.expectEqual(str_char[i], c.strchrnul(str_char, str[i])[0]);
    }

    try testing.expectEqual(0, c.strchrnul(@ptrCast("123456789"), '0')[0]);
}

test "strcspn" {
    try testing.expectEqual(3, c.strcspn(@ptrCast("abc123"), @ptrCast("123")));
    try testing.expectEqual(6, c.strcspn(@ptrCast("abc456"), @ptrCast("123")));
    try testing.expectEqual(0, c.strcspn(@ptrCast("123abc"), @ptrCast("123")));
}

test "strspn" {
    try testing.expectEqual(0, c.strspn(@ptrCast("abc123"), @ptrCast("123")));
    try testing.expectEqual(3, c.strspn(@ptrCast("123abc"), @ptrCast("123")));
    try testing.expectEqual(6, c.strspn(@ptrCast("123123"), @ptrCast("123")));
    try testing.expectEqual(6, c.strspn(@ptrCast("333333"), @ptrCast("123")));
}

fn testStrpbrk(dst: [*:0]const u8, values: [*:0]const u8, expected_index: ?usize) !void {
    const first: ?[*:0]const u8 = @ptrCast(c.strpbrk(@ptrCast(dst), @ptrCast(values)));
    try testing.expectEqual(if (expected_index) |idx| dst[idx..] else null, first);
}

test "strpbrk" {
    try testStrpbrk("abc123", "123", 3);
    try testStrpbrk("abc456", "123", null);
    try testStrpbrk("123abc", "123", 0);
}

test "strtok_r" {
    if (builtin.target.os.tag == .windows) return; // strtok_r not available
    const sep: [:0]const c_char = @ptrCast(" |b");

    var str = "zig | zag | zog ||abc|     |   |    |def".*;
    var state: ?[*:0]c_char = null;

    try std.testing.expectEqualStrings("zig", @ptrCast(std.mem.span(c.strtok_r(@ptrCast(&str), sep, &state))));
    try std.testing.expectEqualStrings("zag", @ptrCast(std.mem.span(c.strtok_r(null, sep, &state))));
    try std.testing.expectEqualStrings("zog", @ptrCast(std.mem.span(c.strtok_r(null, sep, &state))));
    try std.testing.expectEqualStrings("a", @ptrCast(std.mem.span(c.strtok_r(null, sep, &state))));
    try std.testing.expectEqualStrings("c", @ptrCast(std.mem.span(c.strtok_r(null, sep, &state))));
    try std.testing.expectEqualStrings("def", @ptrCast(std.mem.span(c.strtok_r(null, sep, &state))));
    try std.testing.expectEqual(null, c.strtok_r(null, sep, &state));
}

test "strsep" {
    if (builtin.target.os.tag == .windows) return; // strsep not available
    const sep: [:0]const c_char = @ptrCast(" |b");

    var str = "zig|zag|zog||abc||def".*;
    var state: ?[*:0]c_char = @ptrCast(&str);

    try std.testing.expectEqualStrings("zig", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("zag", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("zog", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("a", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("c", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqualStrings("def", @ptrCast(std.mem.span(c.strsep(&state, sep))));
    try std.testing.expectEqual(null, c.strsep(&state, sep));
}

test "strdup" {
    const org: [*:0]const u8 = "a";
    const cpy_opt = c.strdup(@ptrCast(org));
    const cpy = cpy_opt orelse return error.OutOfMemory;
    defer c.free(cpy);

    const cpy_u8: [*:0]u8 = @ptrCast(cpy);
    try testing.expectEqualStrings(std.mem.span(org), std.mem.span(@as([*:0]const u8, cpy_u8)));
    try testing.expect(@intFromPtr(cpy_u8) != @intFromPtr(org));

    cpy_u8[0] = 'b';
    try testing.expectEqualStrings("a", std.mem.span(org));
    try testing.expectEqualStrings("b", std.mem.span(@as([*:0]const u8, cpy_u8)));
}

test "strndup" {
    if (builtin.target.os.tag == .windows) return; // no strndup
    const org1: [*:0]const u8 = "Hello";

    const copy1_opt = c.strndup(@ptrCast(org1), 100);
    const copy1 = copy1_opt orelse return error.OutOfMemory;
    defer c.free(copy1);
    const copy1_u8: [*:0]u8 = @ptrCast(copy1);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy1_u8)));

    const org2: [*:0]const u8 = "Hello World!";
    const copy2_opt = c.strndup(@ptrCast(org2), 5);
    const copy2 = copy2_opt orelse return error.OutOfMemory;
    defer c.free(copy2);
    const copy2_u8: [*:0]u8 = @ptrCast(copy2);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy2_u8)));
    try testing.expectEqual(@as(usize, 5), std.mem.len(copy2_u8));

    const copy3_opt = c.strndup(@ptrCast(org1), 5);
    const copy3 = copy3_opt orelse return error.OutOfMemory;
    defer c.free(copy3);
    const copy3_u8: [*:0]u8 = @ptrCast(copy3);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy3_u8)));
}

test "strnlen" {
    const str: [*:0]const u8 = "Hello";
    try testing.expectEqual(3, c.strnlen(@ptrCast(str), 3));
    try testing.expectEqual(4, c.strnlen(@ptrCast(str), 4));
    try testing.expectEqual(5, c.strnlen(@ptrCast(str), 5));
    try testing.expectEqual(5, c.strnlen(@ptrCast(str), 6));
    try testing.expectEqual(5, c.strnlen(@ptrCast(str), 7));
}
