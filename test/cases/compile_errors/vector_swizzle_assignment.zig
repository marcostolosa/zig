export fn entry() void {
    var vec = @Vector(4, i32){ 1, 2, 3, 4 };
    _ = &vec;
    vec.xy = @Vector(2, i32){ 5, 6 };
}

// error
//
// :4:9: error: cannot assign to or take reference of swizzle on '@Vector(4, i32)'
