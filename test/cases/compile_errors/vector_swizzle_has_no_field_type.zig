export fn entry() void {
    _ = @FieldType(@Vector(4, i32), "xy");
}

// error
//
// :2:37: error: swizzle 'xy' does not name a single component
