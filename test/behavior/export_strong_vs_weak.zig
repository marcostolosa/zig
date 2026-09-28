const std = @import("std");

fn zero() callconv(.c) u8 {
    return 0;
}

fn one() callconv(.c) u8 {
    return 1;
}

extern fn strongZeroWeakOne() u8;

test "export weak should not override strong" {
    @export(&zero, .{ .name = "strongZeroWeakOne", .linkage = .strong });
    @export(&one, .{ .name = "strongZeroWeakOne", .linkage = .weak });

    try std.testing.expectEqual(0, strongZeroWeakOne());
    try std.testing.expectEqual(&zero, &strongZeroWeakOne);
}

extern fn weakZeroStrongOne() u8;

test "export strong should override weak" {
    @export(&zero, .{ .name = "weakZeroStrongOne", .linkage = .weak });
    @export(&one, .{ .name = "weakZeroStrongOne", .linkage = .strong });

    try std.testing.expectEqual(1, weakZeroStrongOne());
    try std.testing.expectEqual(&one, &weakZeroStrongOne);
}
