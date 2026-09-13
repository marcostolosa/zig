export fn entry() void {
    var vec = @Vector(4, i32){ 1, 2, 3, 4 };
    _ = &vec;
    _ = &vec.xy;
}

// error
//
// :4:14: error: cannot assign to or take a pointer to swizzle on '@Vector(4, i32)'
