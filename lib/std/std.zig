pub const AutoHashMap = hash_map.AutoHashMap;
pub const AutoHashMapUnmanaged = hash_map.AutoHashMapUnmanaged;
pub const BitStack = @import("BitStack.zig");
pub const Build = @import("Build.zig");
pub const BufMap = @import("buf_map.zig").BufMap;
pub const BufSet = @import("buf_set.zig").BufSet;
pub const StaticStringMap = static_string_map.StaticStringMap;
pub const StaticStringMapWithEql = static_string_map.StaticStringMapWithEql;
pub const Deque = @import("deque.zig").Deque;
pub const DoublyLinkedList = @import("DoublyLinkedList.zig");
pub const DynLib = @import("dynamic_library.zig").DynLib;
/// Deprecated: use `bit_set.DynamicManaged`.
pub const DynamicBitSet = bit_set.DynamicBitSet;
/// Deprecated: use `bit_set.Dynamic`.
pub const DynamicBitSetUnmanaged = bit_set.DynamicBitSetUnmanaged;
pub const EnumArray = enums.EnumArray;
pub const EnumMap = enums.EnumMap;
pub const EnumSet = enums.EnumSet;
pub const HashMap = hash_map.HashMap;
pub const HashMapUnmanaged = hash_map.HashMapUnmanaged;
pub const Io = @import("Io.zig");
pub const MultiArrayList = @import("multi_array_list.zig").MultiArrayList;
pub const PriorityQueue = @import("priority_queue.zig").PriorityQueue;
pub const PriorityDequeue = @import("priority_dequeue.zig").PriorityDequeue;
pub const Progress = @import("Progress.zig");
pub const Random = @import("Random.zig");
pub const SemanticVersion = @import("SemanticVersion.zig");
pub const SinglyLinkedList = @import("SinglyLinkedList.zig");
/// Deprecated: use `bit_set.Static`.
pub const StaticBitSet = bit_set.StaticBitSet;
pub const StringHashMap = hash_map.StringHashMap;
pub const StringHashMapUnmanaged = hash_map.StringHashMapUnmanaged;
pub const Target = @import("Target.zig");
pub const Thread = @import("Thread.zig");
pub const Treap = @import("treap.zig").Treap;
pub const Tz = tz.Tz;
pub const Uri = @import("Uri.zig");

/// Deprecated; use `array_hash_map.Custom`.
pub const ArrayHashMapUnmanaged = array_hash_map.Custom;
/// Deprecated; use `array_hash_map.Auto`.
pub const AutoArrayHashMapUnmanaged = array_hash_map.Auto;
/// Deprecated; use `array_hash_map.String`.
pub const StringArrayHashMapUnmanaged = array_hash_map.String;

/// A contiguous, growable list of items in memory. This is a wrapper around a
/// slice of `T` values.
///
/// The same allocator must be used throughout its entire lifetime. Initialize
/// directly with `empty` or `initCapacity`, and deinitialize with `deinit` or
/// `toOwnedSlice`.
pub fn ArrayList(comptime T: type) type {
    return array_list.Aligned(T, null);
}
pub const array_list = @import("array_list.zig");

pub const array_hash_map = @import("array_hash_map.zig");
pub const atomic = @import("atomic.zig");
pub const base64 = @import("base64.zig");
pub const bit_set = @import("bit_set.zig");
/// Deprecated; use `lang`.
///
/// To be removed after Zig 0.17.0.
pub const builtin = lang;
pub const lang = @import("lang.zig");
pub const c = @import("c.zig");
pub const coff = @import("coff.zig");
pub const compress = @import("compress.zig");
pub const static_string_map = @import("static_string_map.zig");
pub const crypto = @import("crypto.zig");
pub const debug = @import("debug.zig");
pub const dwarf = @import("dwarf.zig");
pub const elf = @import("elf.zig");
pub const enums = @import("enums.zig");
pub const fmt = @import("fmt.zig");
pub const fs = @import("fs.zig");
pub const spirv = @import("spirv.zig");
pub const hash = @import("hash.zig");
pub const hash_map = @import("hash_map.zig");
pub const heap = @import("heap.zig");
pub const http = @import("http.zig");
pub const json = @import("json.zig");
pub const leb = @import("leb128.zig");
pub const log = @import("log.zig");
pub const macho = @import("macho.zig");
pub const math = @import("math.zig");
pub const mem = @import("mem.zig");
pub const meta = @import("meta.zig");
pub const os = @import("os.zig");
pub const pdb = @import("pdb.zig");
pub const pie = @import("pie.zig");
pub const posix = @import("posix.zig");
pub const process = @import("process.zig");
pub const sort = @import("sort.zig");
pub const simd = @import("simd.zig");
pub const ascii = @import("ascii.zig");
pub const tar = @import("tar.zig");
pub const testing = @import("testing.zig");
pub const time = @import("time.zig");
pub const tz = @import("tz.zig");
pub const unicode = @import("unicode.zig");
pub const valgrind = @import("valgrind.zig");
pub const wasm = @import("wasm.zig");
pub const zig = @import("zig.zig");
pub const zip = @import("zip.zig");
pub const zon = @import("zon.zig");
pub const start = @import("start.zig");

