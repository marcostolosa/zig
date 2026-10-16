const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&basename, "basename");
        symbol(&basename, "__xpg_basename");
    }
}

const c_dot: [1:0]c_char = .{'.'};

fn basename(s: ?[*:0]c_char) callconv(.c) [*:0]c_char {
    const dot = @constCast(&c_dot);

    const ptr = s orelse return dot;
    if (ptr[0] == 0) return dot;

    var i = std.mem.len(ptr) - 1;

    while (i > 0 and ptr[i] == '/') : (i -= 1) {
        ptr[i] = 0;
    }
    while (i > 0 and ptr[i - 1] != '/') : (i -= 1) {}

    return ptr + i;
}
