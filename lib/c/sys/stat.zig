const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const mode_t = std.c.mode_t;

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&chmodLinux, "chmod");
    }
}

fn chmodLinux(path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.chmod(@ptrCast(path), mode));
}
