const std = @import("std");
const Io = std.Io;

const sio = std.os.ps2.sio;
const file_io = std.os.ps2.file_io;

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

/// `Io` implementation for `std.debug`. Provides access to the `EE`'s serial `I/O` console,
/// a monotonic clock and a randoms source. It does not implement file access to save on
/// code size for programs that do no need it.
pub const debug_io: Io = .{ .userdata = null, .vtable = &debug_vtable };
const debug_vtable: Io.VTable = blk: {
    var vtable = Io.failing.vtable.*;

    vtable.swapCancelProtection = &swapCancelProtection;
    vtable.lockStderr = &lockStderr;
    vtable.tryLockStderr = &tryLockStderr;
    vtable.unlockStderr = &unlockStderr;
    vtable.operate = &operate;
    vtable.fileWritePositional = &serialFileWritePositional;

    vtable.now = &now;
    vtable.clockResolution = &clockResolution;
    vtable.sleep = &sleep;
    vtable.random = &random;

    break :blk vtable;
};

/// `Io` implementation for juicy-main programs that require file access
pub const io: Io = .{ .userdata = null, .vtable = &io_vtable };
const io_vtable: Io.VTable = blk: {
    var vtable = debug_vtable;

    vtable.operate = &fileOperate;
    vtable.dirCreateFile = &dirCreateFile;
    vtable.dirOpenFile = &dirOpenFile;
    vtable.fileClose = &fileClose;
    vtable.fileReadPositional = &fileReadPositional;
    vtable.fileWritePositional = &fileWritePositional;
    vtable.fileSeekTo = &fileSeekTo;
    vtable.fileSeekBy = &fileSeekBy;
    vtable.fileLength = &fileLength;

    break :blk vtable;
};

var stderr_writer: Io.File.Writer = .initStreaming(.stderr(), debug_io, &.{});

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

