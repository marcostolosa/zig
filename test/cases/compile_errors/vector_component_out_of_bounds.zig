export fn entry() void {
    var vec = @Vector(2, i32){ 1, 2 };
    _ = &vec;
    _ = vec.z;
}

// error
//
// :4:13: error: component 'z' is out of bounds on '@Vector(2, i32)'
