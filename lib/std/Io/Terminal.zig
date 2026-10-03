/// Abstraction for writing to a stream that might support terminal escape
/// codes.
const Terminal = @This();

const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const std = @import("std");
const windows = std.os.windows;
const Io = std.Io;
const File = std.Io.File;

writer: *Io.Writer,
mode: Mode,

pub const Effect = enum(u8) {
    reset = 0,
    bold = 1,
    dim = 2,
    italic = 3,
    underline = 4,
    slow_blink = 5,
    fast_blink = 6,
    reverse = 7,
    hidden = 8,
    strikethrough = 9,

    fn effects_code_windows(e: Effect, wa: Mode.WindowsApi) SetColorError!windows.WORD {
        return switch (e) {
            .reset => wa.reset_attributes,
            .bold => windows.FOREGROUND_WHITE,
            .dim => windows.FOREGROUND_GREY,
            .underline => windows.COMMON_LVB_UNDERSCORE,
            .reverse => windows.COMMON_LVB_REVERSE_VIDEO,
            else => SetColorError.LegacyWindowsUnsupported,
        };
    }
};

pub const Color = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,

    fn foreground_code(c: Color) u8 {
        return @backingInt(c);
    }

    fn background_code(c: Color) u8 {
        return @backingInt(c) + 10;
    }

    fn foreground_code_windows(c: Color) windows.WORD {
        return switch (c) {
            .black => windows.FOREGROUND_BLACK,
            .red => windows.FOREGROUND_RED,
            .green => windows.FOREGROUND_GREEN,
            .yellow => windows.FOREGROUND_YELLOW,
            .blue => windows.FOREGROUND_BLUE,
            .magenta => windows.FOREGROUND_MAGENTA,
            .cyan => windows.FOREGROUND_CYAN,
            .white => windows.FOREGROUND_LIGHT_GREY,
            .bright_black => windows.FOREGROUND_GREY,
            .bright_red => windows.FOREGROUND_LIGHT_RED,
            .bright_green => windows.FOREGROUND_LIGHT_GREEN,
            .bright_yellow => windows.FOREGROUND_LIGHT_YELLOW,
            .bright_blue => windows.FOREGROUND_LIGHT_BLUE,
            .bright_magenta => windows.FOREGROUND_LIGHT_MAGENTA,
            .bright_cyan => windows.FOREGROUND_LIGHT_CYAN,
            .bright_white => windows.FOREGROUND_WHITE,
        };
    }

    fn background_code_windows(c: Color) windows.WORD {
        return switch (c) {
            .black => windows.BACKGROUND_BLACK,
            .red => windows.BACKGROUND_RED,
            .green => windows.BACKGROUND_GREEN,
            .yellow => windows.BACKGROUND_YELLOW,
            .blue => windows.BACKGROUND_BLUE,
            .magenta => windows.BACKGROUND_MAGENTA,
            .cyan => windows.BACKGROUND_CYAN,
            .white => windows.BACKGROUND_LIGHT_GREY,
            .bright_black => windows.BACKGROUND_GREY,
            .bright_red => windows.BACKGROUND_LIGHT_RED,
            .bright_green => windows.BACKGROUND_LIGHT_GREEN,
            .bright_yellow => windows.BACKGROUND_LIGHT_YELLOW,
            .bright_blue => windows.BACKGROUND_LIGHT_BLUE,
            .bright_magenta => windows.BACKGROUND_LIGHT_MAGENTA,
            .bright_cyan => windows.BACKGROUND_LIGHT_CYAN,
            .bright_white => windows.BACKGROUND_WHITE,
        };
    }
};

pub const Style = struct {
    text_effects: []const Effect = &.{},
    foreground_color: ?Color = null,
    background_color: ?Color = null,

    fn write_windows(self: Style, wa: Mode.WindowsApi, t: *Terminal) SetColorError!void {
        const foreground: Color = self.foreground_color orelse Color.black;
        const background: Color = self.background_color orelse Color.black;
        var effects: windows.WORD = 0x0000;
        for (self.text_effects) |e| {
            effects |= try e.effects_code_windows(wa);
        }
        const attributes: windows.WORD = foreground.foreground_code_windows() | background.background_code_windows() | effects;
        try t.writer.flush();
        var set_text_attribute = windows.CONSOLE.USER_IO.SET_TEXT_ATTRIBUTE(attributes);
        switch (try set_text_attribute.operate(wa.io, wa.file)) {
            .SUCCESS => {},
            else => |status| return windows.unexpectedStatus(status),
        }
    }

    fn write_ansi(self: Style, w: *std.Io.Writer) SetColorError!void {
        try w.writeAll("\x1b[");
        var first = true; // Means that no color/effect has been set yet

        for (self.text_effects) |e| try param(w, &first, @backingInt(e));
        if (self.foreground_color) |f| try param(w, &first, f);
        if (self.background_color) |b| try param(w, &first, b);
    }

    fn param(w: *Io.Writer, first: *bool, n: u8) SetColorError!void {
        if (!first.*) try w.writeByte(';');
        first.* = false;
        try w.print("{d}", .{n});
    }
};

