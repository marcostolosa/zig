const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

test "io_mode" {
    try testing.expectEqual(.evented, builtin.test_io_mode);
    try testing.expectEqual(.evented, testing.io_mode);
}
