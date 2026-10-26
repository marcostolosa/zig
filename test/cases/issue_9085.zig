export fn bar(chr: u8) c_int {
    var buf = [_]u8{chr};
    _ = Foo.init(&buf);
    return 0;
}

const aType = []u8;
const Foo = struct {
    foo: @TypeOf(aType),
    pub fn init(foo: []u8) Foo {
        _ = foo;
        return Foo{ .foo = &.{} };
    }
};

// error
//
// :3:18: error: unable to resolve comptime value
// :3:17: note: call to function with comptime-only return type 'tmp.Foo' is evaluated at comptime
// :10:28: note: return type declared here
// :9:10: note: struct requires comptime because of this field
// :9:10: note: types are not available at runtime
