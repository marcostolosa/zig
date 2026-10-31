const std = @import("std");
const Io = std.Io;

const sio = std.os.ps2.sio;

pub const io: Io = .{ .userdata = null, .vtable = &io_vtable };
const io_vtable: Io.VTable = vtable: {
    var vtable = Io.failing.vtable.*;

    vtable.swapCancelProtection = &swapCancelProtection;
    vtable.lockStderr = &lockStderr;
    vtable.tryLockStderr = &tryLockStderr;
    vtable.unlockStderr = &unlockStderr;
    vtable.operate = &operate;
    vtable.fileWritePositional = &fileWritePositional;

    break :vtable vtable;
};

var stderr_writer: Io.File.Writer = .initStreaming(.stderr(), io, &.{});

fn swapCancelProtection(_: ?*anyopaque, _: Io.CancelProtection) Io.CancelProtection {
    return .unblocked;
}

fn lockStderr(_: ?*anyopaque, _: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    return .{
        .file_writer = &stderr_writer,
        .terminal_mode = .no_color,
    };
}

fn tryLockStderr(data: ?*anyopaque, mode: ?Io.Terminal.Mode) Io.Cancelable!?Io.LockedStderr {
    return try lockStderr(data, mode);
}

fn unlockStderr(_: ?*anyopaque) void {
    stderr_writer.interface.flush() catch {};
    stderr_writer.interface.buffer = &.{};
}

fn operate(data: ?*anyopaque, op: Io.Operation) Io.Cancelable!Io.Operation.Result {
    switch (op) {
        .file_write_streaming => |wr| switch (wr.file.handle) {
            std.posix.STDOUT_FILENO, std.posix.STDERR_FILENO => {
                return .{ .file_write_streaming = sioWrite(wr.header, wr.data, wr.splat) };
            },

            else => {},
        },

        else => {},
    }

    return Io.failingOperate(data, op);
}

fn fileWritePositional(
    _: ?*anyopaque,
    _: Io.File,
    _: []const u8,
    _: []const []const u8,
    _: usize,
    _: u64,
) Io.File.WritePositionalError!usize {
    // The `EE`'s serial `I/O` console does not support positional writes
    return error.Unseekable;
}

fn sioWrite(hdr: []const u8, data: []const []const u8, splat: usize) usize {
    sio.writeAll(hdr);
    if (data.len == 0) return hdr.len;

    var n = hdr.len;
    for (data[0 .. data.len - 1]) |bytes| {
        sio.writeAll(bytes);
        n += bytes.len;
    }

    const last = data[data.len - 1];
    for (0..splat) |_| sio.writeAll(last);
    return n + last.len * splat;
}
