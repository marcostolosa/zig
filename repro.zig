var runtimeP: *bool = undefined;

pub fn main() void {
    comptime var b = true;
    runtimeP = &b;
}
