export fn entry() void {
    _ = @FieldType(@Vector(2, i32), "len");
}

// error
//
// :2:37: error: 'len' is not a component of '@Vector(2, i32)'
// :2:37: note: vector components are named 'x', 'y', 'z', 'w' or 'r', 'g', 'b', 'a'
