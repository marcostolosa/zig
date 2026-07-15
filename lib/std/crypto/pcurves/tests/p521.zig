const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;

const P521 = @import("../p521.zig").P521;

test "p521 ECDH key exchange" {
    const io = testing.io;
    const dha = P521.scalar.random(io, .little);
    const dhb = P521.scalar.random(io, .little);
    const dhA = try P521.basePoint.mul(dha, .little);
    const dhB = try P521.basePoint.mul(dhb, .little);
    const shareda = try dhA.mul(dhb, .little);
    const sharedb = try dhB.mul(dha, .little);
    try testing.expect(shareda.equivalent(sharedb));
}

test "p521 point from affine coordinates" {
    const xh = "00c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3dbaa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd66";
    const yh = "011839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e662c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd16650";
    var xs: [66]u8 = undefined;
    _ = try fmt.hexToBytes(&xs, xh);
    var ys: [66]u8 = undefined;
    _ = try fmt.hexToBytes(&ys, yh);
    var p = try P521.fromSerializedAffineCoordinates(xs, ys, .big);
    try testing.expect(p.equivalent(P521.basePoint));
}

test "p521 test vectors" {
    const expected = [_][]const u8{
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "00C6858E06B70404E9CD9E3ECB662395B4429C648139053FB521F828AF606B4D3DBAA14B5E77EFE75928FE1DC127A2FFA8DE3348B3C1856A429BF97E7E31C2E5BD66",
        "00433C219024277E7E682FCB288148C282747403279B1CCC06352C6E5505D769BE97B3B204DA6EF55507AA104A3A35C5AF41CF2FA364D60FD967F43E3933BA6D783D",
        "01A73D352443DE29195DD91D6A64B5959479B52A6E5B123D9AB9E5AD7A112D7A8DD1AD3F164A3A4832051DA6BD16B59FE21BAEB490862C32EA05A5919D2EDE37AD7D",
        "0035B5DF64AE2AC204C354B483487C9070CDC61C891C5FF39AFC06C5D55541D3CEAC8659E24AFE3D0750E8B88E9F078AF066A1D5025B08E5A5E2FBC87412871902F3",
        "00652BF3C52927A432C73DBC3391C04EB0BF7A596EFDB53F0D24CF03DAB8F177ACE4383C0C6D5E3014237112FEAF137E79A329D7E1E6D8931738D5AB5096EC8F3078",
        "01EE4569D6CDB59219532EFF34F94480D195623D30977FD71CF3981506ADE4AB01525FBCCA16153F7394E0727A239531BE8C2F66E95657F380AE23731BEDF79206B9",
        "0056D5D1D99D5B7F6346EEB65FDA0B073A0C5F22E0E8F5483228F018D2C2F7114C5D8C308D0ABFC698D8C9A6DF30DCE3BBC46F953F50FDC2619A01CEAD882816ECD4",
        "000822C40FB6301F7262A8348396B010E25BD4E29D8A9B003E0A8B8A3B05F826298F5BFEA5B8579F49F08B598C1BC8D79E1AB56289B5A6F4040586F9EA54AA78CE68",
        "01585389E359E1E21826A2F5BF157156D488ED34541B988746992C4AB145B8C6B6657429E1396134DA35F3C556DF725A318F4F50BABD85CD28661F45627967CBE207",
        "0190EB8F22BDA61F281DFCFE7BB6721EC4CD901D879AC09AC7C34A9246B11ADA8910A2C7C178FCC263299DAA4DA9842093F37C2E411F1A8E819A87FF09A04F2F3320",
    };
    var p = P521.identityElement;
    for (expected) |xh| {
        const x = p.affineCoordinates().x;
        p = p.add(P521.basePoint);
        var xs: [66]u8 = undefined;
        _ = try fmt.hexToBytes(&xs, xh);
        try testing.expectEqualSlices(u8, &x.toBytes(.big), &xs);
    }
}

