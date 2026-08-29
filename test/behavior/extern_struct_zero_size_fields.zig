const E = enum(u0) {
    the_only_possible_value,
};

const T = extern struct {
    foo: u0 = 0,
    bar: void = {},
    ayy: E = .the_only_possible_value,
    arr: [0]u0 = .{},
    matey: [128]void = @splat({}),
};

test {
    var t: T = .{};
    _ = &t;
}
