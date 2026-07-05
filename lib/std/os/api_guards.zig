const builtin = @import("builtin");
const std = @import("../std.zig");

pub fn ensureOsTag(osTag: std.Target.Os.Tag) void {
    if (builtin.os.tag != osTag) {
        const targetAsString = @tagName(builtin.os.tag);
        const requiredTargetAsString = @tagName(osTag);
        const thisApiRequires = std.fmt.comptimePrint("This API requires target {s}. ", .{requiredTargetAsString});
        const youAreTargeting = std.fmt.comptimePrint("You are currently targeting {s}, which is incompatible.", .{targetAsString});
        @compileError(thisApiRequires ++ youAreTargeting);
    }
}
