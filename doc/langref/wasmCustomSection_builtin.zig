const arch = @import("builtin").target.cpu.arch;

comptime {
    if (arch == .wasm32) {
        @wasmCustomSection("name", "data");
        @wasmCustomSection("another-name", &[_]u8{ 1, 2, 3 });
    }
}

// syntax
