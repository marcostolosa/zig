const std = @import("std");
const abi = @import("abi.zig");

pub const Word = u32;

/// JIRL rd, rj, si16 (Jump and Link Register)
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

/// ADD.D rd, rj, rk (Addition)
pub fn addD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00021) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SUB.D rd, rj, rk (Subtraction)
pub fn subD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00023) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// OR rd, rj, rk (Bitwise OR)
pub fn @"or"(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x0002A) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// ADDI.D rd, rj, si12 (Add Immediate)
pub fn addiD(rd: abi.Register, rj: abi.Register, si12: i12) Word {
    const imm12: u32 = @as(u12, @bitCast(si12));
    return (@as(u32, 0x00b) << 22) |
        (imm12 << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// AND rd, rj, rk (Bitwise AND)
pub fn andD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00029) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// XOR rd, rj, rk (Bitwise XOR)
pub fn xorD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x0002B) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SLL.W rd, rj, rk (Shift Left Logical 32-bit)
pub fn sllW(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x0002e) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SRL.W rd, rj, rk (Shift Right Logical 32-bit)
pub fn srlW(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x0002f) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SRA.W rd, rj, rk (Shift Right Arithmetic 32-bit)
pub fn sraW(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00030) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SLL.D rd, rj, rk (Shift Left Logical 64-bit)
pub fn sllD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00031) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SRL.D rd, rj, rk (Shift Right Logical 64-bit)
pub fn srlD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00032) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// SRA.D rd, rj, rk (Shift Right Arithmetic 64-bit)
pub fn sraD(rd: abi.Register, rj: abi.Register, rk: abi.Register) Word {
    return (@as(u32, 0x00033) << 15) |
        (@as(u32, rk.id()) << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// LD.D rd, rj, si12 (Load Doubleword)
pub fn ldD(rd: abi.Register, rj: abi.Register, si12: i12) Word {
    const imm12: u32 = @as(u12, @bitCast(si12));
    return (@as(u32, 0x0a3) << 22) |
        (imm12 << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}

/// ST.D rd, rj, si12 (Store Doubleword)
pub fn stD(rd: abi.Register, rj: abi.Register, si12: i12) Word {
    const imm12: u32 = @as(u12, @bitCast(si12));
    return (@as(u32, 0x0a7) << 22) |
        (imm12 << 10) |
        (@as(u32, rj.id()) << 5) |
        @as(u32, rd.id());
}
