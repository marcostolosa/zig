//! Fully-featured `Io` implementation for the `PS2` based on `SIF RPC`. Split off from the
//! basic `debug_io` to reduce code size for programs that don't require file access.

const SifIo = @This();

const std = @import("std");
const Io = std.Io;

const debug_io = std.os.ps2.debug_io;
const file_io = std.os.ps2.file_io;

const vtable: Io.VTable = blk: {
    var v = debug_io.vtable;

    v.operate = &operate;
    v.dirCreateFile = &dirCreateFile;
    v.dirOpenFile = &dirOpenFile;
    v.fileClose = &fileClose;
    v.fileReadPositional = &fileReadPositional;
    v.fileWritePositional = &fileWritePositional;
    v.fileSeekTo = &fileSeekTo;
    v.fileSeekBy = &fileSeekBy;
    v.fileLength = &fileLength;
    v.fileStat = &fileStat;
    v.processExecutablePath = &processExecutablePath;
    v.processCurrentPath = &processCurrentPath;

    break :blk v;
};

/// `FILEIO` RPC client bound on first file access
client: ?file_io.Client = null,

pub fn io(self: *SifIo) Io {
    return .{
        .userdata = self,
        .vtable = &vtable,
    };
}

/// Binds to the `FILEIO` RPC server on first use
fn fileIoClient(self: *SifIo) error{NoDevice}!file_io.Client {
    if (self.client) |client| return client;

    const client = std.os.ps2.rpc.Rpc.acquire().bind(.file_io) catch return error.NoDevice;
    self.client = client;
    return client;
}

