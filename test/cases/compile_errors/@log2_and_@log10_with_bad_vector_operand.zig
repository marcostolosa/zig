export fn a() void {
    @log2(@Vector(4, u8){ 1, 2, 3, 0 });
}

export fn b() void {
    @log10(@Vector(4, u8){ 9, 0, 7, 5 });
}

// error
//
// :2:25: error: vector operand must contain values greater than zero (got '0' at index 3)
// :6:26: error: vector operand must contain values greater than zero (got '0' at index 1)
