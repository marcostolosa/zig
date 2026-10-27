const Foo = packed struct {
    pad: u65535 = undefined,
    bit: u1,
};
export fn bar() void {
    const foo = Foo{ .bit = 0 };
    const ptr: *align(@alignOf(Foo):65535:8192) const u1 = &foo.bit;
    _ = &ptr;
}

// error
//
// :1:20: error: packed struct bit width '65536' exceeds maximum bit width of 65535
