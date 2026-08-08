export fn entry1() u16 {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    return slice[0];
}

export fn entry2() *const u16 {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    return &slice[0];
}

export fn entry3() u16 {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    return slice ++ &.{};
}

export fn entry4() void {
    comptime var slice: []const u8 = "hello";
    slice.len = undefined;
    @compileError(slice);
}

export fn entry5() usize {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    return slice.len;
}

export fn entry6() void {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    const slice2 = slice[0..1];
    _ = slice2;
}

// error
//
// :4:17: error: use of slice with undefined length here causes illegal behavior
// :10:18: error: use of slice with undefined length here causes illegal behavior
// :16:12: error: use of slice with undefined length here causes illegal behavior
// :22:19: error: use of slice with undefined length here causes illegal behavior
// :28:17: error: use of slice with undefined length here causes illegal behavior
// :34:25: error: use of slice with undefined length here causes illegal behavior
