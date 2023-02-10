const std = @import("std");

pub const BLUE_BOLD = "\x1b[1;34m";
pub const BLUE = "\x1b[34m";
pub const GREEN_BOLD = "\x1b[1;32m";
pub const GREEN = "\x1b[32m";
pub const RED_BOLD = "\x1b[1;31m";
pub const RED = "\x1b[31m";
pub const YELLOW_BOLD = "\x1b[1;33m";
pub const YELLOW = "\x1b[33m";
pub const CYAN_BOLD = "\x1b[1;36m";
pub const CYAN = "\x1b[36m";
pub const MAGENTA_BOLD = "\x1b[1;35m";
pub const MAGENTA = "\x1b[35m";
pub const WHITE_BOLD = "\x1b[1;37m";
pub const WHITE = "\x1b[37m";
pub const BOLD = "\x1b[1m";
pub const RESET_BOLD = "\x1b[22m";
pub const RESET = "\x1b[0m";
pub const FADE = "\x1b[2m";
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

pub fn styleOld(comptime text: []const u8, comptime c: []const u8) []const u8 {
    return c ++ text ++ RESET;
}

pub fn style(comptime text: []const u8, comptime color: @TypeOf(.EnumLiteral)) []const u8 {
    // create new enum literal
    const c = color;
    return switch (c) {
        .blue => BLUE,
        .blue_bold => BLUE_BOLD,
        .green => GREEN,
        .green_bold => GREEN_BOLD,
        .red => RED,
        .red_bold => RED_BOLD,
        .yellow => YELLOW,
        .yellow_bold => YELLOW_BOLD,
        .cyan => CYAN,
        .cyan_bold => CYAN_BOLD,
        .magenta => MAGENTA,
        .magenta_bold => MAGENTA_BOLD,
        .white => WHITE,
        .white_bold => WHITE_BOLD,
        .bold => BOLD,
        .reset_bold => RESET_BOLD,
        .reset => RESET,
        .bg_red => BG_RED,
        .bg_green => BG_GREEN,
        .bg_yellow => BG_YELLOW,
        .bg_blue => BG_BLUE,
        .bg_magenta => BG_MAGENTA,
        .bg_cyan => BG_CYAN,
        .bg_white => BG_WHITE,
        .bg_reset => BG_RESET,
        .italic => ITALIC,
        .fade => FADE,
        .reset_fade => RESET_FADE,
        else => "",
    } ++ text ++ RESET;
}

pub fn fade(comptime text: []const u8) []const u8 {
    return FADE ++ text ++ RESET_FADE;
}

pub fn bold(comptime text: []const u8) []const u8 {
    return BOLD ++ text ++ RESET_BOLD;
}

pub fn lowerCase(comptime text: []const u8) []const u8 {
    var out: [text.len]u8 = undefined;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[i] = std.ascii.toLower(text[i]);
    }
    return out[0..];
}
