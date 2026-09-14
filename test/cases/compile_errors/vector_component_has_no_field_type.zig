export fn entry() void {
    _ = @FieldType(@Vector(2, i32), "x");
}

// error
//
// :2:20: error: expected struct or union; found '@Vector(2, i32)'
