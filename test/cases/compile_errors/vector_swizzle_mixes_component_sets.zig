export fn entry() void {
    var vec = @Vector(4, i32){ 1, 2, 3, 4 };
    _ = &vec;
    _ = vec.gray;
}

// error
//
// :4:13: error: swizzle on '@Vector(4, i32)' cannot mix spatial and color components
// :4:13: note: component names must come entirely from 'xyzw' or entirely from 'rgba'
