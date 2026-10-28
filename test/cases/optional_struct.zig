const Item = struct { v: f64 };

fn minItem(items: []const Item) ?Item {
    var acc: ?Item = null;
    for (items) |it| {
        acc = min(acc, it);
    }
    return acc;
}

fn min(acc: ?Item, v: Item) Item {
    if (acc) |av| {
        if (v.v < av.v) return v;
        return av;
    }
    return v;
}

pub fn main() void {
    const vals = [_]Item{ .{ .v = 3 }, .{ .v = 1 }, .{ .v = 4 } };
    if ((minItem(vals[0..]) orelse unreachable).v != 1) unreachable;
}

// run
//
