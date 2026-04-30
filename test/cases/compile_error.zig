export fn entry1() void {
    @compileError("this is an error");
}

const E = enum(u8) { _ };
const S = struct {};
export fn entry2() void {
    @compileError("I like ", E, " more than ", S);
}

export fn entry3() void {
    comptime var msg = [_]u8{ 'v', 'a', 'r', 'i', 'a', 'd', 'l', 'e' };
    msg[5] = 'b';
    @compileError(&msg);
}

export fn entry4() void {
    @compileError("this type is undefined: ", @as(type, undefined));
}

// error
//
// :2:5: error: this is an error
// :8:5: error: I like tmp.E more than tmp.S
// :5:11: note: enum declared here
// :6:11: note: struct declared here
// :14:5: error: variable
// :18:5: error: this type is undefined: @as(type, undefined)
