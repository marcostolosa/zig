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
        symbol(&iswprint, "iswprint");

        symbol(&__iswalnum_l, "__iswalnum_l");
        symbol(&__iswblank_l, "__iswblank_l");
        symbol(&__iswdigit_l, "__iswdigit_l");
        symbol(&__iswprint_l, "__iswprint_l");

        symbol(&__iswalnum_l, "iswalnum_l");
        symbol(&__iswblank_l, "iswblank_l");
        symbol(&__iswdigit_l, "iswdigit_l");
        symbol(&__iswprint_l, "iswprint_l");
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