test "p521 test vectors - doubling" {
    const expected = [_][]const u8{
        "00C6858E06B70404E9CD9E3ECB662395B4429C648139053FB521F828AF606B4D3DBAA14B5E77EFE75928FE1DC127A2FFA8DE3348B3C1856A429BF97E7E31C2E5BD66",
        "00433C219024277E7E682FCB288148C282747403279B1CCC06352C6E5505D769BE97B3B204DA6EF55507AA104A3A35C5AF41CF2FA364D60FD967F43E3933BA6D783D",
        "0035B5DF64AE2AC204C354B483487C9070CDC61C891C5FF39AFC06C5D55541D3CEAC8659E24AFE3D0750E8B88E9F078AF066A1D5025B08E5A5E2FBC87412871902F3",
        "000822C40FB6301F7262A8348396B010E25BD4E29D8A9B003E0A8B8A3B05F826298F5BFEA5B8579F49F08B598C1BC8D79E1AB56289B5A6F4040586F9EA54AA78CE68",
    };
    var p = P521.basePoint;
    for (expected) |xh| {
        const x = p.affineCoordinates().x;
        p = p.dbl();
        var xs: [66]u8 = undefined;
        _ = try fmt.hexToBytes(&xs, xh);
        try testing.expectEqualSlices(u8, &x.toBytes(.big), &xs);
    }
}

test "p521 compressed sec1 encoding/decoding" {
    const io = testing.io;
    const p = P521.random(io);
    const s0 = p.toUncompressedSec1();
    const s = p.toCompressedSec1();
    try testing.expectEqualSlices(u8, s0[1..67], s[1..67]);
    const q = try P521.fromSec1(&s);
    try testing.expect(p.equivalent(q));
}

test "p521 uncompressed sec1 encoding/decoding" {
    const io = testing.io;
    const p = P521.random(io);
    const s = p.toUncompressedSec1();
    const q = try P521.fromSec1(&s);
    try testing.expect(p.equivalent(q));
}

test "p521 public key is the neutral element" {
    const io = testing.io;
    const n = P521.scalar.Scalar.zero.toBytes(.little);
    const p = P521.random(io);
    try testing.expectError(error.IdentityElement, p.mul(n, .little));
}

test "p521 public key is the neutral element (public verification)" {
    const io = testing.io;
    const n = P521.scalar.Scalar.zero.toBytes(.little);
    const p = P521.random(io);
    try testing.expectError(error.IdentityElement, p.mulPublic(n, .little));
}

test "p521 field element non-canonical encoding" {
    const s: [66]u8 = @splat(0xff);
    try testing.expectError(error.NonCanonical, P521.Fe.fromBytes(s, .little));
}

test "p521 neutral element decoding" {
    try testing.expectError(error.InvalidEncoding, P521.fromAffineCoordinates(.{ .x = P521.Fe.zero, .y = P521.Fe.zero }));
    try testing.expectError(error.InvalidEncoding, P521.fromAffineCoordinates(.{ .x = P521.Fe.zero, .y = P521.Fe.one }));
    try testing.expectError(error.IdentityElement, P521.identityElement.rejectIdentity());
}

test "p521 double base multiplication" {
    const p1 = P521.basePoint;
    const p2 = P521.basePoint.dbl();
    const s1: [66]u8 = @splat(0x01);
    const s2: [66]u8 = @splat(0x02);
    const pr1 = try P521.mulDoubleBasePublic(p1, s1, p2, s2, .little);
    const pr2 = (try p1.mul(s1, .little)).add(try p2.mul(s2, .little));
    try testing.expect(pr1.equivalent(pr2));
}

test "p521 double base multiplication with large scalars" {
    const p1 = P521.basePoint;
    const p2 = P521.basePoint.dbl();
    const s1: [66]u8 = @splat(0xee);
    const s2: [66]u8 = @splat(0xdd);
    const pr1 = try P521.mulDoubleBasePublic(p1, s1, p2, s2, .little);
    const pr2 = (try p1.mul(s1, .little)).add(try p2.mul(s2, .little));
    try testing.expect(pr1.equivalent(pr2));
}

