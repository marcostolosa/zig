const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;

const dev_t = std.c.dev_t;
const fd_t = std.c.fd_t;
const mode_t = std.c.mode_t;
const S = std.c.S;

const symbol = @import("../../c.zig").symbol;
const errno = @import("../../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&chmodLinux, "chmod");
        symbol(&mkdirLinux, "mkdir");
        symbol(&mkdiratLinux, "mkdirat");
        symbol(&mkfifoLinux, "mkfifo");
        symbol(&mkfifoatLinux, "mkfifoat");
        symbol(&mknodLinux, "mknod");
        symbol(&mknodatLinux, "mknodat");
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

fn mkfifoLinux(path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.mknod(@ptrCast(path), mode | S.IFIFO, 0));
}

fn mkfifoatLinux(dirfd: fd_t, path: [*:0]const c_char, mode: mode_t) callconv(.c) c_int {
    return errno(linux.mknodat(dirfd, @ptrCast(path), mode | S.IFIFO, 0));
}

fn mknodLinux(path: [*:0]const c_char, mode: mode_t, dev: dev_t) callconv(.c) c_int {
    // glibc and musl define dev_t as u64, but Linux kernel uses u32.
    // So only the 32 least significant bits of dev are necessary.
    return errno(linux.mknod(@ptrCast(path), mode, @truncate(dev)));
}

fn mknodatLinux(dirfd: fd_t, path: [*:0]const c_char, mode: mode_t, dev: dev_t) callconv(.c) c_int {
    // See comments in mknodLinux
    return errno(linux.mknodat(dirfd, @ptrCast(path), mode, @truncate(dev)));
}

fn umaskLinux(mode: mode_t) callconv(.c) mode_t {
    return @intCast(linux.umask(mode));
}
