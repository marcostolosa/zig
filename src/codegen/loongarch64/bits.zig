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

/// ADD.D rd, rj, rk
pub fn addD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00020) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SUB.D rd, rj, rk
pub fn subD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00022) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// OR rd, rj, rk
pub fn @"or"(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x0002a) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// ADDI.D rd, rj, si12
pub fn addiD(rd: abi.Register, rj: abi.Register, si12: i12) Word {
    const imm12: u32 = @as(u12, @bitCast(si12));
    return (@as(u32, 0x00b) << 22) |
        (imm12 << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}
