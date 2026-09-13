export fn entry() void {
    var vec = @Vector(8, i32){ 1, 2, 3, 4, 5, 6, 7, 8 };
    _ = &vec;
    _ = vec.x;
}

// error
//
// :4:12: error: component access not available on '@Vector(8, i32)'
// :4:12: note: vectors longer than four elements have no component names
// :4:12: note: use '[0]' to access this element
