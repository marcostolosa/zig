const std = @import("std");

extern fn foo() c_int;
extern fn bar() c_int;
extern fn baz() c_int;

pub fn main(_: std.process.Init) !void {
    std.log.info("|{d}, {d}, {d}|", .{ foo(), bar(), baz() });
}

test foo {
    try std.testing.expectEqual(3, foo() + bar() + baz());
}
