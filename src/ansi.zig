const std = @import("std");

pub const Colors = struct {
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
pub fn c(comptime color: @TypeOf(.EnumLiteral)) []const u8 {
    return colorOfEnum(color);
}

fn colorOfEnum(comptime color: @TypeOf(.EnumLiteral)) []const u8 {
    // create new enum literal
    const tagName = @tagName(color);

    // make upercase
    const upperTagName = comptime upperCase(tagName);
    if (@hasDecl(Colors, upperTagName)) {
        return @field(Colors, upperTagName);
    }
    const ansiTypeInfo = @typeInfo(Colors);
    const decls = ansiTypeInfo.Struct.decls;
    var availableDecls = "";
    for (decls) |decl| {
        availableDecls = availableDecls ++ decl.name ++ ", ";
    }
    @compileError("Invalid color: " ++ tagName ++ " Info: " ++ std.fmt.comptimePrint("info = {any}\n", .{ansiTypeInfo}) ++ ". Available colors: " ++ availableDecls);
}

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

pub fn fade(comptime text: []const u8) []const u8 {
    return c(.FADE) ++ text ++ c(.RESET_FADE);
}

pub fn bold(comptime text: []const u8) []const u8 {
    return c(.BOLD) ++ text ++ c(.RESET_BOLD);
}

pub fn italic(comptime text: []const u8) []const u8 {
    return c(.ITALIC) ++ text ++ c(.RESET);
}

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
