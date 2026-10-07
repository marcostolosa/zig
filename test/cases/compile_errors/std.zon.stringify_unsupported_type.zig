const E = enum(u8) { a, _ };
const S = struct { e: []const E };

export fn entry() void {
    const s: S = .{ .e = &.{.a} };
    @import("std").zon.stringify.serialize(s, .{}, undefined) catch {};
}

// error
//
// :?:?: error: cannot serialize field 'e' of type '[]const tmp.E' in 'tmp.S'
// :?:?: note: called at comptime here
