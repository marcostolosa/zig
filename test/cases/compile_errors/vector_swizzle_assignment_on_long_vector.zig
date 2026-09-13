export fn entry() void {
    var vec = @Vector(8, i32){ 1, 2, 3, 4, 5, 6, 7, 8 };
    _ = &vec;
    vec.rgb = @Vector(3, i32){ 1, 2, 3 };
}

// error
//
// :4:8: error: swizzling not available on '@Vector(8, i32)'
// :4:8: note: vectors longer than four elements have no component names
// :4:8: note: use @shuffle instead
