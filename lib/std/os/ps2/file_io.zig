//! Interface provided by the `FILEIO` `IOP` RPC server.

const std = @import("std");
const rpc = std.os.ps2.rpc;

/// Flags for `open`
pub const OpenFlags = packed struct(u32) {
    /// Access mode
    access: Access = .read_only,
    _2: u2 = 0,
    /// Return instead of blocking if supported by the backing device
    non_blocking: bool = false,
    _5: u3 = 0,
    /// Append to the file on every write
    append: bool = false,
    /// Create the file if it doesn't exist yet
    create: bool = false,
    /// Truncate the file to `0` bytes when opening it
    truncate: bool = false,
    /// Fail if the file already exists
    exclusive: bool = false,
    _12: u20 = 0,

    pub const Access = enum(u2) {
        read_only = 1,
        write_only = 2,
        read_write = 3,
    };
};

/// Reference position for `lseek` offsets
pub const Whence = enum(u32) {
    set = 0,
    cur = 1,
    end = 2,
};

/// RPC functions provided by the `FILEIO` server
const func = struct {
    const open: rpc.Function = .{
        .server = .file_io,
        .id = 0,
        .Args = OpenArgs,
        .Result = i32,
    };

    const close: rpc.Function = .{
        .server = .file_io,
        .id = 1,
        .Args = CloseArgs,
        .Result = i32,
    };

    const read: rpc.Function = .{
        .server = .file_io,
        .id = 2,
        .Args = ReadArgs,
        .Result = i32,
    };

    const write: rpc.Function = .{
        .server = .file_io,
        .id = 3,
        .Args = WriteArgs,
        .Result = i32,
    };

    const lseek: rpc.Function = .{
        .server = .file_io,
        .id = 4,
        .Args = LseekArgs,
        .Result = i32,
    };
};

const OpenArgs = extern struct {
    /// Open flags
    flags: OpenFlags,
    /// Device-prefixed path such as `host:file.txt`
    name: [255:0]u8,
};

const CloseArgs = extern struct {
    /// File to close
    fd: i32,
};

const ReadArgs = extern struct {
    /// File to read from
    fd: i32,
    /// `EE` address the `IOP` writes the `16` byte aligned part to
    ptr: u32,
    /// Number of bytes to read
    size: u32,
    /// `EE` address of a `ReadData` for the unaligned head and tail
    read_data: u32,
};

/// Unaligned head and tail of a read, which is sent separately
const ReadData = extern struct {
    head_size: u32,
    tail_size: u32,
    head_dst: u32,
    tail_dst: u32,
    head: [16]u8,
    tail: [16]u8,
};

const WriteArgs = extern struct {
    /// File to write to
    fd: i32,
    /// `EE` address the `IOP` pulls data from
    ptr: u32,
    /// Number of bytes to write
    size: u32,
    /// Number of bytes until `ptr` is `16` byte aligned
    mis: u32,
    /// Bytes covered by `mis`
    head: [16]u8,
};

const LseekArgs = extern struct {
    /// File to seek in
    fd: i32,
    /// Offset to seek to
    offset: i32,
    /// Determines how `offset` is interpreted
    whence: Whence,
};

comptime {
    std.debug.assert(@sizeOf(OpenArgs) == 260);
    std.debug.assert(@sizeOf(ReadArgs) == 16);
    std.debug.assert(@sizeOf(ReadData) == 48);
    std.debug.assert(@sizeOf(WriteArgs) == 32);
    std.debug.assert(@sizeOf(LseekArgs) == 12);
    std.debug.assert(@as(u32, @bitCast(OpenFlags{ .access = .write_only, .append = true, .create = true })) == 0x302);
}

/// Client bound to the `FILEIO` server
pub const Client = rpc.Client(.file_io);

pub const Error = error{
    FileNotFound,
    AccessDenied,
    PathAlreadyExists,
    NoDevice,
    NotDir,
    IsDir,
    ProcessFdQuotaExceeded,
    NoSpaceLeft,
    ReadOnlyFileSystem,
    NameTooLong,
    InputOutput,
    NotOpenForReading,
    InvalidArgument,
    Unexpected,
};

/// Converts a `FILEIO` status code to `Error` or a byte count
fn check(result: i32) Error!u32 {
    if (result >= 0) return @intCast(result);

    return switch (-result) {
        2 => error.FileNotFound,
        5 => error.InputOutput,
        9 => error.NotOpenForReading,
        13 => error.AccessDenied,
        17 => error.PathAlreadyExists,
        19 => error.NoDevice,
        20 => error.NotDir,
        21 => error.IsDir,
        22 => error.InvalidArgument,
        24 => error.ProcessFdQuotaExceeded,
        28 => error.NoSpaceLeft,
        30 => error.ReadOnlyFileSystem,
        91 => error.NameTooLong,

        else => error.Unexpected,
    };
}

/// Tries to open `path` (`path` is expected to be device-prefixed)
pub fn open(client: Client, path: []const u8, flags: OpenFlags) Error!i32 {
    if (path.len > 255) return error.NameTooLong;

    var name: [255:0]u8 = @splat(0);
    @memcpy(name[0..path.len], path);
    return @intCast(try check(client.callBlocking(func.open, .{
        .flags = flags,
        .name = name,
    })));
}

/// Closes `fd`
pub fn close(client: Client, fd: i32) Error!void {
    _ = try check(client.callBlocking(func.close, .{ .fd = fd }));
}

var read_buf: [4096]u8 align(64) = undefined;
var read_data: ReadData align(64) = undefined;

/// Reads at most `buf.len` bytes from `fd`
pub fn read(client: Client, fd: i32, buf: []u8) Error!usize {
    const bounce = std.os.ps2.uncached(&read_buf);

    var nr_read: usize = 0;
    while (nr_read < buf.len) {
        // Whole chunks of `16` bytes are read in `read_buf`, whilst reads below `16` bytes
        // are written to `read_data.head`.
        const left = buf.len - nr_read;
        const chunk: u32 = if (left < 16)
            @intCast(left)
        else
            @intCast(@min(left, read_buf.len) & ~@as(usize, 15));

        const n = try check(client.callBlocking(func.read, .{
            .fd = fd,
            .ptr = @intFromPtr(&read_buf),
            .size = chunk,
            .read_data = @intFromPtr(&read_data),
        }));

        const dst = buf[nr_read..][0..n];
        if (chunk < 16) {
            const head = &std.os.ps2.uncached(&read_data).head;
            for (dst, 0..) |*b, i| b.* = head[i];
        } else for (dst, 0..) |*b, i| b.* = bounce[i];

        nr_read += n;
        if (n < chunk) break;
    }

    return nr_read;
}

/// Writes `bytes` to `fd` and returns the amount of bytes written
pub fn write(client: Client, fd: i32, bytes: []const u8) Error!usize {
    const addr: u32 = @intFromPtr(bytes.ptr);
    const mis: u32 = @intCast(@min((16 - addr % 16) % 16, bytes.len));

    // The unaligned head has to be extracted and sent separately
    var head: [16]u8 = @splat(0);
    @memcpy(head[0..mis], bytes[0..mis]);
    return check(client.callBlocking(func.write, .{
        .fd = fd,
        .ptr = addr,
        .size = @intCast(bytes.len),
        .mis = mis,
        .head = head,
    }));
}

/// Seeks towards `offset` in `fd`, interpreted based on `whence`
pub fn lseek(client: Client, fd: i32, offset: i32, whence: Whence) Error!u32 {
    return check(client.callBlocking(func.lseek, .{
        .fd = fd,
        .offset = offset,
        .whence = whence,
    }));
}
