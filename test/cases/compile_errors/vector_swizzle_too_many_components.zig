export fn entry() void {
    var vec = @Vector(3, i32){ 1, 2, 3 };
    _ = &vec;
    _ = vec.xxyyzz;
}

// error
//
// :4:13: error: swizzle on '@Vector(3, i32)' cannot be longer than four components
// :4:13: note: use @shuffle instead
