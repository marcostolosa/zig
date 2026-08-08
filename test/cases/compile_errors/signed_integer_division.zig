export fn foo(a: i32, b: i32) i32 {
    return a / b;
}

export fn bar() void {
    const i: isize = -3;
    _ = 14 / i;
}

// error
//
// :2:14: error: division with 'i32' and 'i32': signed integers must use @divTrunc, @divFloor, @divCeil, or @divExact
// :7:12: error: division with 'comptime_int' and 'isize': signed integers must use @divTrunc, @divFloor, @divCeil, or @divExact
