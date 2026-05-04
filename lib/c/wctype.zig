const builtin = @import("builtin");

const std = @import("std");
const wint_t = std.c.wint_t;
const wchar_t = std.c.wchar_t;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {}
}
