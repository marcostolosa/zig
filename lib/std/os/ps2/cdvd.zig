//! Client for the `CDVD` S-command RPC server which owns several system devices,
//! including the RTC.

const std = @import("std");
const rpc = std.os.ps2.rpc;
const epoch = std.time.epoch;

pub const Client = rpc.Client(.cdvd_scmd);

/// Timestamp as read from the real-time clock. All fields are `BCD` encoded and in
/// `JST` (`UTC+9`) irrespective of the timezone settings.
pub const Clock = extern struct {
    /// Non-zero if the read failed
    stat: u8,
    second: u8,
    minute: u8,
    hour: u8,
    _pad: u8,
    day: u8,
    month: u8,
    /// Years since `2000`
    year: u8,

    /// Seconds since the Unix epoch in `UTC`
    pub fn epochSeconds(clk: Clock) u32 {
        const days_until_2000 = comptime blk: {
            var days: u32 = 0;
            for (epoch.epoch_year..2000) |y| days += epoch.getDaysInYear(y);

            break :blk days;
        };

        const year: epoch.Year = 2000 + @as(epoch.Year, bcd(clk.year));

        var days: u32 = days_until_2000;
        for (2000..year) |y| days += epoch.getDaysInYear(@intCast(y));
        for (1..bcd(clk.month)) |m| days += epoch.getDaysInMonth(year, @fromBackingInt(@intCast(m)));
        days += bcd(clk.day) - 1;

        const jst_offset = 9 * std.time.s_per_hour;
        return days * std.time.s_per_day + @as(u32, bcd(clk.hour)) * std.time.s_per_hour + @as(u32, bcd(clk.minute)) * std.time.s_per_min + bcd(clk.second) - jst_offset;
    }

    /// Decodes an `8`-bit `BCD` encoded value
    fn bcd(enc: u8) u8 {
        return (enc >> 4) * 10 + (enc & 0xf);
    }
};

const read_clock: rpc.Function = .{
    .server = .cdvd_scmd,
    .id = 1,
    .Args = void,
    .Result = extern struct {
        /// Set to `1` on success
        result: i32,
        clock: Clock,
        _pad: u32,
    },
};

pub fn readClock(client: Client) error{ClockUnavailable}!Clock {
    const r = client.callBlocking(read_clock, {});
    if (r.result != 1 or r.clock.stat != 0) return error.ClockUnavailable;

    return r.clock;
}
