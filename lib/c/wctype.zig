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
        symbol(&iswgraph, "iswgraph");
        symbol(&iswprint, "iswprint");
        symbol(&iswspace, "iswspace");
        symbol(&iswxdigit, "iswxdigit");

        symbol(&__iswalnum_l, "__iswalnum_l");
        symbol(&__iswblank_l, "__iswblank_l");
        symbol(&__iswdigit_l, "__iswdigit_l");
        symbol(&__iswgraph_l, "__iswgraph_l");
        symbol(&__iswprint_l, "__iswprint_l");
        symbol(&__iswspace_l, "__iswspace_l");
        symbol(&__iswxdigit_l, "__iswxdigit_l");

        symbol(&__iswalnum_l, "iswalnum_l");
        symbol(&__iswblank_l, "iswblank_l");
        symbol(&__iswdigit_l, "iswdigit_l");
        symbol(&__iswgraph_l, "iswgraph_l");
        symbol(&__iswprint_l, "iswprint_l");
        symbol(&__iswspace_l, "iswspace_l");
        symbol(&__iswxdigit_l, "iswxdigit_l");
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

fn iswgraph(wc: wint_t) callconv(.c) c_int {
    if (wc > std.math.maxInt(u8)) return 0;
    return @intFromBool(iswspace(wc) == 0 and iswprint(wc) != 0);
}

fn __iswgraph_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswgraph(wc);
}

fn iswprint(wc: wint_t) callconv(.c) c_int {
    const wc_unsigned: @Int(.unsigned, @bitSizeOf(wint_t)) = @bitCast(wc);
    if (wc_unsigned < 0xff)
        return @intFromBool((wc_unsigned +% 1 & 0x7f) >= 0x21);
    if (wc_unsigned < 0x2028 or wc_unsigned -% 0x202a < 0xd800 -% 0x202a or wc_unsigned -% 0xe000 < 0xfff9 -% 0xe000)
        return 1;
    if (wc_unsigned -% 0xfffc > 0x10ffff -% 0xfffc or (wc_unsigned & 0xfffe) == 0xfffe)
        return 0;
    return 1;
}

fn __iswprint_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswprint(wc);
}

const spaces = [_]wchar_t{ ' ', '\t', '\n', '\r', 11, 12, 0x0085, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x205f, 0x3000, 0 };

fn iswspace(wc: wint_t) callconv(.c) c_int {
    return @intFromBool(wc != 0 and std.c.wcschr(@ptrCast(&spaces[0]), @bitCast(wc)) != null);
}

fn __iswspace_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswspace(wc);
}

fn iswxdigit(wc: wint_t) callconv(.c) c_int {
    if (wc > std.math.maxInt(u8)) return 0;
    return std.c.isxdigit(@intCast(wc));
}

fn __iswxdigit_l(wc: wint_t, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return iswxdigit(wc);
}
