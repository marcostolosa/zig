pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const alloc = init.gpa;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 3) return error.BadUsage;

    const expected_json_fp = args[1];
    const expected_json = v: {
        const expected_json_fh = try std.Io.Dir.cwd().openFile(io, expected_json_fp, .{});
        defer expected_json_fh.close(io);
        var rd_buffer: [4096]u8 = undefined;
        var json_f_rdr = expected_json_fh.reader(io, &rd_buffer);
        var json_reader: std.json.Reader = .init(alloc, &json_f_rdr.interface);
        defer json_reader.deinit();
        break :v try std.json.parseFromTokenSource(
            ExpectedJson,
            alloc,
            &json_reader,
            .{ .ignore_unknown_fields = false },
        );
    };
    defer expected_json.deinit();
    const expected = expected_json.value;

    const actual_json_fp = args[2];
    const actual_json = v: {
        const actual_json_fh = try std.Io.Dir.cwd().openFile(io, actual_json_fp, .{});
        defer actual_json_fh.close(io);
        var rd_buffer: [4096]u8 = undefined;
        var json_f_rdr = actual_json_fh.reader(io, &rd_buffer);
        var json_reader: std.json.Reader = .init(alloc, &json_f_rdr.interface);
        defer json_reader.deinit();
        break :v try std.json.parseFromTokenSource(
            CompDbJson,
            alloc,
            &json_reader,
            .{ .ignore_unknown_fields = false },
        );
    };
    defer actual_json.deinit();
    const actual = actual_json.value;

    // Must specify every file you expect a compile_commands.json entry for
    if (expected.len != actual.len) {
        return error.FileCountMismatch;
    }

    // Holy nested for loops!

    // Make sure expected files are in JSON
    loop: for (expected) |exp_entry| {
        for (actual) |actual_entry| {
            // Expectd just gives file names, actual json will have full paths
            if (std.mem.find(u8, actual_entry.file, exp_entry.file)) |_| {
                // Make sure expected flags are in args
                loopf: for (exp_entry.arguments) |flg| {
                    for (actual_entry.arguments) |arg| {
                        if (std.mem.eql(u8, arg, flg)) {
                            continue :loopf;
                        }
                    }
                    return error.MissingFlag;
                }
                continue :loop;
            }
        }
        return error.MissingFile;
    }
}

pub const CompDbJsonEntry = struct {
    directory: []const u8,
    file: []const u8,
    output: []const u8,
    arguments: []const []const u8,
};
pub const CompDbJson = []const CompDbJsonEntry;

pub const ExpectedJsonEntry = struct {
    file: []const u8,
    arguments: []const []const u8,
};
pub const ExpectedJson = []const ExpectedJsonEntry;

const std = @import("std");
