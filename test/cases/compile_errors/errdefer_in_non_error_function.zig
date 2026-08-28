fn foo() u8 {
    var a: u8 = 5;
    errdefer a += 1;
    return a;
}

export fn entry() u8 {
    return foo();
}

// error
//
// :3:5: error: errdefer in function with no error union return type
