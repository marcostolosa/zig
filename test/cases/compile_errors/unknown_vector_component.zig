export fn entry() void {
    var vec = @Vector(0, i32){};
    _ = &vec;
    _ = vec.q;
}

// error
//
// :4:13: error: no member named 'q' in '@Vector(0, i32)'
