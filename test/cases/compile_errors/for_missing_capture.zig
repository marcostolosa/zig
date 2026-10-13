export fn entry() void {
    const items = [_]usize{ 4, 5, 6 };
    var count: usize = 0;
    for (items[0..].ptr, 0..3) |i| count += 1;
    _ = count;
}

// error
//
// :4:27: error: for input is not captured
