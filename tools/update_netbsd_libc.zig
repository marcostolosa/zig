const Args = struct {
    netbsd_src_path: []const u8,
    zig_src_path: []const u8,

    pub const @"--help": std.cli.Help(Args) = .{
        .command_name = "zig run tools/update_netbsd_libc.zig --",
        .summary = (
            \\This script updates the .c, .h, .s, and .S files that make up the start
            \\files such as crt1.o.
            \\
            \\Example usage:
            \\zig run tools/update_netbsd_libc.zig -- ~/Downloads/netbsd-src .
        ),
        .args = .{
            .netbsd_src_path = .{ .description = "Path to NetBSD source tree" },
            .zig_src_path = .{ .description = "Path to Zig source tree" },
        },
    };
};

const std = @import("std");
const Io = std.Io;

const exempt_files = [_][]const u8{
    // This file is maintained by a separate project and does not come from NetBSD.
    "abilists",
};

pub fn main(init: std.process.Init, args: Args) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const dest_dir_path = try std.fmt.allocPrint(arena, "{s}/lib/libc/netbsd", .{args.zig_src_path});

    var dest_dir = Io.Dir.cwd().openDir(io, dest_dir_path, .{ .iterate = true }) catch |err| {
        std.log.err("unable to open destination directory '{s}': {t}", .{ dest_dir_path, err });
        std.process.exit(1);
    };
    defer dest_dir.close(io);

    var netbsd_src_dir = try Io.Dir.cwd().openDir(io, args.netbsd_src_path, .{});
    defer netbsd_src_dir.close(io);

    // Copy updated files from upstream.
    {
        var walker = try dest_dir.walk(arena);
        defer walker.deinit();

        walk: while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.startsWith(u8, entry.basename, ".")) continue;
            for (exempt_files) |p| {
                if (std.mem.eql(u8, entry.path, p)) continue :walk;
            }

            std.log.info("updating '{s}/{s}' from '{s}/{s}'", .{
                dest_dir_path,        entry.path,
                args.netbsd_src_path, entry.path,
            });

            netbsd_src_dir.copyFile(entry.path, dest_dir, entry.path, io, .{}) catch |err| {
                std.log.warn("unable to copy '{s}/{s}' to '{s}/{s}': {t}", .{
                    args.netbsd_src_path, entry.path, dest_dir_path, entry.path, err,
                });
                if (err == error.FileNotFound) {
                    try dest_dir.deleteFile(io, entry.path);
                }
            };
        }
    }
}
