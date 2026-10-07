const Inner = struct { x: ??u8 };
const Outer = struct { inner: []const Inner };

export fn entry1() void {
    _ = @import("std").zon.parse.fromSlice(Outer, undefined) catch {};
}

export fn entry2() void {
    _ = @import("std").zon.parse.fromSlice(??u8, undefined) catch {};
}

// error
//
// :?:?: error: cannot parse: ??u8
// :?:?: note: called at comptime here
// :?:?: error: cannot parse field 'x' of type '??u8' in 'tmp.Inner'
// :?:?: note: called at comptime here
