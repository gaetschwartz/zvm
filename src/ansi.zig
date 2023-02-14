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
    pub const UNDERLINE = "\x1b[4m";
    pub const REVERSE = "\x1b[7m";
};
/// Accepts an enum literal representing a color or a struct with enum literals as fields.
pub fn c(comptime colors: anytype) []const u8 {
    const type_info = @typeInfo(@TypeOf(colors));
    switch (type_info) {
        .Struct => {
            const fields = comptime type_info.Struct.fields;
            var temp: []const u8 = "";
            for (fields) |field| {
                temp = temp ++ colorOfEnum(@field(colors, field.name));
            }
            return temp;
        },
        .EnumLiteral => return colorOfEnum(colors),
        else => @compileError("Invalid type for colors: " ++ @typeName(@TypeOf(colors))),
    }
}

fn colorOfEnum(comptime color: @TypeOf(.EnumLiteral)) []const u8 {
    // create new enum literal
    const tagName = @tagName(color);

    // make upercase
    const upperTagName = comptime upperCase(tagName);
    if (@hasDecl(Colors, upperTagName)) {
        return @field(Colors, upperTagName);
    }
    @compileError("Invalid color: " ++ tagName);
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
                temp = colorOfEnum(@field(colors, field.name)) ++ temp;
            }
            return temp ++ c(.RESET);
        },
        .EnumLiteral => return colorOfEnum(colors) ++
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

fn lowerCase(comptime text: []const u8) []const u8 {
    var out: [text.len]u8 = undefined;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[i] = std.ascii.toLower(text[i]);
    }
    return out[0..];
}

fn upperCase(comptime text: []const u8) []const u8 {
    var out: [text.len]u8 = undefined;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[i] = std.ascii.toUpper(text[i]);
    }
    return out[0..];
}

fn lowerCaseFirst(comptime text: []const u8) []const u8 {
    var out: [text.len]u8 = undefined;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (i == 0) {
            out[i] = std.ascii.toLower(text[i]);
        } else {
            out[i] = text[i];
        }
    }
    return out[0..];
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
