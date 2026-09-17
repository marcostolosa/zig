comptime {
    _ = @TypeOf(.{}).is_optional;
}

// error
//
// :2:21: error: struct '@TypeOf(.{})' has no declaration named 'is_optional'
