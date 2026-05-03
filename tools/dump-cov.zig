//! Reads a Zig coverage file and prints human-readable information to stdout,
//! including file:line:column information for each PC.

const std = @import("std");
const Io = std.Io;
const fatal = std.process.fatal;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const SeenPcsHeader = std.Build.abi.fuzz.SeenPcsHeader;

const usage =
    \\usage: dump-cov path/to/exe path/to/coverage [target]
    \\  if omitted, 'target' defaults to 'native'
    \\  example: dump-cov zig-out/test .zig-cache/v/xxxxxxxx x86_64-linux
    \\
    \\Options:
    \\  -h, --help       Print this help and exit.
    \\
;

const command: std.cli.Command = .{
    .name = "dump-cov",
    .help = usage,
    .positional_args = &.{
        .init("exe", [:0]const u8, .{ .help = "path to exe" }),
        .init("cov", [:0]const u8, .{ .help = "path to coverage" }),
        .init("target", [:0]const u8, .{ .help = "target, defaults to native", .default_value = "native" }),
    },
};
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const parsed = try std.cli.parseAlloc(command, arena, args, .{
        .exit_help = true,
        .exit_usage_error = true,
        .render_usage_errors = true,
        .render_help = .verbatim,
    });

    const target = std.zig.resolveTargetQueryOrFatal(io, try .parse(.{
        .arch_os_abi = parsed.kind.args.target,
    }));

    const exe_file_name = parsed.kind.args.exe;
    const cov_file_name = parsed.kind.args.cov;

    const exe_path: Path = .{
        .root_dir = .cwd(),
        .sub_path = exe_file_name,
    };
    const cov_path: Path = .{
        .root_dir = .cwd(),
        .sub_path = cov_file_name,
    };

    var coverage: std.debug.Coverage = .init;
    defer coverage.deinit(gpa);

    var debug_info = std.debug.Info.load(gpa, io, exe_path, &coverage, target.ofmt, target.cpu.arch) catch |err| {
        fatal("failed to load debug info for {f}: {t}", .{ exe_path, err });
    };
    defer debug_info.deinit(gpa);

    const cov_bytes = cov_path.root_dir.handle.readFileAllocOptions(
        io,
        cov_path.sub_path,
        arena,
        .limited(1 << 30),
        .of(SeenPcsHeader),
        null,
    ) catch |err| {
        fatal("failed to load coverage file {f}: {s}", .{ cov_path, @errorName(err) });
    };

    var stdout_buffer: [4000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const header: *SeenPcsHeader = @ptrCast(cov_bytes);
    try stdout.print("{any}\n", .{header.*});
    const pcs = header.pcAddrs();

    var indexed_pcs: std.array_hash_map.Auto(usize, void) = .empty;
    try indexed_pcs.entries.resize(arena, pcs.len);
    @memcpy(indexed_pcs.entries.items(.key), pcs);
    try indexed_pcs.reIndex(arena);

    const sorted_pcs = try arena.dupe(usize, pcs);
    std.mem.sortUnstable(usize, sorted_pcs, {}, std.sort.asc(usize));

    const source_locations = try arena.alloc(std.debug.Coverage.SourceLocation, sorted_pcs.len);
    try debug_info.resolveAddresses(gpa, io, sorted_pcs, source_locations);

    const seen_pcs = header.seenBits();

    for (sorted_pcs, source_locations) |pc, sl| {
        if (sl.file == .invalid) {
            try stdout.print(" {x}: invalid\n", .{pc});
            continue;
        }
        const file = debug_info.coverage.fileAt(sl.file);
        const dir_name = debug_info.coverage.directories.keys()[file.directory_index];
        const dir_name_slice = debug_info.coverage.stringAt(dir_name);
        const seen_i = indexed_pcs.getIndex(pc).?;
        const hit: u1 = @truncate(seen_pcs[seen_i / @bitSizeOf(usize)] >> @intCast(seen_i % @bitSizeOf(usize)));
        try stdout.print("{c}{x}: {s}/{s}:{d}:{d}\n", .{
            "-+"[hit], pc, dir_name_slice, debug_info.coverage.stringAt(file.basename), sl.line, sl.column,
        });
    }

    try stdout.flush();
}
