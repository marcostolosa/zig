export fn a() void {
    @log2(@as(i8, -1));
}

export fn b() void {
    @log10(@as(i8, -1));
}

// error
//
// :2:11: error: expected unsigned integer, float, or vector of either unsigned integers or floats, found 'i8'
// :6:12: error: expected unsigned integer, float, or vector of either unsigned integers or floats, found 'i8'
