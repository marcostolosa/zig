comptime {
    @wasmCustomSection("name", "data");
    @wasmCustomSection("another-name", &[_]u8{ 1, 2, 3 });
}

// syntax
