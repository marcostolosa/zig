const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    symbol(&strndup, "strndup");

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // memcpy implemented in compiler_rt
        // memmove implemented in compiler_rt
        // memset implemented in compiler_rt
        // memcmp implemented in compiler_rt
        symbol(&memchr, "memchr");
        symbol(&strcpy, "strcpy");
        symbol(&strncpy, "strncpy");
        symbol(&strcat, "strcat");
        symbol(&strncat, "strncat");
        symbol(&strcmp, "strcmp");
        symbol(&strncmp, "strncmp");
        symbol(&strverscmp, "strverscmp");
        symbol(&strcoll, "strcoll");
        symbol(&strxfrm, "strxfrm");
        symbol(&strchr, "strchr");
        symbol(&strrchr, "strrchr");
        symbol(&strcspn, "strcspn");
        symbol(&strspn, "strspn");
        symbol(&strpbrk, "strpbrk");
        symbol(&strstr, "strstr");
        symbol(&strtok, "strtok");
        symbol(&strdup, "strdup");
        // strlen is in compiler_rt

        symbol(&strtok_r, "strtok_r");
        symbol(&stpcpy, "stpcpy");
        symbol(&stpncpy, "stpncpy");
        symbol(&strnlen, "strnlen");
        symbol(&memmem, "memmem");

        symbol(&memccpy, "memccpy");

        symbol(&strsep, "strsep");
        symbol(&strlcat, "strlcat");
        symbol(&strlcpy, "strlcpy");
        symbol(&explicit_bzero, "explicit_bzero");

        symbol(&strchrnul, "strchrnul");
        symbol(&strcasestr, "strcasestr");
        symbol(&memrchr, "memrchr");
        symbol(&mempcpy, "mempcpy");

        symbol(&__strcoll_l, "__strcoll_l");
        symbol(&__strxfrm_l, "__strxfrm_l");
        symbol(&__strcoll_l, "strcoll_l");
        symbol(&__strxfrm_l, "strxfrm_l");

        // These symbols are not in the public ABI of musl/wasi. However they depend on these exports internally.
        symbol(&stpcpy, "__stpcpy");
        symbol(&stpncpy, "__stpncpy");
        symbol(&strchrnul, "__strchrnul");
        symbol(&memrchr, "__memrchr");
    }

    if (builtin.target.isMinGW()) {
        symbol(&strnlen, "strnlen");
        symbol(&mempcpy, "mempcpy");
        symbol(&strtok_r, "strtok_r");
    }
}

