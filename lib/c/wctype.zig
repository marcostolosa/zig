const builtin = @import("builtin");

const std = @import("std");
const wint_t = std.c.wint_t;
const wchar_t = std.c.wchar_t;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&iswblank, "iswblank");

        symbol(&__iswblank_l, "__iswblank_l");

        symbol(&__iswblank_l, "iswblank_l");
    }
}

fn iswblank(wc: wint_t) callconv(.c) c_int {
    if (wc > std.math.maxInt(u8)) return 0;
    return std.c.isblank(@intCast(wc));
}

fn __iswblank_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswblank(wc);
}
