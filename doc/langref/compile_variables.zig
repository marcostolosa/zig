const builtin = @import("builtin");
const separator = if (builtin.target.os.tag == .windows) '\\' else '/';

// syntax
