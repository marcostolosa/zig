const std = @import("std");

const mem = std.mem;
const ArrayList = std.ArrayList;

const wasm_path = @import("build_options").wasm_path;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const wasm_file = try std.Io.Dir.cwd().openFile(io, wasm_path, .{});
    defer wasm_file.close(io);

    var buf: [1000]u8 = undefined;
    const file_size = try wasm_file.readPositional(io, &.{&buf}, 0);
    const wasm = buf[0..file_size];

    const customs = try get_custom_sections(wasm);

    std.debug.assert(has_custom_section(&customs, "is-utf8", "abcd"));
    std.debug.assert(has_custom_section(&customs, "non-utf8", &[_]u8{ 255, 254, 253 }));

    // TODO: Currently, the two "dupe-name" `linksection`s in `lib.zig` are getting combined
    //  into one custom section. We have not yet looked into why.
    //  When we solve that problem we can uncomment these two lines and
    //  delete the "twoone" check below.
    // std.debug.assert(has_custom_section(&customs, "dupe-name", "one"));
    // std.debug.assert(has_custom_section(&customs, "dupe-name", "two"));
    std.debug.assert(has_custom_section(&customs, "dupe-name", "twoone"));
}

const CustomSection = struct {
    name: []const u8,
    data: []const u8,
};

fn get_custom_sections(wasm: []const u8) ![4]CustomSection {
    var customs: [4]CustomSection = undefined;

    var reader: std.Io.Reader = .fixed(wasm);

    const custom_section_id = 0;

    const wasm_magic_number = &[_]u8{ 0x00, 0x61, 0x73, 0x6D };
    std.debug.assert(std.mem.eql(u8, try reader.take(4), wasm_magic_number));

    // Skip wasm version bytes
    _ = try reader.take(4);

    var custom_section_idx: usize = 0;

    while (reader.peekByte() != error.EndOfStream) {
        const section_id = try reader.takeByte();
        const section_len = try reader.takeLeb128(u32);

        if (section_id != custom_section_id) {
            reader.toss(section_len);
        } else {
            const name_len = try reader.takeLeb128(u32);
            const name_len_byte_count = if (name_len < 127) 1 else unreachable;
            const name = try reader.take(name_len);

            const data_len = section_len - name_len_byte_count - name_len;
            const data = try reader.take(data_len);

            customs[custom_section_idx] = .{ .name = name, .data = data };
            custom_section_idx += 1;
        }
    }

    return customs;
}

fn has_custom_section(customs: []const CustomSection, name: []const u8, data: []const u8) bool {
    for (customs) |custom| {
        if (std.mem.eql(u8, custom.name, name) and std.mem.eql(u8, custom.data, data)) {
            return true;
        }
    }

    return false;
}
