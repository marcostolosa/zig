export fn entry() void {
    var vec = @Vector(0, i32){};
    _ = &vec;
    _ = vec.x;
}

// error
//
// :4:12: error: component access not available on '@Vector(0, i32)'
