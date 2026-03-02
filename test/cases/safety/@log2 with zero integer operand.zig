const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "@log2/@log10 called with zero integer operand")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var runtime: u32 = 0;
    _ = &runtime;
    _ = @log2(runtime);
    return error.TestFailed;
}

// run
// backend=selfhosted,llvm
// target=x86_64-linux,aarch64-linux
