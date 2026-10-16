const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&dirname, "dirname");
    }
}

const c_dot: [1:0]c_char = .{'.'};
const c_slash: [1:0]c_char = .{'/'};

fn dirname(s: ?[*:0]c_char) callconv(.c) [*:0]c_char {
    const dot = @constCast(&c_dot);
    const slash = @constCast(&c_slash);

    const ptr = s orelse return dot;
    if (ptr[0] == 0) return dot;

    var i = std.mem.len(ptr) - 1;

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
