const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const fd_t = std.c.fd_t;
const mode_t = std.c.mode_t;

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&chmodLinux, "chmod");
        symbol(&mkdirLinux, "mkdir");
        symbol(&mkdiratLinux, "mkdirat");
        symbol(&umaskLinux, "umask");
    }
}

fn chmodLinux(path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.chmod(@ptrCast(path), mode));
}

fn mkdirLinux(path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.mkdir(@ptrCast(path), mode));
}

fn mkdiratLinux(dirfd: fd_t, path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.mkdirat(dirfd, @ptrCast(path), mode));
}

fn umaskLinux(mode: mode_t) callconv(.c) mode_t {
    return @intCast(linux.umask(mode));
}
