const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const child_exe = args[1];

    const id = child: {
        var child = try std.process.spawn(io, .{ .argv = &.{child_exe} });
        defer child.kill(init.io);

        var wait_future = try init.io.concurrent(std.process.Child.wait, .{ &child, init.io });
        defer _ = wait_future.cancel(init.io) catch {};

        break :child child.id.?;
    };

    switch (builtin.target.os.tag) {
        .windows => {
            // TODO
        },
        else => {
            var status: if (builtin.link_libc) c_int else i32 = undefined;
            switch (std.posix.errno(std.posix.system.waitpid(id, &status, 0))) {
                .SUCCESS => return error.ZombieChild,
                .CHILD => {}, // already terminated/killed
                else => |err| return std.posix.unexpectedErrno(err),
            }
        },
    }
}
