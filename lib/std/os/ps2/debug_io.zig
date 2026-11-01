//! `Io` implementation for `std.debug`. Provides access to the `EE`'s serial `I/O` console,
//! a monotonic clock and a random source. It does not implement file access to save on
//! code size for programs that do no need it.

const std = @import("std");
const Io = std.Io;

const sio = std.os.ps2.sio;
const file_io = std.os.ps2.file_io;

/// Stateless `Io` instance with a minimal vtable
pub const io: Io = .{ .userdata = null, .vtable = &vtable };
pub const vtable: Io.VTable = blk: {
    var v = Io.failing.vtable.*;

    v.swapCancelProtection = &swapCancelProtection;
    v.lockStderr = &lockStderr;
    v.tryLockStderr = &tryLockStderr;
    v.unlockStderr = &unlockStderr;
    v.operate = &operate;
    v.fileWritePositional = &fileWritePositional;

    v.now = &now;
    v.clockResolution = &clockResolution;
    v.sleep = &sleep;
    v.random = &random;

    break :blk v;
};

var stderr_writer: Io.File.Writer = .initStreaming(.stderr(), io, &.{});

fn swapCancelProtection(_: ?*anyopaque, _: Io.CancelProtection) Io.CancelProtection {
    // Unapplicable to the `PS2`
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
    // For `debug_io` we only support streaming writes to `stdout` or `stderr`
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

/// Returns the current time
fn now(_: ?*anyopaque, clk: Io.Clock) Io.Timestamp {
    return switch (clk) {
        // No `RTC` for now, as it's owned by the `CDVD` controller which sits behind the `IOP`
        .real => .zero,

        else => .{ .nanoseconds = clock.nanos() },
    };
}

/// Computes the clock's resolution
fn clockResolution(_: ?*anyopaque, clk: Io.Clock) Io.Clock.ResolutionError!Io.Duration {
    return switch (clk) {
        .real => error.ClockUnavailable,

        // One `COP0` tick is around `3.39 ns` (`15625 / 4608`)
        else => .{ .nanoseconds = 4 },
    };
}

/// Sleeps according to `timeout`
fn sleep(_: ?*anyopaque, timeout: Io.Timeout) Io.Cancelable!void {
    const deadline: i96 = switch (timeout) {
        .duration => |d| clock.nanos() + d.raw.nanoseconds,
        .deadline => |t| if (t.clock == .real)
            clock.nanos() + t.raw.nanoseconds
        else
            t.raw.nanoseconds,

        .none => while (true) {},
    };

    // Just busy loop as there's nobody to yield to
    while (clock.nanos() < deadline) {}
}

var rng_state: u32 = 0;

/// Cryptographically-insecure `PRNG` implemented via a `32` bit xor-shift seeded once
/// from the `COP0` counter.
fn random(_: ?*anyopaque, buf: []u8) void {
    // An initial state of `0` does not work with xor-shift
    if (rng_state == 0) rng_state = clock.count() | 1;

    for (buf) |*b| {
        rng_state ^= rng_state << 13;
        rng_state ^= rng_state >> 17;
        rng_state ^= rng_state << 5;

        b.* = @truncate(rng_state);
    }
}

/// Writes `hdr`, followed by `data` with its last element written `splat` times to the `EE`
/// serial `I/O` console.
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

/// Monotonic clock for the `EE`. Note that the counter wraps every `~14.6 s` so if nothing
/// reads it for longer than that, the clock will silently lose time.
const clock = struct {
    var last: u32 = 0;
    var carry: u32 = 0;
    var ns: u64 = 0;

    /// Reads the monotonic counter from `COP0`
    fn count() u32 {
        return asm volatile (
            \\ mfc0 %[count], $9
            : [count] "=r" (-> u32),
        );
    }

    fn nanos() u64 {
        const cnt = count();
        const delta = cnt -% last;
        last = cnt;

        // The `COP0` counter increases by one every `EE` clock cycle,
        // which is `294.912 MHz`. To avoid expensive soft-float math
        // and clock drift, we express it as an exact fraction of one
        // tick per `15625 / 4608 ns`.
        const rem = delta % 4608 + carry;
        ns += @as(u64, delta / 4608 + rem / 4608) * 15625;
        carry = rem % 4608;

        return ns + carry * 15625 / 4608;
    }
};