test "p521 scalar inverse" {
    const expected = "00d696339a84f1835bdd2308dc4ca3cd56294a12f6b9e2598348df11f619979f8268ef929ca84de94584943d767a7a54a9094d979d600011427078afbc8b874487f0";
    var out: [66]u8 = undefined;
    _ = try std.fmt.hexToBytes(&out, expected);

    const scalar = try P521.scalar.Scalar.fromBytes(.{
        0x00, 0x1f, 0x84, 0xc5, 0x91, 0xe7, 0x9b, 0x44, 0xf3, 0xf2, 0x59, 0x8a, 0x57, 0x55, 0x57, 0x05,
        0x3b, 0x29, 0x1a, 0xb7, 0xd4, 0x1c, 0xd6, 0x8a, 0xf4, 0x89, 0xe7, 0x96, 0x27, 0xa8, 0xc2, 0x97,
        0x99, 0x71, 0x5d, 0x90, 0xe7, 0x4d, 0xe0, 0xc6, 0x7d, 0x04, 0xa6, 0xdf, 0x9a, 0x3e, 0x09, 0x2a,
        0xfe, 0x15, 0xf0, 0xdb, 0x2e, 0x64, 0x13, 0xe8, 0x6d, 0xcf, 0x01, 0x9e, 0xce, 0x2e, 0x19, 0xa8,
        0xb2, 0x02,
    }, .big);
    const inverse = scalar.invert();
    const inverse2 = inverse.invert();
    try testing.expectEqualSlices(u8, &out, &inverse.toBytes(.big));
    try testing.expect(inverse2.equivalent(scalar));
}

// Note: like P-256, the order of P-521 is 1 (mod 4), so `scalar.Scalar.sqrt` has
// no implementation to select and is a compile error. `Fe.sqrt` is unaffected:
// the field order is 3 (mod 4). Point decompression only needs the latter.
test "p521 field element square root" {
    const io = testing.io;
    const p = P521.random(io).affineCoordinates();
    const x2 = p.x.sq();
    try testing.expect(x2.isSquare());
    const x = try x2.sqrt();
    try testing.expect(x.sq().equivalent(x2));

    // The field order is 3 (mod 4), so -1 is a non-residue.
    const minus_one = P521.Fe.one.neg();
    try testing.expect(!minus_one.isSquare());
    try testing.expectError(error.NotSquare, minus_one.sqrt());
}

test "p521 scalar reduction" {
    // 2^512 < L, so a 64-byte input is already canonical and passes through.
    const s64: [64]u8 = @splat(0xab);
    const r64 = P521.scalar.reduce64(s64, .big);
    var expected64: [66]u8 = @splat(0xab);
    expected64[0] = 0;
    expected64[1] = 0;
    try testing.expectEqualSlices(u8, &expected64, &r64);

    // A 96-byte input does exercise the reduction.
    const s96: [96]u8 = @splat(0xcd);
    const r96 = P521.scalar.Scalar.fromBytes96(s96, .big).toBytes(.big);
    var expected96: [66]u8 = undefined;
    _ = try fmt.hexToBytes(&expected96, "01cdd0167214d29285f83e338859d61f35d8f5152ce39f3c23105ce6da9fce10ebd2aa4eac6cca8f507509db244bd9cc7770862b7eba862890f7f45ab93eb52dd7b7");
    try testing.expectEqualSlices(u8, &expected96, &r96);
}

test "p521 scalar parity" {
    try std.testing.expect(P521.scalar.Scalar.zero.isOdd() == false);
    try std.testing.expect(P521.scalar.Scalar.one.isOdd());
    try std.testing.expect(P521.scalar.Scalar.one.dbl().isOdd() == false);
}
