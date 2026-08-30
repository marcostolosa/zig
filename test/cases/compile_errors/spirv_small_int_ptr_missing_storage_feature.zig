const storage_u8 = @extern(*addrspace(.storage_buffer) extern struct { val: u8 }, .{
    .name = "storage_u8",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});

const uniform_u8 = @extern(*addrspace(.uniform) extern struct { val: u8 }, .{
    .name = "uniform_u8",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});

const push_constant_u16 = @extern(*addrspace(.push_constant) extern struct { val: u16 }, .{
    .name = "push_constant_u16",
});

export fn loadStorage() callconv(.kernel) void {
    _ = storage_u8.*;
}

export fn loadUniform() callconv(.kernel) void {
    _ = uniform_u8.*;
}

export fn loadPushConstant() callconv(.kernel) void {
    _ = push_constant_u16.*;
}

// error
// backend=auto
// target=spirv32-vulkan
// cpu_features=baseline+int8+int16+int64
//
//:16:19: error: 'u8' requires feature 'storage_buffer8bit_access' to be loaded/stored in address space 'storage_buffer'
//:20:19: error: 'u8' requires feature 'uniform_and_storage_buffer8bit_access' to be loaded/stored in address space 'uniform'
//:24:26: error: 'u16' requires feature 'storage_push_constant16' to be loaded/stored in address space 'push_constant'

