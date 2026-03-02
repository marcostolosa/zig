export fn a() void {
    @log2(0);
}

export fn b() void {
    @log10(0);
}

// error
//
// :2:11: error: integer operand must be greater than zero (got '0')
// :6:12: error: integer operand must be greater than zero (got '0')
