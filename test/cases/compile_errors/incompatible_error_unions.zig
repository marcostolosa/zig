export fn foo() void {
    var cond: bool = false;
    _ = &cond;
    const ab = if (cond) a else b;
    _ = ab;
}

fn a() !void {
    return error.ErrorA;
}

fn b() !void {
    return error.ErrorB;
}

// error
//
// :4:16: error: incompatible types: 'fn () @typeInfo(@typeInfo(@TypeOf(tmp.a)).@"fn".return_type.?).error_union.error_set!void' and 'fn () @typeInfo(@typeInfo(@TypeOf(tmp.b)).@"fn".return_type.?).error_union.error_set!void'
// :4:26: note: type 'fn () @typeInfo(@typeInfo(@TypeOf(tmp.a)).@"fn".return_type.?).error_union.error_set!void' here
// :4:33: note: type 'fn () @typeInfo(@typeInfo(@TypeOf(tmp.b)).@"fn".return_type.?).error_union.error_set!void' here