/// Opens or creates `sub_path` relative to `dir`
fn open(
    self: *SifIo,
    dir: Io.Dir,
    sub_path: []const u8,
    flags: file_io.OpenFlags,
) Io.File.OpenError!Io.File {
    // `FILEIO` does not support opening directories other than the image's own
    if (dir.handle != std.posix.AT.FDCWD) return error.Unexpected;

    var buf: [255]u8 = undefined;
    const path = try convertPath(&buf, sub_path);
    const client = try self.fileIoClient();

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

/// Reads into the first non-empty buffer in `data`
fn readStreaming(
    self: *SifIo,
    handle: Io.File.Handle,
    data: []const []u8,
) Io.Operation.FileReadStreaming.Error!usize {
    const client = self.client orelse return error.NotOpenForReading;

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
    self: *SifIo,
    handle: Io.File.Handle,
    hdr: []const u8,
    data: []const []const u8,
    splat: usize,
) Io.Operation.FileWriteStreaming.Error!usize {
    const client = self.client orelse return error.NotOpenForWriting;
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
    self: *SifIo,
    handle: Io.File.Handle,
    off: i64,
    whence: file_io.Whence,
) error{ Unseekable, Unexpected }!u32 {
    if (!isFileIo(handle)) return error.Unseekable;

    const client = self.client orelse return error.Unseekable;
    // Truncate as `FILEIO` expects `32` bit offsets
    const truncated_off = std.math.cast(i32, off) orelse return error.Unseekable;
    return file_io.lseek(client, handle, truncated_off, whence) catch error.Unexpected;
}

fn dirCreateFile(
    userdata: ?*anyopaque,
    dir: Io.Dir,
    sub_path: []const u8,
    opt: Io.Dir.CreateFileOptions,
) Io.File.OpenError!Io.File {
    if (opt.lock != .none) return error.FileLocksUnsupported;

    const self = fromUserdata(userdata);

    // On `PCSX2`, `host:` ignores `O_EXCL`, so check for an existing file first
    if (opt.exclusive) {
        if (self.open(dir, sub_path, .{ .access = .read_only })) |exists| {
            fileClose(userdata, &.{exists});
            return error.PathAlreadyExists;
        } else |_| {}
    }

    return self.open(dir, sub_path, .{
        .access = if (opt.read) .read_write else .write_only,
        .create = true,
        .truncate = opt.truncate,
        .exclusive = opt.exclusive,
    });
}

fn dirOpenFile(
    userdata: ?*anyopaque,
    dir: Io.Dir,
    sub_path: []const u8,
    opt: Io.Dir.OpenFileOptions,
) Io.File.OpenError!Io.File {
    return fromUserdata(userdata).open(dir, sub_path, .{ .access = switch (opt.mode) {
        .read_only => .read_only,
        .write_only => .write_only,
        .read_write => .read_write,
    } });
}

fn fileClose(userdata: ?*anyopaque, files: []const Io.File) void {
    const client = fromUserdata(userdata).client orelse return;

    for (files) |file| if (isFileIo(file.handle)) file_io.close(client, file.handle) catch {};
}

fn operate(userdata: ?*anyopaque, op: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const self = fromUserdata(userdata);

    switch (op) {
        .file_read_streaming => |r| if (isFileIo(r.file.handle)) {
            return .{ .file_read_streaming = self.readStreaming(r.file.handle, r.data) };
        },
        .file_write_streaming => |w| if (isFileIo(w.file.handle)) {
            return .{ .file_write_streaming = self.writeStreaming(
                w.file.handle,
                w.header,
                w.data,
                w.splat,
            ) };
        },

        else => {},
    }

    // Forward to `debug_io` for any non-file access
    return debug_io.vtable.operate(userdata, op);
}

fn fileReadPositional(
    userdata: ?*anyopaque,
    file: Io.File,
    data: []const []u8,
    off: u64,
) Io.File.ReadPositionalError!usize {
    const self = fromUserdata(userdata);

    _ = try self.seekFile(
        file.handle,
        std.math.cast(i64, off) orelse return error.Unseekable,
        .set,
    );
    return self.readStreaming(file.handle, data) catch |err| switch (err) {
        error.EndOfStream => 0,
        error.ConnectionResetByPeer, error.SocketUnconnected => error.Unexpected,

        else => |e| e,
    };
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file: Io.File,
    hdr: []const u8,
    data: []const []const u8,
    splat: usize,
    off: u64,
) Io.File.WritePositionalError!usize {
    const self = fromUserdata(userdata);

    _ = try self.seekFile(
        file.handle,
        std.math.cast(i64, off) orelse return error.Unseekable,
        .set,
    );
    return self.writeStreaming(file.handle, hdr, data, splat);
}

fn fileSeekTo(userdata: ?*anyopaque, file: Io.File, abs_off: u64) Io.File.SeekError!void {
    _ = try fromUserdata(userdata).seekFile(
        file.handle,
        std.math.cast(i64, abs_off) orelse return error.Unseekable,
        .set,
    );
}

fn fileSeekBy(userdata: ?*anyopaque, file: Io.File, rel_off: i64) Io.File.SeekError!void {
    _ = try fromUserdata(userdata).seekFile(file.handle, rel_off, .cur);
}

/// Returns the file's length, found by seeking to the end and back
fn fileLength(userdata: ?*anyopaque, file: Io.File) Io.File.LengthError!u64 {
    const self = fromUserdata(userdata);

    const pos = self.seekFile(file.handle, 0, .cur) catch |err| return switch (err) {
        error.Unseekable => error.Streaming,
        error.Unexpected => error.Unexpected,
    };
    const end = self.seekFile(file.handle, 0, .end) catch return error.Unexpected;
    _ = self.seekFile(file.handle, pos, .set) catch return error.Unexpected;

    return end;
}

/// Reports `file`'s size and kind. `FILEIO` does not support a reliable `getstat` so times
/// are zero.
fn fileStat(userdata: ?*anyopaque, file: Io.File) Io.File.StatError!Io.File.Stat {
    const size: u64, const kind: Io.File.Kind = if (isFileIo(file.handle))
        .{ try fileLength(userdata, file), .file }
    else
        .{ 0, .character_device };

    return .{
        .inode = {},
        .nlink = 0,
        .size = size,
        .permissions = .default_file,
        .kind = kind,
        .atime = null,
        .mtime = .zero,
        .ctime = .zero,
        .block_size = 1,
    };
}

/// Returns the device-prefixed path of the program's image (e.g. `host:foo.elf`)
fn processExecutablePath(_: ?*anyopaque, buf: []u8) std.process.ExecutablePathError!usize {
    const args = std.os.ps2.programArgs();
    if (args.len == 0) return error.OperationUnsupported;

    const path = std.mem.span(args[0]);
    if (path.len > buf.len) return error.NameTooLong;

    @memcpy(buf[0..path.len], path);
    return path.len;
}

/// Returns the current program's image directory
fn processCurrentPath(_: ?*anyopaque, buf: []u8) std.process.CurrentPathError!usize {
    const dir = std.os.ps2.programDir();
    if (dir.len > buf.len) return error.NameTooLong;

    @memcpy(buf[0..dir.len], dir);
    return dir.len;
}

/// Converts `path` into a path `FILEIO` understands. Device-prefixed paths (e.g. `cdrom0:\\X;1`)
/// are returned as they are, while others are adjusted to be relative to the program's image
/// directory.
fn convertPath(buf: *[255]u8, path: []const u8) error{NameTooLong}![]const u8 {
    if (std.mem.indexOfScalar(u8, path, ':') != null) return path;

    const dir = std.os.ps2.programDir();
    if (dir.len + path.len > buf.len) return error.NameTooLong;

    @memcpy(buf[0..dir.len], dir);
    @memcpy(buf[dir.len..][0..path.len], path);
    return buf[0 .. dir.len + path.len];
}

/// Determines whether `handle` is a proper file handle instead of referring to the console
fn isFileIo(handle: Io.File.Handle) bool {
    return handle > std.posix.STDERR_FILENO;
}

fn fromUserdata(userdata: ?*anyopaque) *SifIo {
    return @ptrCast(@alignCast(userdata.?));
}
