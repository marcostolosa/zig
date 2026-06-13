const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&dirname, "dirname");
    }
}

var dot_buf: [2]c_char = .{ '.', 0 };
var slash_buf: [2]c_char = .{ '/', 0 };

fn dirname(s: ?[*:0]c_char) callconv(.c) [*:0]c_char {
    const dot: [*:0]c_char = @ptrCast(&dot_buf);
    const slash: [*:0]c_char = @ptrCast(&slash_buf);

    if (s == null) return dot;

    const ptr = s.?;
    if (ptr[0] == 0) return dot;

    var i = std.mem.len(@as([*:0]u8, @ptrCast(ptr))) - 1;

    while (true) : (i -= 1) {
        if (ptr[i] != '/') break;
        if (i == 0) return slash;
    }

    while (true) : (i -= 1) {
        if (ptr[i] == '/') break;
        if (i == 0) return dot;
    }

    while (true) : (i -= 1) {
        if (ptr[i] != '/') break;
        if (i == 0) return slash;
    }

    ptr[i + 1] = 0;
    return ptr;
}
