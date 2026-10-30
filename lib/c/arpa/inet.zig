const builtin = @import("builtin");

const std = @import("std");

const symbol = @import("../../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&htons, "htons");
        symbol(&htonl, "htonl");
        symbol(&ntohs, "ntohs");
        symbol(&ntohl, "ntohl");
    }
}

fn htons(n: u16) callconv(.c) u16 {
    return std.mem.nativeToBig(u16, n);
}

fn htonl(n: u32) callconv(.c) u32 {
    return std.mem.nativeToBig(u32, n);
}

fn ntohs(n: u16) callconv(.c) u16 {
    return std.mem.bigToNative(u16, n);
}

fn ntohl(n: u32) callconv(.c) u32 {
    return std.mem.bigToNative(u32, n);
}
