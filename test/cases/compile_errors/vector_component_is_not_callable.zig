export fn entry() void {
    var vec = @Vector(4, i32){ 1, 2, 3, 4 };
    _ = &vec;
    _ = vec.x();
}

// error
//
// :4:12: error: type 'i32' not a function
