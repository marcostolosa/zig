const std = @import("std");
const builtin = @import("builtin");
const expectEqual = std.testing.expectEqual;

const types = [_]type{ u4, u8, u16, u20, u29, u32, u64, u128 };

fn canHold(comptime T: type, bits: u16) bool {
    return @typeInfo(T).int.bits >= bits;
}

fn log2Case(comptime T: type, comptime expected: T, comptime actual: T) !void {
    try expectEqual(expected, @log2(actual));

    var runtime = actual;
    _ = &runtime;
    try expectEqual(expected, @log2(runtime));
}
fn log10Case(comptime T: type, comptime expected: T, comptime actual: T) !void {
    try expectEqual(expected, @log10(actual));

    var runtime = actual;
    _ = &runtime;
    try expectEqual(expected, @log10(runtime));
}

test "log2 scalar" {
    if (builtin.zig_backend == .stage2_llvm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_x86_64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    inline for (types) |T| {
        try log2Case(T, 0, @as(T, 0b1));
        try log2Case(T, 1, @as(T, 0b11));
        try log2Case(T, 2, @as(T, 0b101));
        try log2Case(T, 3, @as(T, 0b1000));

        if (comptime canHold(T, 8)) {
            try log2Case(T, 4, @as(T, 0b10100));
            try log2Case(T, 5, @as(T, 0b100000));
            try log2Case(T, 7, @as(T, 0b10000101));
            try log2Case(T, 7, @as(T, 0b10101101));
        }
        if (comptime canHold(T, 16)) {
            try log2Case(T, 10, @as(T, 0b10011001000));
            try log2Case(T, 12, @as(T, 0b1010111110011));
            try log2Case(T, 12, @as(T, 0b1101101010100));
            try log2Case(T, 14, @as(T, 0b100011001011110));
        }
        if (comptime canHold(T, 32)) {
            try log2Case(T, 25, @as(T, 0b11010010110011000011010010));
            try log2Case(T, 29, @as(T, 0b100101000000101011010111000001));
            try log2Case(T, 30, @as(T, 0b1110110110101110010111111010000));
            try log2Case(T, 31, @as(T, 0b11100100110101100101110000100111));
        }
        if (comptime canHold(T, 64)) {
            try log2Case(T, 56, @as(T, 0b110001001001100010110100100011011011101111110010011101001));
            try log2Case(T, 63, @as(T, 0b1010000100011100000001001111000000001000010101011010110010011110));
            try log2Case(T, 60, @as(T, 0b1000100010110101001011111000001001000100010111100000100010101));
            try log2Case(T, 60, @as(T, 0b1100110100111101000101101011110010001000011000110010101010110));
        }
        if (comptime canHold(T, 128)) {
            try log2Case(T, 121, @as(T, 0b10010110100110111111101001110001101101011110100011111100101100111010010110011011010111110110100101010100000011010000101111));
            try log2Case(T, 127, @as(T, 0b10010011011010000000010100110010001111011101101111101100100111111001111111000100111101011010000010011110011110011100000010000101));
            try log2Case(T, 123, @as(T, 0b1110000011101001111101010110101011110001011101001110100100001011111010011010001011010111111100000111110110010100101101010011));
            try log2Case(T, 125, @as(T, 0b110000101010010110001101111100011111010100111000101001110000110101100101101001000111010010010111110000110000101100001000101100));
        }
    }
}

test "log10 scalar" {
    if (builtin.zig_backend == .stage2_llvm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_x86_64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    inline for (types) |T| {
        try log10Case(T, 0, @as(T, 1));
        try log10Case(T, 0, @as(T, 6));
        try log10Case(T, 0, @as(T, 7));
        try log10Case(T, 1, @as(T, 11));

        if (comptime canHold(T, 8)) {
            try log10Case(T, 1, @as(T, 50));
            try log10Case(T, 1, @as(T, 86));
            try log10Case(T, 2, @as(T, 124));
            try log10Case(T, 2, @as(T, 169));
        }

        if (comptime canHold(T, 16)) {
            try log10Case(T, 3, @as(T, 2730));
            try log10Case(T, 4, @as(T, 12644));
            try log10Case(T, 4, @as(T, 35399));
            try log10Case(T, 4, @as(T, 13686));
        }

        if (comptime canHold(T, 32)) {
            try log10Case(T, 6, @as(T, 7746486));
            try log10Case(T, 8, @as(T, 168149813));
            try log10Case(T, 9, @as(T, 2532646425));
            try log10Case(T, 9, @as(T, 3752980442));
        }

        if (comptime canHold(T, 64)) {
            try log10Case(T, 15, @as(T, 2466283783456442));
            try log10Case(T, 17, @as(T, 153329152225227434));
            try log10Case(T, 19, @as(T, 15277210520041664936));
            try log10Case(T, 19, @as(T, 18178586238655859796));
        }

        if (comptime canHold(T, 128)) {
            try log10Case(T, 38, @as(T, 0b10110100000011100000000111000000110011101010111000110011010011100100100100100011111111110101010110011101111111010110000010110001));
            try log10Case(T, 37, @as(T, 0b111111110001000010100101000101010101111000010001100010001111100010100000110111010111100010000101100110000100101001110110111001));
            try log10Case(T, 36, @as(T, 0b1011010010101011000100010101000001011001110110101010010001001010111111000010111010100010001100101101100111000110100100110));
            try log10Case(T, 36, @as(T, 0b11011001111010100010110110011101000000100100110101101110111100100001101011100000110101011101010011010100000000011100010011));
        }
    }
}

test "log2 vector" {
    if (builtin.zig_backend == .stage2_llvm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_x86_64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    try log2Case(@Vector(2, u4), .{ 3, 3 }, .{ 10, 8 });
    try log2Case(@Vector(4, u4), .{ 2, 2, 3, 3 }, .{ 7, 5, 15, 8 });
    try log2Case(@Vector(7, u4), .{ 3, 2, 2, 1, 1, 2, 2 }, .{ 12, 5, 5, 2, 3, 5, 6 });
    try log2Case(@Vector(8, u4), .{ 1, 3, 3, 2, 3, 3, 3, 3 }, .{ 2, 12, 15, 6, 14, 12, 9, 11 });

    try log2Case(@Vector(2, u8), .{ 7, 6 }, .{ 186, 87 });
    try log2Case(@Vector(4, u8), .{ 7, 5, 6, 7 }, .{ 237, 37, 125, 150 });
    try log2Case(@Vector(7, u8), .{ 4, 7, 7, 5, 7, 7, 6 }, .{ 20, 213, 235, 40, 157, 216, 84 });
    try log2Case(@Vector(8, u8), .{ 6, 7, 7, 6, 7, 6, 6, 5 }, .{ 100, 187, 142, 76, 195, 106, 111, 63 });

    try log2Case(@Vector(2, u16), .{ 12, 14 }, .{ 4182, 18158 });
    try log2Case(@Vector(4, u16), .{ 14, 15, 14, 15 }, .{ 26896, 65034, 19663, 48837 });
    try log2Case(@Vector(7, u16), .{ 15, 14, 15, 15, 15, 9, 13 }, .{ 44410, 23067, 58529, 40819, 45776, 953, 14165 });
    try log2Case(@Vector(8, u16), .{ 15, 13, 14, 12, 15, 14, 12, 14 }, .{ 33431, 12521, 32562, 4917, 64484, 30886, 7046, 27794 });

    try log2Case(@Vector(2, u29), .{ 27, 25 }, .{ 149585801, 58042017 });
    try log2Case(@Vector(4, u29), .{ 28, 28, 28, 28 }, .{ 379747321, 489078982, 516067302, 497104130 });
    try log2Case(@Vector(7, u29), .{ 28, 28, 27, 28, 24, 27, 26 }, .{ 287650597, 300186323, 203467827, 506656004, 30420594, 184142996, 89761960 });
    try log2Case(@Vector(8, u29), .{ 27, 28, 28, 27, 26, 28, 28, 28 }, .{ 176302299, 300695250, 461498875, 137518700, 96868075, 375905164, 344273402, 453496088 });

    try log2Case(@Vector(2, u32), .{ 31, 30 }, .{ 2888403706, 1445384865 });
    try log2Case(@Vector(4, u32), .{ 31, 31, 31, 30 }, .{ 2913187144, 3113364803, 2379331873, 2013243861 });
    try log2Case(@Vector(7, u32), .{ 30, 31, 30, 29, 31, 29, 30 }, .{ 1742014216, 3853135549, 1454111479, 541321038, 2212806062, 574388002, 1108381520 });
    try log2Case(@Vector(8, u32), .{ 31, 31, 31, 31, 30, 31, 29, 30 }, .{ 4017518260, 2876709677, 3447896435, 4078041531, 1621149675, 2317272119, 1000365626, 1906847916 });

    try log2Case(@Vector(2, u64), .{ 63, 60 }, .{ 11810596087924995315, 1505890563231392909 });
    try log2Case(@Vector(4, u64), .{ 63, 61, 62, 61 }, .{ 9423055505803885173, 3554256207185123588, 7670173154200242564, 2430816280576980694 });
    try log2Case(@Vector(7, u64), .{ 63, 61, 62, 63, 63, 63, 62 }, .{ 11271962389864980645, 3075238014679252172, 9159846130557506681, 16672346515825274018, 14162889928581956007, 9908686833521055263, 7438994521811361186 });
    try log2Case(@Vector(8, u64), .{ 63, 63, 61, 62, 61, 61, 61, 63 }, .{ 15304969000552073828, 11990943349316385447, 3500515094643725540, 9086324586907932853, 4301701380845919517, 3750015110924413444, 2882825106061929588, 13459565266828320500 });

    try log2Case(@Vector(2, u128), .{ 125, 125 }, .{ 45813631246574365853786245123157534275, 46595219547382151028183545000465549515 });
    try log2Case(@Vector(4, u128), .{ 127, 127, 124, 127 }, .{ 192650539885179930635099126787298648073, 192476376299047368219982254635011887993, 24871142354983766895627638486231762776, 277551850517725214665841966150531841139 });
    try log2Case(@Vector(7, u128), .{ 127, 126, 126, 125, 126, 127, 127 }, .{ 175343200930523385041525095647492968064, 110232815734987263329738800225874762907, 165273943585296244196078759232016834806, 45667246843584179250601103342254844265, 169967217632248511999820030561405284730, 181422318393555814845986904525774236141, 275037580967407543686176830980199382056 });
    try log2Case(@Vector(8, u128), .{ 127, 125, 127, 127, 126, 127, 127, 126 }, .{ 205210720917467741008597636221445428648, 77884202834959065474850942157037972321, 214008109475342591611594772105335853290, 328979744390444352129820326981677580788, 140787705274203224314372873117495307842, 278723917746840505276129860635303359925, 172042781476473064268850200809214865511, 148176620004539658496249044207921799423 });
}

test "log10 vector" {
    if (builtin.zig_backend == .stage2_llvm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_x86_64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    try log10Case(@Vector(2, u4), .{ 0, 1 }, .{ 7, 12 });
    try log10Case(@Vector(4, u4), .{ 1, 0, 0, 0 }, .{ 12, 2, 5, 7 });
    try log10Case(@Vector(7, u4), .{ 0, 0, 1, 0, 0, 1, 1 }, .{ 5, 7, 10, 8, 4, 13, 13 });
    try log10Case(@Vector(8, u4), .{ 1, 0, 0, 0, 0, 0, 1, 1 }, .{ 13, 2, 4, 2, 3, 2, 11, 14 });

    try log10Case(@Vector(2, u8), .{ 2, 1 }, .{ 202, 68 });
    try log10Case(@Vector(4, u8), .{ 2, 2, 2, 2 }, .{ 234, 162, 130, 126 });
    try log10Case(@Vector(7, u8), .{ 1, 2, 1, 2, 2, 1, 2 }, .{ 35, 145, 29, 156, 200, 12, 217 });
    try log10Case(@Vector(8, u8), .{ 2, 1, 1, 2, 1, 2, 1, 2 }, .{ 230, 64, 42, 233, 21, 231, 40, 202 });

    try log10Case(@Vector(2, u16), .{ 4, 3 }, .{ 16632, 8523 });
    try log10Case(@Vector(4, u16), .{ 2, 4, 3, 4 }, .{ 957, 22412, 9534, 54942 });
    try log10Case(@Vector(7, u16), .{ 3, 4, 3, 4, 4, 4, 4 }, .{ 2112, 44353, 2779, 58581, 20673, 46261, 14163 });
    try log10Case(@Vector(8, u16), .{ 4, 4, 4, 4, 4, 4, 4, 4 }, .{ 52433, 12834, 64704, 60809, 34791, 49285, 56154, 41814 });

    try log10Case(@Vector(2, u29), .{ 8, 7 }, .{ 395568740, 76913497 });
    try log10Case(@Vector(4, u29), .{ 8, 8, 8, 8 }, .{ 215279550, 356853060, 368634239, 525991965 });
    try log10Case(@Vector(7, u29), .{ 7, 8, 8, 7, 6, 8, 8 }, .{ 75970206, 457325698, 406870681, 28988493, 9102675, 480062868, 216681207 });
    try log10Case(@Vector(8, u29), .{ 8, 8, 8, 8, 8, 8, 8, 8 }, .{ 144813446, 443091925, 116499270, 492698198, 190535137, 342552601, 376113701, 153931234 });

    try log10Case(@Vector(2, u32), .{ 9, 9 }, .{ 2736130997, 1526245150 });
    try log10Case(@Vector(4, u32), .{ 9, 9, 8, 9 }, .{ 2812444075, 1524396919, 276963733, 3875171099 });
    try log10Case(@Vector(7, u32), .{ 9, 8, 9, 9, 8, 8, 9 }, .{ 4111669260, 514325912, 4152184279, 2676291750, 348684151, 276095052, 1597861454 });
    try log10Case(@Vector(8, u32), .{ 9, 9, 9, 9, 9, 9, 9, 9 }, .{ 2479913575, 1975372620, 2896674708, 2015769468, 3656914213, 3089608619, 1834707523, 2026983605 });

    try log10Case(@Vector(2, u64), .{ 18, 19 }, .{ 3358985154754608602, 17345168687413325149 });
    try log10Case(@Vector(4, u64), .{ 19, 18, 18, 19 }, .{ 11525649942230835339, 1521733984298943951, 1756498260566812399, 16190935261970354358 });
    try log10Case(@Vector(7, u64), .{ 19, 18, 18, 19, 18, 18, 19 }, .{ 13022630670711327587, 5204072673293729822, 6620070925083307646, 10592860363181578057, 6938552746432044253, 5218397573639948073, 11628537294906896306 });
    try log10Case(@Vector(8, u64), .{ 18, 18, 19, 18, 18, 19, 17, 18 }, .{ 8647780949212056189, 6119556334169656177, 17108066163248412379, 9279791566924920363, 4296191241974980782, 16988075928825311614, 153700418228408913, 6258130254072610377 });

    try log10Case(@Vector(2, u128), .{ 38, 38 }, .{ 190457884907006843799119678442007174743, 127737100255618677460867496614904785464 });
    try log10Case(@Vector(4, u128), .{ 38, 38, 38, 37 }, .{ 320985096752258233830620641077353084714, 104120975153448773985973744936261317505, 271480383334788927501892174988771653292, 13170336538369714612513329577199852849 });
    try log10Case(@Vector(7, u128), .{ 38, 37, 37, 37, 37, 37, 38 }, .{ 163241590776945460828666230670525312120, 34311072550166081242089266775287811131, 99283181373128151785114323016766545881, 51588033808812513463647559285158640132, 99155965269512498719743145039255849888, 88646059215214346476814399796912213733, 157262250475973820392894629156132974200 });
    try log10Case(@Vector(8, u128), .{ 37, 38, 38, 38, 37, 38, 37, 38 }, .{ 70955832113703725194905545975063887241, 338307533133980797844239016835215336625, 307934334347636795706401589394259507009, 302543597979302146201437933292085745329, 55613917671630940942475818460272633591, 259387871354890000700421772880352904245, 52181927482808212901261291619826867065, 187082663075887705982463961753021000114 });
}

fn log2ResultTypeCase(comptime Expected: type, comptime Operand: type) !void {
    try expectEqual(Expected, @TypeOf(@log2(@as(Operand, 1))));
}

fn log10ResultTypeCase(comptime Expected: type, comptime Operand: type) !void {
    try expectEqual(Expected, @TypeOf(@log10(@as(Operand, 1))));
}

test "log2 result type" {
    try comptime log2ResultTypeCase(u6, u64);
    try comptime log2ResultTypeCase(u5, u32);
    try comptime log2ResultTypeCase(u5, u29);
    try comptime log2ResultTypeCase(u4, u16);
    try comptime log2ResultTypeCase(u3, u8);
    try comptime log2ResultTypeCase(u2, u4);
    try comptime log2ResultTypeCase(u1, u2);
    try comptime log2ResultTypeCase(u0, u1);
}

test "log10 result type" {
    try comptime log10ResultTypeCase(u5, u64);
    try comptime log10ResultTypeCase(u4, u32);
    try comptime log10ResultTypeCase(u4, u29);
    try comptime log10ResultTypeCase(u3, u16);
    try comptime log10ResultTypeCase(u2, u8);
    try comptime log10ResultTypeCase(u1, u4);
    try comptime log10ResultTypeCase(u0, u2);
    try comptime log10ResultTypeCase(u0, u1);
}

test "log2 comptime zero" {
    var a: u1 = 1;
    _ = &a;
    try comptime expectEqual(0, @log2(a));
}

test "log10 comptime zero" {
    var a: u3 = 7;
    _ = &a;
    try comptime expectEqual(0, @log10(a));
}
