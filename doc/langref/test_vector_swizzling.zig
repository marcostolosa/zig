const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "Vector Swizzling" {
    const a = @Vector(4, i32){ 1, 2, 3, 4 };

    // Swizzling up to four components can create vectors.
    const b: @Vector(3, i32) = a.xxy;

    try expectEqual(1, b.r);
    try expectEqual(1, b.g);
    try expectEqual(2, b.b);

    // Swizzling also accepts color components. Mixing color and spatial
    // components in a single swizzle is not allowed.
    const c = a.argb;

    try expectEqual(4, c.x);
    try expectEqual(1, c.y);
    try expectEqual(2, c.z);
    try expectEqual(3, c.w);

    // referencing a swizzle creates a pointer to a constant copy
    const ptr: *const @Vector(2, i32) = &a.bg;

    try expectEqual(3, ptr.x);
    try expectEqual(2, ptr.y);
}

// test
