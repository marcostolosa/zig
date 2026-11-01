comptime {
    _ = @embedFile("/root/foo");
}

// error
// is_test=true
//
// :2:20: error: embed of file using absolute path: '/root/foo'
