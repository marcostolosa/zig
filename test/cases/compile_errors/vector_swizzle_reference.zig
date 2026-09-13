export fn entry() void {
    var vec = @Vector(4, i32){ 1, 2, 3, 4 };
    _ = &vec;
    _ = &vec.xy;
}

// error
//
// :4:14: error: cannot assign to or take reference of swizzle on '@Vector(4, i32)'
