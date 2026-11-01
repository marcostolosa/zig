comptime {
    _ = @import("/root/foo");
}

// error
// is_test=true
//
// :2:17: error: import of file using absolute path