/// Sets terminal foreground, background, and effects, using a `Style`
pub fn setStyle(t: Terminal, style: Style) SetColorError!void {
    switch (t.mode) {
        .no_color => return,
        .escape_codes => style.write_ansi(t.writer),
        .windows_api => |wa| style.write_windows(wa, &t),
    }
}

pub const Mode = union(enum) {
    no_color,
    escape_codes,
    windows_api: WindowsApi,

    pub const WindowsApi = if (!is_windows) noreturn else struct {
        io: Io,
        file: File,
        reset_attributes: u16,
    };

    /// Detect suitable TTY configuration options for the given file (commonly
    /// stdout/stderr).
    ///
    /// Will attempt to enable ANSI escape code support if necessary/possible.
    ///
    /// * `NO_COLOR` indicates whether "NO_COLOR" environment variable is
    ///   present and non-empty.
    /// * `CLICOLOR_FORCE` indicates whether "CLICOLOR_FORCE" environment
    ///   variable is present and non-empty.
    pub fn detect(io: Io, file: File, NO_COLOR: bool, CLICOLOR_FORCE: bool) Io.Cancelable!Mode {
        const force_color: ?bool = if (NO_COLOR) false else if (CLICOLOR_FORCE) true else null;
        if (force_color == false) return .no_color;

        if (file.enableAnsiEscapeCodes(io)) |_| {
            return .escape_codes;
        } else |err| switch (err) {
            error.Canceled => |e| return e,
            error.NotTerminalDevice, error.Unexpected => {},
        }

        if (is_windows and try file.isTty(io)) {
            var get_console_info = std.os.windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
            switch (try get_console_info.operate(io, file)) {
                .SUCCESS => return .{ .windows_api = .{
                    .io = io,
                    .file = file,
                    .reset_attributes = get_console_info.Data.wAttributes,
                } },
                else => {},
            }
        }
        return if (force_color == true) .escape_codes else .no_color;
    }
};

pub const SetColorError = Io.Cancelable || Io.UnexpectedError || Io.Writer.Error || error{LegacyWindowsUnsupported};

pub const OldColor = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    bold,
    dim,
    reset,
};

/// DEPRECIATED: Use 'Terminal.setStyle()' instead
pub fn setColor(t: Terminal, color: OldColor) SetColorError!void {
    switch (t.mode) {
        .no_color => return,
        .escape_codes => {
            const color_string = switch (color) {
                .black => "\x1b[30m",
                .red => "\x1b[31m",
                .green => "\x1b[32m",
                .yellow => "\x1b[33m",
                .blue => "\x1b[34m",
                .magenta => "\x1b[35m",
                .cyan => "\x1b[36m",
                .white => "\x1b[37m",
                .bright_black => "\x1b[90m",
                .bright_red => "\x1b[91m",
                .bright_green => "\x1b[92m",
                .bright_yellow => "\x1b[93m",
                .bright_blue => "\x1b[94m",
                .bright_magenta => "\x1b[95m",
                .bright_cyan => "\x1b[96m",
                .bright_white => "\x1b[97m",
                .bold => "\x1b[1m",
                .dim => "\x1b[2m",
                .reset => "\x1b[0m",
            };
            try t.writer.writeAll(color_string);
        },
        .windows_api => |wa| {
            const attributes: windows.WORD = switch (color) {
                .black => 0,
                .red => windows.FOREGROUND_RED,
                .green => windows.FOREGROUND_GREEN,
                .yellow => windows.FOREGROUND_YELLOW,
                .blue => windows.FOREGROUND_BLUE,
                .magenta => windows.FOREGROUND_MAGENTA,
                .cyan => windows.FOREGROUND_CYAN,
                .white => windows.FOREGROUND_LIGHT_GREY,
                .bright_black => windows.FOREGROUND_DARK_GREY,
                .bright_red => windows.FOREGROUND_LIGHT_RED,
                .bright_green => windows.FOREGROUND_LIGHT_GREEN,
                .bright_yellow => windows.FOREGROUND_LIGHT_YELLOW,
                .bright_blue => windows.FOREGROUND_LIGHT_BLUE,
                .bright_magenta => windows.FOREGROUND_LIGHT_RED,
                .bright_cyan => windows.FOREGROUND_LIGHT_CYAN,
                .bright_white, .bold => windows.FOREGROUND_WHITE,
                // "dim" is not supported using basic character attributes, but let's still make it do *something*.
                // This matches the old behavior of TTY.Color before the bright variants were added.
                .dim => windows.FOREGROUND_DARK_GREY,
                .reset => wa.reset_attributes,
            };
            try t.writer.flush();
            var set_text_attribute = windows.CONSOLE.USER_IO.SET_TEXT_ATTRIBUTE(attributes);
            switch (try set_text_attribute.operate(wa.io, wa.file)) {
                .SUCCESS => {},
                else => |status| return windows.unexpectedStatus(status),
            }
        },
    }
}
