const std = @import("std");
const math = std.math;

pub fn Reader(comptime T: type) type {
    return struct {
        buf: []const T,
        pos: usize,

        const Self = @This();

        pub const Error = error{UnexpectedEOF};

        pub fn init(buf: []const T) Self {
            return Self{
                .buf = buf,
                .pos = 0,
            };
        }

        pub fn read(self: *Self) Error!T {
            if (self.pos >= self.buf.len) return Error.UnexpectedEOF;
            const val = self.buf[self.pos];
            self.pos += 1;
            return val;
        }

        pub fn readSlice(self: *Self, len: usize) Error![]const T {
            const end = math.min(self.pos + len, self.buf.len);
            const val = self.buf[self.pos..end];
            self.pos = end;
            return val;
        }

        pub fn readAll(self: *Self) Error![]const T {
            return self.readSlice(self.buf.len - self.pos);
        }

        pub fn readUntil(self: *Self, delim: T) Error![]const T {
            var i: usize = 0;
            while (self.pos + i < self.buf.len) : (i += 1) {
                if (self.buf[self.pos + i] == delim) {
                    const val = self.buf[self.pos .. self.pos + i];
                    self.pos += i + 1;
                    return val;
                }
            }
            return Error.UnexpectedEOF;
        }

        // reads until the delimiter is found, and then reads the delimiter
        // also skips over any trailing delimiters
        pub fn readUntilDelimiterN(self: *Self, delim: T) Error![]const T {
            var i: usize = 0;
            while (self.pos + i < self.buf.len) : (i += 1) {
                if (self.buf[self.pos + i] == delim) {
                    const val = self.buf[self.pos .. self.pos + i];
                    self.pos += i + 1;
                    while (self.pos < self.buf.len and self.buf[self.pos] == delim) {
                        self.pos += 1;
                    }
                    return val;
                }
            }
            return Error.UnexpectedEOF;
        }

        pub fn isEOF(self: *Self) bool {
            return self.pos >= self.buf.len;
        }
    };
}
const testing = std.testing;
test "simple read" {
    var reader = Reader(u8).init("hello world");
    try testing.expectEqual(reader.read() catch unreachable, 'h');
    try testing.expectEqual(reader.read() catch unreachable, 'e');
    try testing.expectEqual(reader.read() catch unreachable, 'l');
    try testing.expectEqual(reader.read() catch unreachable, 'l');
    try testing.expectEqual(reader.read() catch unreachable, 'o');
    try testing.expectEqual(reader.read() catch unreachable, ' ');
    try testing.expectEqual(reader.read() catch unreachable, 'w');
    try testing.expectEqual(reader.read() catch unreachable, 'o');
    try testing.expectEqual(reader.read() catch unreachable, 'r');
    try testing.expectEqual(reader.read() catch unreachable, 'l');
    try testing.expectEqual(reader.read() catch unreachable, 'd');

    try testing.expect(blk: {
        _ = reader.read() catch |err| switch (err) {
            Reader(u8).Error.UnexpectedEOF => break :blk true,
        };
        break :blk false;
    });
}

test "read slice" {
    var reader = Reader(u8).init("hello world");
    try testing.expectEqualStrings(try reader.readSlice(5), "hello");
    try testing.expectEqualStrings(try reader.readSlice(5), " worl");
    try testing.expectEqualStrings(try reader.readSlice(5), "d");
    try testing.expect(reader.isEOF());
}

test "read all" {
    var reader = Reader(u8).init("hello world");
    try testing.expectEqualStrings(try reader.readAll(), "hello world");
    try testing.expect(reader.isEOF());
}

test "read until" {
    var reader = Reader(u8).init("hello world");
    try testing.expectEqualStrings(try reader.readUntil(' '), "hello");
    try testing.expectEqualStrings(try reader.readUntil('l'), "wor");
    try testing.expect(blk: {
        _ = reader.readUntil(' ') catch |err| switch (err) {
            Reader(u8).Error.UnexpectedEOF => break :blk true,
        };
        break :blk false;
    });
}

test "read until delimiter" {
    var reader = Reader(u8).init("hello     world");
    try testing.expectEqualStrings(try reader.readUntilDelimiterN(' '), "hello");
    try testing.expectEqualStrings(try reader.readUntilDelimiterN('l'), "wor");
    try testing.expect(!reader.isEOF());
    try testing.expectEqualStrings(try reader.readAll(), "d");
    try testing.expect(reader.isEOF());
}

pub const StringUtils = struct {
    const spaces = [_]u8{ ' ', '\t', '\r', '\n' };

    pub fn trimLeft(str: []const u8) []const u8 {
        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            // if (str[i] == ' ' or str[i] == '\t' or str[i] == '\r' or str[i] == '\n') {
            if (std.mem.indexOf(u8, spaces[0..], str[i .. i + 1]) == null) {
                break;
            }
        }
        return str[i..];
    }

    pub fn trimRight(str: []const u8) []const u8 {
        var i: usize = str.len;
        while (i > 0) : (i -= 1) {
            if (std.mem.indexOf(u8, spaces[0..], str[i - 1 .. i]) == null) {
                break;
            }
        }
        return str[0..i];
    }

    pub fn trim(str: []const u8) []const u8 {
        return trimLeft(trimRight(str));
    }
};

test "trim" {
    try testing.expectEqualStrings(StringUtils.trimLeft("  hello world  "), "hello world  ");
    try testing.expectEqualStrings(StringUtils.trimRight("  hello world  "), "  hello world");
    try testing.expectEqualStrings(StringUtils.trim("  hello world  "), "hello world");
}
