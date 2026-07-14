const std = @import("std");
const common = @import("../common.zig");

const Field = common.Field;

pub const Fe = Field(.{
    .fiat = @import("p521_64.zig"),
    .field_order = 6864797660130609714981900799081393217269435300143305409394463459185543183397656052122559640661454554977296311391480858037121987999716643812574028291115057151,
    .field_bits = 521,
    .saturated_bits = 521,
    .encoded_length = 66,
});
