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

pub const Style = struct {
    text_effects: Style.Effects,
    foreground_color: ?Style.Color = null,
    background_color: ?Style.Color = null,

    pub const Effects = packed struct {
        reset: bool = false,
        bold: bool = false,
        dim: bool = false,
        italic: bool = false,
        underline: bool = false,
        slow_blink: bool = false,
        fast_blink: bool = false,
        reverse: bool = false,
        hidden: bool = false,
        strikethrough: bool = false,

        fn isEmpty(e: Effects) bool {
            return !(e.reset or e.bold or e.dim or e.italic or e.underline or e.slow_blink or e.fast_blink or e.reverse or e.hidden or e.strikethrough);
        }

        fn writeAnsiParams(e: Style.Effects, w: *std.Io.Writer, first: *bool) !void {
            if (e.reset) try Style.param(w, first, 0);
            if (e.bold) try Style.param(w, first, 1);
            if (e.dim) try Style.param(w, first, 2);
            if (e.italic) try Style.param(w, first, 3);
            if (e.underline) try Style.param(w, first, 4);
            if (e.slow_blink) try Style.param(w, first, 5);
            if (e.fast_blink) try Style.param(w, first, 6);
            if (e.reverse) try Style.param(w, first, 7);
            if (e.hidden) try Style.param(w, first, 8);
            if (e.strikethrough) try Style.param(w, first, 9);
        }

        fn effectsCodeWindows(e: Effects) windows.WORD {
            var effect_code: windows.WORD = 0;
            if (e.bold) effect_code |= windows.FOREGROUND_BRIGHT_WHITE;
            if (e.dim) effect_code |= windows.FOREGROUND_GREY;
            if (e.underline) effect_code |= windows.COMMON_LVB_UNDERSCORE;
            if (e.reverse) effect_code |= windows.COMMON_LVB_REVERSE_VIDEO;
            return effect_code;
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

        fn foregroundCode(c: Style.Color) u8 {
            return @backingInt(c);
        }

        fn backgroundCode(c: Style.Color) u8 {
            return @backingInt(c) + 10;
        }

        fn foregroundCodeWindows(c: Style.Color) windows.WORD {
            return switch (c) {
                .black => windows.FOREGROUND_BLACK,
                .red => windows.FOREGROUND_RED,
                .green => windows.FOREGROUND_GREEN,
                .yellow => windows.FOREGROUND_YELLOW,
                .blue => windows.FOREGROUND_BLUE,
                .magenta => windows.FOREGROUND_MAGENTA,
                .cyan => windows.FOREGROUND_CYAN,
                .white => windows.FOREGROUND_WHITE,
                .bright_black => windows.FOREGROUND_GREY,
                .bright_red => windows.FOREGROUND_BRIGHT_RED,
                .bright_green => windows.FOREGROUND_BRIGHT_GREEN,
                .bright_yellow => windows.FOREGROUND_BRIGHT_YELLOW,
                .bright_blue => windows.FOREGROUND_BRIGHT_BLUE,
                .bright_magenta => windows.FOREGROUND_BRIGHT_MAGENTA,
                .bright_cyan => windows.FOREGROUND_BRIGHT_CYAN,
                .bright_white => windows.FOREGROUND_BRIGHT_WHITE,
            };
        }

        fn backgroundCodeWindows(c: Style.Color) windows.WORD {
            return switch (c) {
                .black => windows.BACKGROUND_BLACK,
                .red => windows.BACKGROUND_RED,
                .green => windows.BACKGROUND_GREEN,
                .yellow => windows.BACKGROUND_YELLOW,
                .blue => windows.BACKGROUND_BLUE,
                .magenta => windows.BACKGROUND_MAGENTA,
                .cyan => windows.BACKGROUND_CYAN,
                .white => windows.BACKGROUND_WHITE,
                .bright_black => windows.BACKGROUND_GREY,
                .bright_red => windows.BACKGROUND_BRIGHT_RED,
                .bright_green => windows.BACKGROUND_BRIGHT_GREEN,
                .bright_yellow => windows.BACKGROUND_BRIGHT_YELLOW,
                .bright_blue => windows.BACKGROUND_BRIGHT_BLUE,
                .bright_magenta => windows.BACKGROUND_BRIGHT_MAGENTA,
                .bright_cyan => windows.BACKGROUND_BRIGHT_CYAN,
                .bright_white => windows.BACKGROUND_BRIGHT_WHITE,
            };
        }
    };
    pub const reset = Style{ .text_effects = .{ .reset = true } };

    pub fn new_bold(fg: Style.Color) Style {
        return Style{ .foreground_color = fg, .text_effects = .{ .bold = true } };
    }

    pub fn new(fg: ?Style.Color, bg: ?Style.Color, effects: Style.Effects) Style {
        return Style{ .foreground_color = fg, .background_color = bg, .text_effects = effects };
    }

    fn isEmpty(self: Style) bool {
        return (self.foreground_color == null and self.background_color == null and self.text_effects.isEmpty());
    }

    fn windowsAttributesCall(wa: Mode.WindowsApi, attributes: windows.WORD, w: *std.Io.Writer) SetColorError!void {
        try w.flush();
        var set_text_attribute = windows.CONSOLE.USER_IO.SET_TEXT_ATTRIBUTE(attributes);
        switch (try set_text_attribute.operate(wa.io, wa.file)) {
            .SUCCESS => {},
            else => |status| return windows.unexpectedStatus(status),
        }
    }

    fn writeWindows(self: Style, wa: Mode.WindowsApi, w: *std.Io.Writer) SetColorError!void {
        if (!self.foreground_color and !self.background_color and self.text_effects == .{ .reset = true }) {
            return self.windowsAttributesCall(wa, wa.reset_attributes, w);
        } else if (self.text_effects == .{ .reset = true }) {
            try self.windowsAttributesCall(wa, wa.reset_attributes, w);
        }
        const fg = if (self.foreground_color) |c| c.foregroundCodeWindows() else wa.reset_attributes & 0x000F;
        const bg = if (self.background_color) |c| c.backgroundCodeWindows() else wa.reset_attributes & 0x00F0;
        const effects = self.text_effects.effectsCodeWindows();
        const attributes: windows.WORD = fg | bg | effects;
        return self.windowsAttributesCall(wa, attributes, w);
    }

    fn writeAnsi(self: Style, w: *std.Io.Writer) SetColorError!void {
        try w.writeAll("\x1b[");
        var first = true; // Means that no color/effect has been set yet

        try self.text_effects.writeAnsiParams(w, &first);
        if (self.foreground_color) |f| try param(w, &first, f.foregroundCode());
        if (self.background_color) |b| try param(w, &first, b.backgroundCode());
        try w.writeAll("m");
    }

    fn param(w: *Io.Writer, first: *bool, n: u8) SetColorError!void {
        if (!first.*) try w.writeByte(';');
        first.* = false;
        try w.print("{d}", .{n});
    }
};

/// Sets terminal foreground, background, and effects, using a `Style`.
/// If using `Mode.windows_api` then italic, blink, hidden, and strikethrough
/// are unsupported and do nothing.
pub fn setStyle(t: Terminal, style: Style) SetColorError!void {
    if (!style.isEmpty()) {
        switch (t.mode) {
            .no_color => return,
            .escape_codes => try style.writeAnsi(t.writer),
            .windows_api => |wa| try style.writeWindows(wa, t.writer),
        }
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

pub const SetColorError = Io.Cancelable || Io.UnexpectedError || Io.Writer.Error;

/// Deprecated; See `Style.Color`
pub const Color = enum {
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

/// Deprecated; See 'Terminal.setStyle()'
pub fn setColor(t: Terminal, color: Color) SetColorError!void {
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
                .white => windows.FOREGROUND_WHITE,
                .bright_black => windows.FOREGROUND_GREY,
                .bright_red => windows.FOREGROUND_BRIGHT_RED,
                .bright_green => windows.FOREGROUND_BRIGHT_GREEN,
                .bright_yellow => windows.FOREGROUND_BRIGHT_YELLOW,
                .bright_blue => windows.FOREGROUND_BRIGHT_BLUE,
                .bright_magenta => windows.FOREGROUND_BRIGHT_MAGENTA,
                .bright_cyan => windows.FOREGROUND_BRIGHT_CYAN,
                .bright_white, .bold => windows.FOREGROUND_BRIGHT_WHITE,
                // "dim" is not supported using basic character attributes, but let's still make it do *something*.
                // This matches the old behavior of TTY.Color before the bright variants were added.
                .dim => windows.FOREGROUND_GREY,
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
