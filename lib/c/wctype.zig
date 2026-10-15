const builtin = @import("builtin");

const std = @import("std");
const wint_t = std.c.wint_t;
const wchar_t = std.c.wchar_t;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&iswalnum, "iswalnum");
        symbol(&iswblank, "iswblank");
        symbol(&iswdigit, "iswdigit");

        symbol(&__iswalnum_l, "__iswalnum_l");
        symbol(&__iswblank_l, "__iswblank_l");
        symbol(&__iswdigit_l, "__iswdigit_l");

        symbol(&__iswalnum_l, "iswalnum_l");
        symbol(&__iswblank_l, "iswblank_l");
        symbol(&__iswdigit_l, "iswdigit_l");
    }
}

fn iswalnum(wc: wint_t) callconv(.c) c_int {
    return @intFromBool(iswdigit(wc) != 0 or std.c.iswalpha(wc) != 0);
}

fn __iswalnum_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswalnum(wc);
}

fn iswblank(wc: wint_t) callconv(.c) c_int {
    if (wc > std.math.maxInt(u8)) return 0;
    return std.c.isblank(@intCast(wc));
}

fn __iswblank_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswblank(wc);
}

fn iswdigit(wc: wint_t) callconv(.c) c_int {
    if (wc > std.math.maxInt(u8)) return 0;
    return std.c.isdigit(@intCast(wc));
}

fn __iswdigit_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswdigit(wc);
}
