const std = @import("std");
const Io = std.Io;
const testing = std.testing;

const Context = struct {
    gpa: std.mem.Allocator,
    buf: std.ArrayList(u8),
    server: Server,
};

const Server = struct {
    io: Io,
    in: Io.Event,
    out: Io.Event,

    pub fn worker(s: *Server) Io.Cancelable!void {
        while (true) {
            try s.in.wait(s.io);
            s.in.reset();
            s.out.set(s.io);
        }
    }
};

test {
    var ctx: Context = .{
        .gpa = testing.allocator,
        .buf = .empty,
        .server = .{
            .io = testing.io,
            .in = .unset,
            .out = .unset,
        },
    };
    defer ctx.buf.deinit(testing.allocator);
    var worker = try testing.io.concurrent(Server.worker, .{&ctx.server});
    defer worker.cancel(testing.io) catch {};

    try testing.fuzz(&ctx, testOne, .{});
}

fn testOne(ctx: *Context, smith: *testing.Smith) !void {
    // The below checks that we are able to access the test thread's Allocator and Io
    // interfaces as well as our own.

    const len = smith.valueRangeLessThan(u16, 1, 1 << 15);
    try ctx.buf.resize(ctx.gpa, len);

    const local_buf = try testing.allocator.alloc(u8, 1000);
    testing.allocator.free(local_buf);

    var worker = testing.io.async(client, .{&ctx.server});
    try worker.await(testing.io);
}

fn client(s: *Server) Io.Cancelable!void {
    for (0..5) |_| {
        s.in.set(s.io);
        try s.out.wait(s.io);
        s.out.reset();
    }
}