const root = @import("root");

/// Compile-time known OS settings overridable by the root source file.
pub const os_options: Options.OperatingSystem = if (@hasDecl(root, "std_os_options")) root.std_os_options else .{};

/// Compile-time known settings overridable by the root source file.
pub const options: Options = if (@hasDecl(root, "std_options")) root.std_options else .{};

pub const Options = struct {
    /// Provides overrides for underlying system-specific APIs without replacing them.
    pub const OperatingSystem = struct {
        /// Will be evaluated automagically by `std`
        start: ?type = null,

        /// `std.debug` overrides.
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const SelfInfo: type;
        /// pub fn printLineFromFile(io: Io, writer: *Writer, source_location: SourceLocation) !void;
        /// pub fn getDebugInfoAllocator() std.mem.Allocator;
        /// pub fn defaultPanic(msg: []const u8, first_trace_addr: ?usize) noreturn;
        /// ```
        debug: ?type = null,

        /// `std.Thread` overrides.
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const Id: type;
        /// pub const ThreadHandle: type;
        /// pub fn getCurrentId() Id;
        /// pub fn getCpuCount() anyerror!usize;
        /// pub fn yield() std.Thread.YieldError!void;
        /// pub fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) std.Thread.SpawnError!@This();
        /// pub fn getHandle(impl: @This()) ThreadHandle;
        /// pub fn detach(impl: @This()) void;
        /// pub fn join(impl: @This()) void;
        /// ```
        Thread: ?type = null,

        /// `std.heap` overrides.
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const page_size_min: usize;
        /// pub const page_size_max: usize;
        /// pub const page_allocator: std.mem.Allocator;
        /// pub fn queryPageSize() usize;
        /// ```
        heap: ?type = null,

        /// `std.process` overrides.
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const allocator: std.mem.Allocator;
        /// pub const io: std.Io;
        /// ```
        process: ?type = null,

        /// `std.Io` overrides.
        ///
        /// This type may expose the following declarations:
        /// ```
        /// pub const VTable: type;
        /// pub const LockedStderr: type;
        ///
        /// // All declarations must be present if overridden
        /// pub const Terminal: type = struct {
        ///     pub const Mode: type;
        /// };
        ///
        /// // All declarations must be present if overridden
        /// pub const File: type = struct {
        ///     pub const Flags: type;
        ///     pub const Handle: type;
        ///     pub const Permissions: type;
        ///     pub fn stdin() std.Io.File;
        ///     pub fn stdout() std.Io.File;
        ///     pub fn stderr() std.Io.File;
        /// };
        ///
        /// // All declarations must be present if overridden
        /// pub const Dir: type = struct {
        ///     pub const max_path_bytes: usize;
        ///     pub const max_name_bytes: usize;
        ///     pub const Handle: type;
        ///
        ///     pub fn cwd() std.Io.Dir;
        ///
        ///     pub const Reader: type = struct {
        ///         pub const min_buffer_len: usize;
        ///     };
        /// };
        ///
        /// // All declarations must be present if overridden
        /// pub const net: type = struct {
        ///     pub const has_unix_sockets: bool;
        ///     pub const cmsg_align: usize;
        ///
        ///     pub const Socket: type = struct {
        ///         pub const Handle: type;
        ///     };
        /// };
        /// ```
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const Operation: type = struct {
        ///     pub const DeviceIoControl: type;
        /// };
        /// ```
        Io: ?type = null,

        /// `std.testing` overrides.
        ///
        /// This type must expose the following declarations:
        /// ```
        /// pub const can_replace: bool;
        /// pub const can_spawn: bool;
        /// pub fn getBaseAddress() usize;
        /// pub fn totalSystemMemory() std.process.TotalSystemMemoryError!usize;
        /// pub fn abort() void;
        /// pub fn exit() void;
        /// pub fn lockMemory(memory: []align(std.heap.page_size_min) const u8, options: std.process.LockMemoryOptions) std.process.LockMemoryError!void;
        /// pub fn unlockMemory(memory: []align(std.heap.page_size_min) const u8) std.process.UnlockMemoryError!void;
        /// pub fn lockMemoryAll(options: std.process.LockMemoryAllOptions) std.process.LockMemoryError!void;
        /// pub fn unlockMemoryAll() std.process.UnlockMemoryError!void;
        /// pub fn protectMemory(memory: []align(std.heap.page_size_min) u8, protection: std.process.MemoryProtection) std.process.ProtectMemoryError!void;
        /// ```
        testing: ?type = null,
    };

    enable_segfault_handler: bool = debug.default_enable_segfault_handler,

    /// If set, `std.start` and `std.Thread` will configure an per-thread alternative signal stack
    /// of this size. Importantly, if `enable_segfault_handler` is set, the segfault handler will
    /// use this alternative stack, meaning it can still print stack traces even if a segmentation
    /// fault is caused by a stack overflow.
    ///
    /// On POSIX targets, the signal stack is configured using 'sigaltstack(2)'.
    ///
    /// On Windows, this value is currently ignored.
    signal_stack_size: ?u64 = 1 << 18, // 1<<17 observed to be sufficient for stack tracing with self-hosted x86_64 backend

    /// The current log level.
    log_level: log.Level = log.default_level,

    log_scope_levels: []const log.ScopeLevel = &.{},

    logFn: fn (
        comptime message_level: log.Level,
        comptime scope: @EnumLiteral(),
        comptime format: []const u8,
        args: anytype,
    ) void = log.defaultLog,

    fmt_max_depth: usize = fmt.default_max_depth,

    /// By default, std.http.Client will support HTTPS connections.  Set this option to `true` to
    /// disable TLS support.
    ///
    /// This will likely reduce the size of the binary, but it will also make it impossible to
    /// make a HTTPS connection.
    http_disable_tls: bool = false,

    /// This enables `std.http.Client` to log ssl secrets to the file specified by the SSLKEYLOGFILE
    /// env var.  Creating such a log file allows other programs with access to that file to decrypt
    /// all `std.http.Client` traffic made by this program.
    http_enable_ssl_key_log_file: bool = @import("builtin").mode == .debug,

    side_channels_mitigations: crypto.SideChannelsMitigations = crypto.default_side_channels_mitigations,

    /// Whether to allow capturing and writing stack traces. This affects the following functions:
    /// * `debug.captureCurrentStackTrace`
    /// * `debug.writeCurrentStackTrace`
    /// * `debug.dumpCurrentStackTrace`
    /// * `debug.writeStackTrace`
    /// * `debug.dumpStackTrace`
    /// * `debug.writeErrorReturnTrace`
    /// * `debug.dumpErrorReturnTrace`
    ///
    /// Stack traces can generally be collected and printed when debug info is stripped, but are
    /// often less useful since they usually cannot be mapped to source locations and/or have bad
    /// source locations. The stack tracing logic can also be quite large, which may be undesirable,
    /// particularly in ReleaseSmall.
    ///
    /// If this is `false`, then captured stack traces will always be empty, and attempts to write
    /// stack traces will just print an error to the relevant `Io.Writer` and return.
    allow_stack_tracing: bool = !@import("builtin").strip_debug_info,

    /// Allows disabling networking in std.Io implementations.
    networking: bool = true,

    /// Whether or not `error.Unexpected` will print its value and a stack trace.
    ///
    /// If this happens the fix is to add the error code to the corresponding
    /// switch expression, possibly introduce a new error in the error set, and
    /// send a patch to Zig.
    unexpected_error_tracing: bool = @import("builtin").mode == .debug and switch (@import("builtin").zig_backend) {
        .stage2_llvm, .stage2_x86_64 => true,
        else => false,
    },

    /// TODO This is a separate decl instead of a field as a workaround around
    /// compilation errors due to zig not being lazy enough.
    pub const logTerminalMode: fn () Io.Terminal.Mode = log.defaultTerminalMode;

    /// TODO This is a separate decl instead of a field as a workaround around
    /// compilation errors due to zig not being lazy enough.
    pub const elf_debug_info_search_paths: ?fn (exe_path: []const u8) switch (@import("builtin").object_format) {
        .elf => debug.ElfFile.DebugInfoSearchPaths,
        else => void,
    } = if (@hasDecl(root, "std_options_elf_debug_info_search_paths"))
        root.std_options_elf_debug_info_search_paths
    else
        null;

    pub const debug_threaded_io: ?*Io.Threaded = if (@hasDecl(root, "std_options_debug_threaded_io"))
        root.std_options_debug_threaded_io
    else
        Io.Threaded.global_single_threaded;

    /// The `Io` instance that `std.debug` uses for `std.debug.print`,
    /// capturing stack traces, loading debug info, finding the executable's
    /// own path, and environment variables that affect terminal mode
    /// detection. The default is to use statically initialized singleton that
    /// is independent from the application's `Io` instance in order to make
    /// debugging more straightforward. For example, while debugging an `Io`
    /// implementation based on coroutines, one likely wants `std.debug.print`
    /// to directly write to stderr without trying to interact with the code
    /// being debugged.
    pub const debug_io: Io = if (@hasDecl(root, "std_options_debug_io")) root.std_options_debug_io else (if (os_options.Io) |io| io.debug_io else debug_threaded_io.?.io());

    /// Overrides `std.Io.Dir.cwd`.
    pub const cwd: ?fn () Io.Dir = if (@hasDecl(root, "std_options_cwd")) root.std_options_cwd else null;
};

// This forces the start.zig file to be imported, and the comptime logic inside that
// file decides whether to export any appropriate start symbols, and call main.
comptime {
    _ = start;
}

test {
    testing.refAllDecls(@This());
}

comptime {
    debug.assert(@import("std") == @This()); // std lib tests require --zig-lib-dir
}
