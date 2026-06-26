const std = @import("std");
const builtin = @import("builtin");

const config = @import("config");

pub fn main() void {
    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;

    for (builtin.test_functions) |test_fn| {
        if (config.verbose) {
            std.debug.print("{s}...", .{test_fn.name});
        }

        if (test_fn.func()) |_| {
            ok_count += 1;
            if (config.verbose) {
                std.debug.print("OK\n", .{});
            }
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                if (config.verbose) {
                    std.debug.print("SKIP\n", .{});
                }
            },
            else => {
                fail_count += 1;
                if (config.verbose) {
                    std.debug.print("FAIL ({t})\n", .{err});
                }
            },
        }
    }

    std.debug.print("{d} OK, {d} SKIP, {d} FAIL", .{ ok_count, skip_count, fail_count });

    if (ok_count != 1) {
        std.process.exit(1);
    }
}

test "pass" {}

test "fail" {
    return error.TestFailed;
}

test "skip" {
    return error.SkipZigTest;
}
