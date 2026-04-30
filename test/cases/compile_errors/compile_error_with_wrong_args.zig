export fn entry1() void {
    @compileError();
}

export fn entry2() void {
    @compileError(123);
}

export fn entry3() void {
    @compileError(&[_]u16{ 'f', 'o', 'o' });
}

export fn entry4() void {
    @compileError(undefined);
}

// error
//
// :2:5: error: expected at least 1 argument, found 0
// :2:5: note: consider using 'comptime unreachable'
// :6:19: error: expected either type '[]const u8' or type 'type', found 'comptime_int'
// :10:19: error: expected either type '[]const u8' or type 'type', found '*const [3]u16'
// :10:19: note: pointer type child 'u16' cannot cast into pointer type child 'u8'
// :10:19: note: unsigned 8-bit int cannot represent all possible unsigned 16-bit values
// :14:19: error: use of undefined value here causes illegal behavior
