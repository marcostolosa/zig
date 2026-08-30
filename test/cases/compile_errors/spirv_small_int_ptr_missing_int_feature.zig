const S = extern struct { x: u32, y: u8 };
const P = packed struct(u8) { a: u4, b: u4 };
const U = extern union { a: u32, b: u8 };

const storage_u8 = @extern(*addrspace(.storage_buffer) extern struct { val: u8 }, .{
    .name = "storage_u8",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});

const uniform_u16 = @extern(*addrspace(.uniform) extern struct { val: u16 }, .{
    .name = "uniform_u16",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});

const push_constant_u8 = @extern(*addrspace(.push_constant) extern struct { val: u8 }, .{
    .name = "push_constant_u8",
});

const storage_struct = @extern(*addrspace(.storage_buffer) extern struct {val: S}, .{
    .name = "storage_struct",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } },
});

const storage_packed = @extern(*addrspace(.storage_buffer) extern struct { val: P }, .{
    .name = "storage_packed",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 3 } },
});

const storage_array = @extern(*addrspace(.storage_buffer) extern struct { val: [4]u8 }, .{
    .name = "storage_array",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 4 } },
});

const storage_union = @extern(*addrspace(.storage_buffer) extern struct { val: U }, .{
    .name = "storage_union",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 5 } },
});

export fn storeU8() callconv(.kernel) void {
    storage_u8.val = 1;
}

export fn loadU16() callconv(.kernel) void {
    _ = uniform_u16.val;
}

export fn storePushConstantU8() callconv(.kernel) void {
    push_constant_u8.val = 1;
}

export fn loadStruct() callconv(.kernel) void {
    _ = storage_struct.val;
}

export fn loadPacked() callconv(.kernel) void {
    _ = storage_packed.val;
}

export fn loadArray() callconv(.kernel) void {
    _ = storage_array.val;
}

export fn loadUnion() callconv(.kernel) void {
    _ = storage_union.val;
}

// error
// backend=auto
// target=spirv32-opengl,spirv32-vulkan
//
//:40:20: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'storage_buffer'
//:44:20: error: 'u16' requires feature 'int16' to be loaded/stored in address space 'uniform'
//:48:26: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'push_constant'
//:52:23: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'storage_buffer'
//:56:23: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'storage_buffer'
//:60:22: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'storage_buffer'
//:64:22: error: 'u8' requires feature 'int8' to be loaded/stored in address space 'storage_buffer'

