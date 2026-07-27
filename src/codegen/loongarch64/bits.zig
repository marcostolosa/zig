const std = @import("std");
const abi = @import("abi.zig");

pub const Word = u32;

pub fn jirl(rd: abi.Register, rj: abi.Register, si16: i16) Word {
    const imm: u32 = @bitCast(@as(i32, si16));
    const imm16: u32 = imm & 0xffff;
    return (@as(u32, 0x13) << 26) |
        (imm16 << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

pub fn ret() Word {
    return jirl(.zero, .ra, 0);
}
