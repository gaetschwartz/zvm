const std = @import("std");

/// Colors for the terminal.
pub const Colors = struct {
    pub const BLACK_BOLD = "\x1b[1;30m";
    pub const BLACK = "\x1b[30m";
    pub const RED_BOLD = "\x1b[1;31m";
    pub const RED = "\x1b[31m";
    pub const GREEN_BOLD = "\x1b[1;32m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW_BOLD = "\x1b[1;33m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE_BOLD = "\x1b[1;34m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA_BOLD = "\x1b[1;35m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN_BOLD = "\x1b[1;36m";
    pub const CYAN = "\x1b[36m";
    pub const WHITE_BOLD = "\x1b[1;37m";
    pub const WHITE = "\x1b[37m";
    pub const LIGHT_BLACK = "\x1b[90m";
    pub const LIGHT_GRAY = LIGHT_BLACK;
    pub const LIGHT_RED = "\x1b[91m";
    pub const LIGHT_GREEN = "\x1b[92m";
    pub const LIGHT_YELLOW = "\x1b[93m";
    pub const LIGHT_BLUE = "\x1b[94m";
    pub const LIGHT_MAGENTA = "\x1b[95m";
    pub const LIGHT_CYAN = "\x1b[96m";
    pub const LIGHT_WHITE = "\x1b[97m";
    pub const BOLD = "\x1b[1m";
    pub const FADE = "\x1b[2m";
    pub const RESET = "\x1b[0m";
    pub const RESET_BOLD = "\x1b[22m";
    pub const RESET_FADE = "\x1b[22m";
    pub const BG_RED = "\x1b[41m";
    pub const BG_GREEN = "\x1b[42m";
    pub const BG_YELLOW = "\x1b[43m";
    pub const BG_BLUE = "\x1b[44m";
    pub const BG_MAGENTA = "\x1b[45m";
    pub const BG_CYAN = "\x1b[46m";
    pub const BG_WHITE = "\x1b[47m";
    pub const BG_RESET = "\x1b[49m";
    pub const ITALIC = "\x1b[3m";
    pub const BLINK = "\x1b[5m";
    pub const REVERSE = "\x1b[7m";
    pub const UNDERLINE = "\x1b[4m";
    pub const STRIKETHROUGH = "\x1b[9m";

    // actually not used, but to represent colors looking like fg_0x123456 or bg_0x123456
    pub const fg_0x123456 = struct {};
    pub const bg_0x123456 = struct {};
};

// clear current line using ansi escape sequence
pub const CLEAR_LINE_ONLY = "\x1b[2K";
// SET CURSOR TO 0
pub const CURSOR_TO_0 = "\x1b[0G";
pub const CLEAR_LINE = CURSOR_TO_0 ++ CLEAR_LINE_ONLY;

pub const Color = struct {
    layer: enum { fg, bg } = .fg,
    color: u24,
};

/// Accepts an enum literal representing a color or a struct with enum literals as fields.
pub inline fn c(comptime colors: anytype) []const u8 {
    const type_info = @typeInfo(@TypeOf(colors));
    if (@TypeOf(colors) == Color) {
        return comptime colorOf(colors);
    }
    switch (type_info) {
        .Struct => {
            const fields = type_info.Struct.fields;
            var temp: []const u8 = "";
            inline for (fields) |field| {
                temp = temp ++ colorOf(@field(colors, field.name));
            }
            return temp;
        },
        else => return comptime colorOf(colors),
    }
}

fn colorOf(comptime color: anytype) []const u8 {
    if (@TypeOf(color) == Color) {
        const prefix = comptime switch (color.layer) {
            .fg => "38;2;",
            .bg => "48;2;",
        };
        return std.fmt.comptimePrint("\x1b[" ++ prefix ++ "{};{};{}m", .{ color.color >> 16, (color.color >> 8) & 0xff, color.color & 0xff });
    }

    var colorName: []const u8 = @typeName(@TypeOf(color));

    const tpInfo = @typeInfo(@TypeOf(color));
    switch (tpInfo) {
        .EnumLiteral => {
            const tagName = @tagName(color);
            colorName = tagName;

            // if tagname looks like fg_0x123456 or bg_0x123456, then we need to convert it to a string
            const isHexColor = comptime std.mem.startsWith(u8, tagName, "fg_0x") or std.mem.startsWith(u8, tagName, "bg_0x");
            if (isHexColor) {
                const coloru24 = tagName[5..];
                const n = std.fmt.parseUnsigned(u24, coloru24, 16) catch @compileError("Invalid hex color: " ++ tagName);
                const r = n >> 16;
                const g = (n >> 8) & 0xff;
                const b = n & 0xff;
                const prefix = comptime switch (tagName[0]) {
                    'f' => "38;2;",
                    'b' => "48;2;",
                    else => @compileError("Invalid color: " ++ tagName),
                };
                return std.fmt.comptimePrint("\x1b[" ++ prefix ++ "{};{};{}m", .{ r, g, b });
            }

            // make upercase
            const upperTagName = comptime upperCase(tagName);
            if (@hasDecl(Colors, upperTagName)) {
                return @field(Colors, upperTagName);
            }
        },
        else => {},
    }

    //? list all allowed colors in error message
    var allowedColors: []const u8 = "";
    // iterate through all the fields of Colors
    inline for (@typeInfo(Colors).Struct.decls) |decl| {
        allowedColors = allowedColors ++ decl.name ++ ", ";
    }
    allowedColors = allowedColors[0 .. allowedColors.len - 2];

    @compileError("Invalid color '" ++ colorName ++ "'. Allowed values are:\n" ++
        \\1. An enum literal from the Colors enum {
    ++ allowedColors ++ "}\n" ++
        \\2. A Color struct Color{ .layer = .fg, .color = 0x123456 }
    );
}

const ParseRes = union(enum) {
    res: u24,
    err: enum {
        InvalidCharacter,
    },
};

fn parseHexColor(comptime color: []const u8) ParseRes {
    var n: u24 = 0;
    inline for (color) |char| {
        n = n << 4;
        if (char >= '0' and char <= '9') {
            n = n | @as(u24, char - '0');
        } else if (char >= 'a' and char <= 'f') {
            n = n | @as(u24, char - 'a' + 10);
        } else if (char >= 'A' and char <= 'F') {
            n = n | @as(u24, char - 'A' + 10);
        } else {
            // @compileLog("Invalid character in color: ", char);
            return ParseRes{ .err = .InvalidCharacter };
        }
    }
    // @compileLog("color: ", color, " n = ", n);
    return ParseRes{ .res = n };
}

/// Accepts an enum literal representing a color or a struct with enum literals as fields.
/// The text will be colored with the given colors.
pub fn style(comptime text: []const u8, comptime colors: anytype) []const u8 {
    const type_info = @typeInfo(@TypeOf(colors));
    switch (type_info) {
        .Struct => {
            const fields = type_info.Struct.fields;
            var temp = text;
            for (fields) |field| {
                temp = colorOf(@field(colors, field.name)) ++ temp;
            }
            return temp ++ c(.RESET);
        },
        .EnumLiteral => return colorOf(colors) ++
            text ++
            c(.RESET),
        else => @compileError("Invalid type for colors: " ++ @typeName(@TypeOf(colors))),
    }
}

/// Make the text fade.
pub fn fade(comptime text: []const u8) []const u8 {
    return c(.FADE) ++ text ++ c(.RESET_FADE);
}

/// Make the text bold.
pub fn bold(comptime text: []const u8) []const u8 {
    return c(.BOLD) ++ text ++ c(.RESET_BOLD);
}

/// Make the text italic.
pub fn italic(comptime text: []const u8) []const u8 {
    return c(.ITALIC) ++ text ++ c(.RESET);
}

/// Make the text blink.
pub fn blink(comptime text: []const u8) []const u8 {
    return c(.BLINK) ++ text ++ c(.RESET);
}

fn upperCase(comptime text: []const u8) []const u8 {
    var out: [text.len]u8 = undefined;
    for (text, 0..) |char, i| {
        out[i] = std.ascii.toUpper(char);
    }
    return out[0..];
}

test "upperCase" {
    const text = "hello";
    const upper = upperCase(text);
    try std.testing.expectEqualStrings(upper, "HELLO");
}

test "fg_0x123456 & bg_0x123456" {
    const text = "hello";
    const fg = comptime c(.fg_0x123456);
    const bg = comptime c(.bg_0x123456);
    const reset = comptime c(.RESET);
    try std.testing.expectEqualStrings(fg ++ text ++ reset, "\x1b[38;2;18;52;86mhello\x1b[0m");
    try std.testing.expectEqualStrings(bg ++ text ++ reset, "\x1b[48;2;18;52;86mhello\x1b[0m");

    try std.testing.expectEqualStrings(c(.fg_0x123456), c(Color{ .color = 0x123456, .layer = .fg }));
    try std.testing.expectEqualStrings(c(.bg_0x123456), c(Color{ .color = 0x123456, .layer = .bg }));
}

test "all colors can be resolved" {
    comptime {
        _ = c(.BLUE_BOLD);
        _ = c(.BLUE);
        _ = c(.GREEN_BOLD);
        _ = c(.GREEN);
        _ = c(.RED_BOLD);
        _ = c(.RED);
        _ = c(.YELLOW_BOLD);
        _ = c(.YELLOW);
        _ = c(.CYAN_BOLD);
        _ = c(.CYAN);
        _ = c(.MAGENTA_BOLD);
        _ = c(.MAGENTA);
        _ = c(.WHITE_BOLD);
        _ = c(.WHITE);
        _ = c(.BOLD);
        _ = c(.FADE);
        _ = c(.RESET);
        _ = c(.RESET_BOLD);
        _ = c(.RESET_FADE);
        _ = c(.BG_RED);
        _ = c(.BG_GREEN);
        _ = c(.BG_YELLOW);
        _ = c(.BG_BLUE);
        _ = c(.BG_MAGENTA);
        _ = c(.BG_CYAN);
        _ = c(.BG_WHITE);
        _ = c(.BG_RESET);
        _ = c(.ITALIC);
        _ = c(.BLINK);
        _ = c(.UNDERLINE);
        _ = c(.REVERSE);
    }
}

test "ansi.c(.{...})" {
    try std.testing.expectEqualSlices(u8, "\x1b[3m\x1b[31m", comptime c(.{ .italic, .red }));
    try std.testing.expectEqualSlices(u8, "\x1b[31m\x1b[3m", comptime c(.{ .red, .italic }));
    try std.testing.expectEqualSlices(u8, "\x1b[3m", comptime c(.{.italic}));
    try std.testing.expectEqualSlices(u8, "", comptime c(.{}));
}

test "ansi.c(...)" {
    try std.testing.expectEqualSlices(u8, "\x1b[31m", comptime c(.red));
    try std.testing.expectEqualSlices(u8, "\x1b[3m", comptime c(.italic));
}

test "ansi.style(...) == ansi.c(...) ++ text ++ ansi.c(.RESET)" {
    try std.testing.expectEqualSlices(u8, comptime c(.red) ++ "hello" ++ c(.reset), comptime style("hello", .red));
    try std.testing.expectEqualSlices(u8, comptime c(.bold) ++ "hello" ++ c(.reset_bold), comptime bold("hello"));
    try std.testing.expectEqualSlices(u8, comptime c(.fade) ++ "hello" ++ c(.reset_fade), comptime fade("hello"));
    try std.testing.expectEqualSlices(u8, comptime c(.italic) ++ "hello" ++ c(.reset), comptime italic("hello"));
}
