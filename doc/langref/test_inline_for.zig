const expectEqual = @import("std").testing.expectEqual;
const Int = @import("std").meta.Int;

test "inline for loop" {
    const array = getRuntimeArray();
    const slice = getRuntimeSlice();
    const len = slice.len;
    // All of the above values are runtime-known, but the *length* of `array` is
    // known at compile time, so we can use `inline for`. This will effectively
    // duplicate the loop body 3 times.
    inline for (0..len, array, slice) |i, array_elem, slice_elem| {
        // Even though `len` was runtime-known, because the start index 0 was
        // comptime-known, `i` is comptime-known. That means we can do things
        // with it which are only legal at comptime, such as create types.
        _ = Int(.unsigned, i);
        // `slice_elem` and `arr_elem` are runtime-known.
        try expectEqual(i + 5, array_elem);
        try expectEqual(i * 10, slice_elem);
    }
}
fn getRuntimeArray() [3]u8 {
    return .{ 5, 6, 7 };
}
fn getRuntimeSlice() []const u8 {
    return &.{ 0, 10, 20 };
}

// test