fn memchr(ptr: *const anyopaque, value: c_int, len: usize) callconv(.c) ?*anyopaque {
    const bytes: [*]const u8 = @ptrCast(ptr);
    return @constCast(bytes[std.mem.findScalar(u8, bytes[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strcpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char) callconv(.c) [*]c_char {
    _ = stpcpy(dst, src);
    return dst;
}

fn strncpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*]c_char {
    _ = stpncpy(dst, src, max);
    return dst;
}

fn strcat(noalias dst: [*:0]c_char, noalias src: [*:0]const c_char) callconv(.c) [*:0]c_char {
    return strncat(dst, src, std.math.maxInt(usize));
}

fn strncat(noalias dst: [*:0]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*:0]c_char {
    const dst_len = std.mem.len(@as([*:0]u8, @ptrCast(dst)));
    const src_len = strnlen(src, max);

    @memcpy(dst[dst_len..][0..src_len], src[0..src_len]);
    dst[dst_len + src_len] = 0;
    return dst[0..(dst_len + src_len) :0].ptr;
}

fn strcmp(a: [*:0]const c_char, b: [*:0]const c_char) callconv(.c) c_int {
    return strncmp(a, b, std.math.maxInt(usize));
}

fn strncmp(a: [*:0]const c_char, b: [*:0]const c_char, max: usize) callconv(.c) c_int {
    return switch (std.mem.boundedOrderZ(u8, @ptrCast(a), @ptrCast(b), max)) {
        .eq => 0,
        .gt => 1,
        .lt => -1,
    };
}

fn strverscmp(l0: [*:0]const u8, r0: [*:0]const u8) c_int {
    const l = l0;
    const r = r0;

    var i: usize = 0;
    var dp: usize = 0;
    var j: usize = 0;
    var z: c_int = 1;

    // Find maximal matching prefix and track its maximal digit
    // suffix and whether those digits are all zeros.
    while (l[i] == r[i]) : (i += 1) {
        const ch: c_int = l[i];

        if (ch == 0)
            return 0;

        if (!std.ascii.isDigit(l[i])) {
            dp = i + 1;
            z = 1;
        } else if (l[i] != '0') {
            z = 0;
        }
    }

    if (@as(c_uint, l[dp]) -% '1' < 9 and
        @as(c_uint, r[dp]) -% '1' < 9)
    {

        // If we're looking at non-degenerate digit sequences starting
        // with nonzero digits, longest digit string is greater.

        j = i;

        while (std.ascii.isDigit(l[j])) : (j += 1) {
            if (!std.ascii.isDigit(r[j]))
                return 1;
        }

        if (std.ascii.isDigit(r[j]))
            return -1;
    } else if (z != 0 and dp < i and
        (std.ascii.isDigit(l[i]) or std.ascii.isDigit(r[i])))
    {

        // Otherwise, if common prefix of digit sequence is
        // all zeros, digits order less than non-digits.

        return @as(c_int, @as(u8, l[i] -% '0')) -
            @as(c_int, @as(u8, r[i] -% '0'));
    }

    return @as(c_int, l[i]) - @as(c_int, r[i]);
}

fn strcoll(a: [*:0]const c_char, b: [*:0]const c_char) callconv(.c) c_int {
    return strcmp(a, b);
}

fn __strcoll_l(a: [*:0]const c_char, b: [*:0]const c_char, locale: *anyopaque) callconv(.c) c_int {
    _ = locale;
    return strcoll(a, b);
}

// NOTE: If 'max' is 0, 'dst' is allowed to be a null pointer
fn strxfrm(noalias dst: ?[*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) usize {
    const src_len = std.mem.len(@as([*:0]const u8, @ptrCast(src)));
    if (src_len < max) @memcpy(dst.?[0 .. src_len + 1], src[0 .. src_len + 1]);
    return src_len;
}

fn __strxfrm_l(noalias dst: ?[*]c_char, noalias src: [*:0]const c_char, max: usize, locale: *anyopaque) callconv(.c) usize {
    _ = locale;
    return strxfrm(dst, src, max);
}

fn strchr(str: [*:0]const c_char, value: c_int) callconv(.c) ?[*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    const len = std.mem.len(str_u8);

    if (value == 0) return @constCast(str + len);
    return @constCast(str[std.mem.findScalar(u8, str_u8[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strrchr(str: [*:0]const c_char, value: c_int) callconv(.c) ?[*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    // std.mem.len(str) + 1 to not special case '\0'
    return @constCast(str[std.mem.findScalarLast(u8, str_u8[0 .. std.mem.len(str_u8) + 1], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn strcspn(dst: [*:0]const c_char, values: [*:0]const c_char) callconv(.c) usize {
    const dst_slice = std.mem.span(@as([*:0]const u8, @ptrCast(dst)));
    return std.mem.findAny(u8, dst_slice, std.mem.span(@as([*:0]const u8, @ptrCast(values)))) orelse dst_slice.len;
}

fn strspn(dst: [*:0]const c_char, values: [*:0]const c_char) callconv(.c) usize {
    const dst_slice = std.mem.span(@as([*:0]const u8, @ptrCast(dst)));
    return std.mem.findNone(u8, dst_slice, std.mem.span(@as([*:0]const u8, @ptrCast(values)))) orelse dst_slice.len;
}

fn strpbrk(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.mem.findAny(u8, std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn strstr(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.mem.find(u8, std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn strtok(noalias maybe_str: ?[*:0]c_char, noalias values: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    const state = struct {
        var str: ?[*:0]c_char = null;
    };

    return strtok_r(maybe_str, values, &state.str);
}

fn strdup(str: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    const len = std.mem.len(str);
    const d_opaque = c.malloc(len + 1) orelse return null;
    const d: [*]c_char = @ptrCast(d_opaque);
    @memcpy(d[0 .. len + 1], str[0 .. len + 1]);
    return @ptrCast(d);
}

fn strndup(str: [*:0]const c_char, n: usize) callconv(.c) ?[*:0]c_char {
    const len = strnlen(str, n);
    const d_opaque = c.malloc(len + 1) orelse return null;
    const d: [*]c_char = @ptrCast(d_opaque);
    @memcpy(d[0..len], str[0..len]);
    d[len] = 0;
    return @ptrCast(d);
}

// strlen is in compiler_rt

fn strtok_r(noalias maybe_str: ?[*:0]c_char, noalias values: [*:0]const c_char, noalias state: *?[*:0]c_char) callconv(.c) ?[*:0]c_char {
    const str = if (maybe_str) |str|
        str
    else if (state.*) |state_str|
        state_str
    else
        return null;

    const str_bytes = std.mem.span(@as([*:0]u8, @ptrCast(str)));
    const values_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(values)));
    const tok_start = std.mem.findNone(u8, str_bytes, values_bytes) orelse return null;

    if (std.mem.findAnyPos(u8, str_bytes, tok_start, values_bytes)) |tok_end| {
        str[tok_end] = 0;
        state.* = str[tok_end + 1 ..];
    } else {
        state.* = str[str_bytes.len..];
    }

    return str[tok_start..];
}

fn stpcpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char) callconv(.c) [*]c_char {
    const src_len = std.mem.len(@as([*:0]const u8, @ptrCast(src)));
    @memcpy(dst[0 .. src_len + 1], src[0 .. src_len + 1]);
    return dst + src_len;
}

fn stpncpy(noalias dst: [*]c_char, noalias src: [*:0]const c_char, max: usize) callconv(.c) [*]c_char {
    const src_len = strnlen(src, max);
    const copying_len = @min(max, src_len);
    @memcpy(dst[0..copying_len], src[0..copying_len]);
    @memset(dst[copying_len..][0 .. max - copying_len], 0x00);
    return dst + copying_len;
}

fn strnlen(str: [*:0]const c_char, max: usize) callconv(.c) usize {
    return std.mem.findScalar(u8, @ptrCast(str[0..max]), 0) orelse max;
}

fn memmem(haystack: *const anyopaque, haystack_len: usize, needle: *const anyopaque, needle_len: usize) callconv(.c) ?*anyopaque {
    const haystack_bytes: [*:0]const u8 = @ptrCast(haystack);
    const needle_bytes: [*:0]const u8 = @ptrCast(needle);

    return @constCast(haystack_bytes[std.mem.find(u8, haystack_bytes[0..haystack_len], needle_bytes[0..needle_len]) orelse return null ..]);
}

fn strsep(maybe_str: *?[*:0]c_char, values: [*:0]const c_char) callconv(.c) ?[*]c_char {
    if (maybe_str.*) |str| {
        const values_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(values)));
        const str_bytes = std.mem.span(@as([*:0]u8, @ptrCast(str)));
        const found = std.mem.findAny(u8, str_bytes, values_bytes) orelse {
            maybe_str.* = null;
            return str;
        };

        str[found] = 0;
        maybe_str.* = str[found + 1 ..];
        return str;
    }

    return null;
}

fn strlcat(dst: [*:0]c_char, src: [*:0]const c_char, dst_total_len: usize) callconv(.c) usize {
    const dst_len = strnlen(dst, dst_total_len);
    const src_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(src)));

    if (dst_total_len == dst_len) return dst_len + src_bytes.len;

    const copying_len = @min(dst_total_len - (dst_len + 1), src_bytes.len);

    @memcpy(dst[dst_len..][0..copying_len], src[0..copying_len]);
    dst[dst_len + copying_len] = 0;
    return dst_len + src_bytes.len;
}

fn strlcpy(dst: [*]c_char, src: [*:0]const c_char, dst_total_len: usize) callconv(.c) usize {
    const src_bytes = std.mem.span(@as([*:0]const u8, @ptrCast(src)));
    if (dst_total_len != 0) {
        const copying_len = @min(src_bytes.len, dst_total_len - 1);
        @memcpy(dst[0..copying_len], src[0..copying_len]);
        dst[copying_len] = 0;
    }
    return src_bytes.len;
}

fn memccpy(noalias dst: *anyopaque, noalias src: *const anyopaque, value: c_int, len: usize) callconv(.c) *anyopaque {
    const dst_bytes: [*]u8 = @ptrCast(dst);
    const src_bytes: [*]const u8 = @ptrCast(src);
    const value_u8: u8 = @truncate(@as(c_uint, @bitCast(value)));
    const copying_len = std.mem.findScalar(u8, src_bytes[0..len], value_u8) orelse len;
    @memcpy(dst_bytes[0..copying_len], src_bytes[0..copying_len]);
    return dst_bytes + copying_len;
}

fn explicit_bzero(ptr: *anyopaque, len: usize) callconv(.c) void {
    const bytes: [*]u8 = @ptrCast(ptr);
    std.crypto.secureZero(u8, bytes[0..len]);
}

fn strchrnul(str: [*:0]const c_char, value: c_int) callconv(.c) [*:0]c_char {
    const str_u8: [*:0]const u8 = @ptrCast(str);
    const len = std.mem.len(str_u8);

    if (value == 0) return @constCast(str + len);
    return @constCast(str[std.mem.findScalar(u8, str_u8[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse len ..]);
}

fn strcasestr(haystack: [*:0]const c_char, needle: [*:0]const c_char) callconv(.c) ?[*:0]c_char {
    return @constCast(haystack[std.ascii.findIgnoreCase(std.mem.span(@as([*:0]const u8, @ptrCast(haystack))), std.mem.span(@as([*:0]const u8, @ptrCast(needle)))) orelse return null ..]);
}

fn memrchr(ptr: *const anyopaque, value: c_int, len: usize) callconv(.c) ?*anyopaque {
    const bytes: [*]const u8 = @ptrCast(ptr);
    return @constCast(bytes[std.mem.findScalarLast(u8, bytes[0..len], @truncate(@as(c_uint, @bitCast(value)))) orelse return null ..]);
}

fn mempcpy(noalias dst: *anyopaque, noalias src: *const anyopaque, len: usize) callconv(.c) *anyopaque {
    const dst_bytes: [*]u8 = @ptrCast(dst);
    const src_bytes: [*]const u8 = @ptrCast(src);
    @memcpy(dst_bytes[0..len], src_bytes[0..len]);
    return dst_bytes + len;
}