fn serialFileWritePositional(
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

var file_io_client: ?file_io.Client = null;

/// Initialize our `FILEIO` client via RPC
fn fileIoClient() error{NoDevice}!file_io.Client {
    if (file_io_client) |client| return client;

    const client = std.os.ps2.rpc.Rpc.acquire().bind(.file_io) catch return error.NoDevice;
    file_io_client = client;
    return client;
}

/// Determines whether `handle` is a proper file handle instead of referring to the console
fn isFileIo(handle: Io.File.Handle) bool {
    return handle > std.posix.STDERR_FILENO;
}

/// Converts `path` into a path `FILEIO` understands. Device-prefixed paths (e.g. `cdrom0:\\X;1`)
/// are returned as they are, while others are adjusted to be relative to the program's image
/// directory.
fn convertPath(buf: *[255]u8, path: []const u8) error{NameTooLong}![]const u8 {
    if (std.mem.indexOfScalar(u8, path, ':') != null) return path;

    const args = std.os.ps2.programArgs();
    const image = if (args.len > 0) std.mem.span(args[0]) else "";
    // The program's image directory ends at its last `:`, `/` or `\\`
    const dir = image[0..if (std.mem.lastIndexOfAny(u8, image, ":/\\")) |i| i + 1 else 0];
    if (dir.len + path.len > buf.len) return error.NameTooLong;

    @memcpy(buf[0..dir.len], dir);
    @memcpy(buf[dir.len..][0..path.len], path);
    return buf[0 .. dir.len + path.len];
}

fn dirCreateFile(
    _: ?*anyopaque,
    dir: Io.Dir,
    sub_path: []const u8,
    opt: Io.Dir.CreateFileOptions,
) Io.File.OpenError!Io.File {
    if (opt.lock != .none) return error.FileLocksUnsupported;

    // On `PCSX2`, `host:` ignores `O_EXCL`, so check for an existing file first
    if (opt.exclusive) {
        if (open(dir, sub_path, .{ .access = .read_only })) |exists| {
            fileClose(null, &.{exists});
            return error.PathAlreadyExists;
        } else |_| {}
    }

    return open(dir, sub_path, .{
        .access = if (opt.read) .read_write else .write_only,
        .create = true,
        .truncate = opt.truncate,
        .exclusive = opt.exclusive,
    });
}

fn dirOpenFile(
    _: ?*anyopaque,
    dir: Io.Dir,
    sub_path: []const u8,
    opt: Io.Dir.OpenFileOptions,
) Io.File.OpenError!Io.File {
    return open(dir, sub_path, .{ .access = switch (opt.mode) {
        .read_only => .read_only,
        .write_only => .write_only,
        .read_write => .read_write,
    } });
}

/// Opens or creates `sub_path` relative to `dir`
fn open(
    dir: Io.Dir,
    sub_path: []const u8,
    flags: file_io.OpenFlags,
) Io.File.OpenError!Io.File {
    // `FILEIO` does not support opening directories other than the image's own
    if (dir.handle != std.posix.AT.FDCWD) return error.Unexpected;

    var buf: [255]u8 = undefined;
    const path = try convertPath(&buf, sub_path);
    const client = try fileIoClient();

    const fd = file_io.open(client, path, flags) catch |err| return switch (err) {
        error.FileNotFound,
        error.AccessDenied,
        error.PathAlreadyExists,
        error.NoDevice,
        error.NotDir,
        error.IsDir,
        error.ProcessFdQuotaExceeded,
        error.NoSpaceLeft,
        error.ReadOnlyFileSystem,
        error.NameTooLong,
        => |e| e,

        error.InputOutput => error.FileNotFound,

        error.NotOpenForReading,
        error.InvalidArgument,
        error.Unexpected,
        => error.Unexpected,
    };

    return .{ .handle = fd, .flags = .{ .nonblocking = false } };
}

fn fileClose(_: ?*anyopaque, files: []const Io.File) void {
    const client = file_io_client orelse return;

    for (files) |file| if (isFileIo(file.handle)) file_io.close(client, file.handle) catch {};
}

// Handles actual file access via `FILEIO` and forwards to `debug_io` otherwise
fn fileOperate(data: ?*anyopaque, op: Io.Operation) Io.Cancelable!Io.Operation.Result {
    switch (op) {
        .file_read_streaming => |r| if (isFileIo(r.file.handle)) {
            return .{ .file_read_streaming = readStreaming(r.file.handle, r.data) };
        },
        .file_write_streaming => |w| if (isFileIo(w.file.handle)) {
            return .{ .file_write_streaming = writeStreaming(
                w.file.handle,
                w.header,
                w.data,
                w.splat,
            ) };
        },

        else => {},
    }

    return operate(data, op);
}

/// Reads into the first non-empty buffer in `data`
fn readStreaming(
    handle: Io.File.Handle,
    data: []const []u8,
) Io.Operation.FileReadStreaming.Error!usize {
    const client = file_io_client orelse return error.NotOpenForReading;

    for (data) |buf| {
        if (buf.len == 0) continue;

        const n = file_io.read(client, handle, buf) catch |err| return switch (err) {
            error.NotOpenForReading,
            error.IsDir,
            error.AccessDenied,
            error.InputOutput,
            => |e| e,

            else => error.Unexpected,
        };
        return if (n == 0) error.EndOfStream else n;
    }

    return 0;
}

/// Writes the first non-empty buffer of `hdr` or `data`. `data`'s last buffer counts
/// `splat` times. The rest is written by `Io.Writer` invoking us again.
fn writeStreaming(
    handle: Io.File.Handle,
    hdr: []const u8,
    data: []const []const u8,
    splat: usize,
) Io.Operation.FileWriteStreaming.Error!usize {
    const client = file_io_client orelse return error.NotOpenForWriting;
    const bytes = if (hdr.len != 0) hdr else for (data, 0..) |buf, i| {
        if (buf.len != 0 and (i + 1 < data.len or splat != 0)) break buf;
    } else return 0;

    const n = file_io.write(client, handle, bytes) catch |err| return switch (err) {
        error.NoSpaceLeft,
        error.InputOutput,
        error.AccessDenied,
        error.NoDevice,
        => |e| e,

        error.NotOpenForReading => error.NotOpenForWriting,

        else => error.Unexpected,
    };
    // `FILEIO` returns `0` bytes written if the caller tried to write to a read-only file
    return if (n == 0) error.NotOpenForWriting else n;
}

/// Moves `handle`'s file position to `off`, interpreted based on `whence`. Positional reads
/// and writes trip this too, so subsequent streaming accesses are impacted.
fn seekFile(
    handle: Io.File.Handle,
    off: i64,
    whence: file_io.Whence,
) error{ Unseekable, Unexpected }!u32 {
    if (!isFileIo(handle)) return error.Unseekable;

    const client = file_io_client orelse return error.Unseekable;
    // Truncate as `FILEIO` expects `32` bit offsets
    const truncated_off = std.math.cast(i32, off) orelse return error.Unseekable;
    return file_io.lseek(client, handle, truncated_off, whence) catch error.Unexpected;
}

fn fileReadPositional(
    _: ?*anyopaque,
    file: Io.File,
    data: []const []u8,
    off: u64,
) Io.File.ReadPositionalError!usize {
    _ = try seekFile(file.handle, std.math.cast(i64, off) orelse return error.Unseekable, .set);
    return readStreaming(file.handle, data) catch |err| switch (err) {
        error.EndOfStream => 0,
        error.ConnectionResetByPeer, error.SocketUnconnected => error.Unexpected,

        else => |e| e,
    };
}

fn fileWritePositional(
    _: ?*anyopaque,
    file: Io.File,
    hdr: []const u8,
    data: []const []const u8,
    splat: usize,
    off: u64,
) Io.File.WritePositionalError!usize {
    _ = try seekFile(file.handle, std.math.cast(i64, off) orelse return error.Unseekable, .set);
    return writeStreaming(file.handle, hdr, data, splat);
}

fn fileSeekTo(_: ?*anyopaque, file: Io.File, abs_off: u64) Io.File.SeekError!void {
    _ = try seekFile(file.handle, std.math.cast(i64, abs_off) orelse return error.Unseekable, .set);
}

fn fileSeekBy(_: ?*anyopaque, file: Io.File, rel_off: i64) Io.File.SeekError!void {
    _ = try seekFile(file.handle, rel_off, .cur);
}

/// Returns the file's length, found by seeking to the end and back
fn fileLength(_: ?*anyopaque, file: Io.File) Io.File.LengthError!u64 {
    const pos = seekFile(file.handle, 0, .cur) catch |err| return switch (err) {
        error.Unseekable => error.Streaming,
        error.Unexpected => error.Unexpected,
    };
    const end = seekFile(file.handle, 0, .end) catch return error.Unexpected;
    _ = seekFile(file.handle, pos, .set) catch return error.Unexpected;
    return end;
}
