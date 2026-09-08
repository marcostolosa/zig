comptime {
    const A = @Tuple(&.{});
    const a: A = .{};
    _ = a[0];
}
comptime {
    const B = struct { u32 };
    const b: B = .{4};
    _ = b[0];
    _ = b[4];
}

// error
//
// :4:10: error: indexing into empty tuple is not allowed
// :10:11: error: index 4 out of bounds of tuple 'struct { u32 }'
