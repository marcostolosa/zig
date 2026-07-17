const plan9 = @import("../plan9.zig");
// TODO better inline asm

pub fn syscall1(comptime sys: plan9.SYS, arg0: usize) usize {
    return asm volatile (
        \\pushq %[arg0]
        \\push %%rbp
        \\mov %[syscall_number], %%ebp
        \\syscall
        \\pop %%rbp
        \\pop %%r11
        : [ret] "={rax}" (-> usize),
        : [arg0] "rm" (arg0),
          [syscall_number] "i" (@backingInt(sys)),
        : .{ .rcx = true, .rax = true, .r11 = true, .memory = true });
}
pub fn syscall2(comptime sys: plan9.SYS, arg0: usize, arg1: usize) usize {
    return asm volatile (
        \\pushq %[arg1]
        \\push %[arg0]
        \\push %%rbp
        \\mov %[syscall_number], %%ebp
        \\syscall
        \\pop %%rbp
        \\pop %%r11
        \\pop %%r11
        : [ret] "={rax}" (-> usize),
        : [arg0] "r" (arg0),
          [arg1] "rm" (arg1),
          [syscall_number] "i" (@backingInt(sys)),
        : .{ .rcx = true, .rax = true, .r11 = true, .memory = true });
}
pub fn syscall3(comptime sys: plan9.SYS, arg0: usize, arg1: usize, arg2: usize) usize {
    return asm volatile (
        \\pushq %[arg2]
        \\push %[arg1]
        \\push %[arg0]
        \\push %%rbp
        \\mov %[syscall_number], %%ebp
        \\syscall
        \\pop %%rbp
        \\pop %%r11
        \\pop %%r11
        \\pop %%r11
        : [ret] "={rax}" (-> usize),
        : [arg0] "r" (arg0),
          [arg1] "r" (arg1),
          [arg2] "rm" (arg2),
          [syscall_number] "{rbp}" (@backingInt(sys)),
        : .{ .rcx = true, .rax = true, .rbp = true, .r11 = true, .memory = true });
}
pub fn syscall4(comptime sys: plan9.SYS, arg0: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile (
        \\pushq %[arg3]
        \\push %[arg2]
        \\push %[arg1]
        \\push %[arg0]
        \\push %%rbp
        \\mov %[syscall_number], %%ebp
        \\syscall
        \\pop %%rbp
        \\pop %%r11
        \\pop %%r11
        \\pop %%r11
        \\pop %%r11
        : [ret] "={rax}" (-> usize),
        : [arg0] "r" (arg0),
          [arg1] "r" (arg1),
          [arg2] "r" (arg2),
          [arg3] "rm" (arg3),
          [syscall_number] "i" (@backingInt(sys)),
        : .{ .rcx = true, .rax = true, .r11 = true, .memory = true });
}
