comptime {
    @wasmCustomSection("hello", "world");
}

// error
// target=x86_64-native
//
// :2:9: error: builtin @wasmCustomSection is available when targeting WebAssembly; targeted CPU architecture is x86_64

