pub fn main() void {
    var operand: u32 = 0;
    _ = &operand;
    _ = @log2(operand);
}

// exe=fail
