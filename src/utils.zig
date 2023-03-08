const std = @import("std");
const known = @import("known-folders");
const builtin = @import("builtin");
const math = std.math;

pub fn zvmDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try known.getPath(allocator, .home) orelse
        return error.UnableToFindHomeDirectory;
    defer allocator.free(home);
    std.log.debug("home: {s}", .{home});
    return try std.fs.path.join(allocator, &[_][]const u8{ home, ".zvm" });
}

const ArchiveType = enum {
    zip,
    @"tar.xz",
    unknown,
};

pub fn archiveType(path: []const u8) ArchiveType {
    var iter = std.mem.splitBackwards(u8, path, ".");
    const last1 = iter.next() orelse return .unknown;
    //? It's safe to return here because we know that there should be at least one dot in the path
    //? thus two components.
    const last2 = iter.next() orelse return .unknown;

    if (std.mem.eql(u8, last1, "zip")) {
        return .zip;
    } else if (std.mem.eql(u8, last2, "tar") and std.mem.eql(u8, last1, "xz")) {
        return .@"tar.xz";
    } else {
        return .unknown;
    }
}

test "archive type" {
    try std.testing.expectEqual(ArchiveType.zip, archiveType("foo.zip"));
    try std.testing.expectEqual(ArchiveType.@"tar.xz", archiveType("foo.tar.xz"));
    try std.testing.expectEqual(ArchiveType.unknown, archiveType("foo"));
    try std.testing.expectEqual(ArchiveType.unknown, archiveType("foo.bar"));
    try std.testing.expectEqual(ArchiveType.unknown, archiveType("foo.bar.baz"));
    try std.testing.expectEqual(ArchiveType.@"tar.xz", archiveType("is.this.a.zip.or.a.tar.xz"));
    try std.testing.expectEqual(ArchiveType.zip, archiveType("its.defo.a.tar.xz.zip"));
    try std.testing.expectEqual(ArchiveType.unknown, archiveType("among.us.zip.."));
}

pub fn HumanSize(comptime T: type) type {
    return struct {
        value: T,
        unit: []const u8,

        const Self = @This();

        pub const Sizes = enum {
            B,
            KB,
            MB,
            GB,
            TB,
            PB,
        };

        pub fn compute(size: T) Self {
            const typeInfo = @typeInfo(Self.Sizes);
            const enum_obj = typeInfo.Enum;
            var x = size;
            inline for (enum_obj.fields[0 .. enum_obj.fields.len - 1]) |field| {
                if (x < 1024) {
                    return Self{
                        .value = x,
                        .unit = field.name,
                    };
                }
                x = switch (@typeInfo(T)) {
                    .Int => x >> 10,
                    .Float => x / 1024,
                    else => @compileError("Unsupported type '" ++ @typeName(T) ++ "'"),
                };
            }
            return Self{
                .value = x,
                .unit = comptime enum_obj.fields[enum_obj.fields.len - 1].name,
            };
        }
    };
}

test "HumanSize(u64)" {
    const cases = [_]struct {
        size: u64,
        expected: HumanSize(u64),
    }{
        .{ .size = 0, .expected = HumanSize(u64){ .value = 0, .unit = "B" } },
        .{ .size = 1, .expected = HumanSize(u64){ .value = 1, .unit = "B" } },
        .{ .size = 1023, .expected = HumanSize(u64){ .value = 1023, .unit = "B" } },
        .{ .size = 1024, .expected = HumanSize(u64){ .value = 1, .unit = "KB" } },
        .{ .size = 1024 * 1024 - 1, .expected = HumanSize(u64){ .value = 1023, .unit = "KB" } },
        .{ .size = 1024 * 1024, .expected = HumanSize(u64){ .value = 1, .unit = "MB" } },
        .{ .size = 1024 * 1024 * 1024 - 1, .expected = HumanSize(u64){ .value = 1023, .unit = "MB" } },
        .{ .size = 1024 * 1024 * 1024, .expected = HumanSize(u64){ .value = 1, .unit = "GB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(u64){ .value = 1023, .unit = "GB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024, .expected = HumanSize(u64){ .value = 1, .unit = "TB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(u64){ .value = 1023, .unit = "TB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024, .expected = HumanSize(u64){ .value = 1, .unit = "PB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(u64){ .value = 1023, .unit = "PB" } },
    };
    for (cases) |c| {
        const actual = HumanSize(u64).compute(c.size);
        expectHumanSize(c.expected, actual) catch |err| {
            std.debug.print("expected: {d} {s}, actual: {d} {s}\n", .{ c.expected.value, c.expected.unit, actual.value, actual.unit });
            return err;
        };
    }
}

test "HumanSize(f64)" {
    const cases = [_]struct {
        size: f64,
        expected: HumanSize(f64),
    }{
        .{ .size = 0, .expected = HumanSize(f64){ .value = 0, .unit = "B" } },
        .{ .size = 1, .expected = HumanSize(f64){ .value = 1, .unit = "B" } },
        .{ .size = 1023, .expected = HumanSize(f64){ .value = 1023, .unit = "B" } },
        .{ .size = 1024, .expected = HumanSize(f64){ .value = 1, .unit = "KB" } },
        .{ .size = 1024 * 1024 - 1, .expected = HumanSize(f64){ .value = 1023, .unit = "KB" } },
        .{ .size = 1024 * 1024, .expected = HumanSize(f64){ .value = 1, .unit = "MB" } },
        .{ .size = 1024 * 1024 * 1024 - 1, .expected = HumanSize(f64){ .value = 1023, .unit = "MB" } },
        .{ .size = 1024 * 1024 * 1024, .expected = HumanSize(f64){ .value = 1, .unit = "GB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(f64){ .value = 1023, .unit = "GB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024, .expected = HumanSize(f64){ .value = 1, .unit = "TB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(f64){ .value = 1023, .unit = "TB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024, .expected = HumanSize(f64){ .value = 1, .unit = "PB" } },
        .{ .size = 1024 * 1024 * 1024 * 1024 * 1024 * 1024 - 1, .expected = HumanSize(f64){ .value = 1023, .unit = "PB" } },
    };
    for (cases) |c| {
        const actual = HumanSize(f64).compute(c.size);
        expectHumanSizeDelta(f64, c.expected, actual, 1) catch |err| {
            std.debug.print("expected: {d} {s}, actual: {d} {s}\n", .{ c.expected.value, c.expected.unit, actual.value, actual.unit });
            return err;
        };
    }
}

fn expectHumanSize(expected: HumanSize(u64), actual: HumanSize(u64)) !void {
    try std.testing.expectEqual(expected.value, actual.value);
    try std.testing.expectEqualStrings(expected.unit, actual.unit);
}

fn expectHumanSizeDelta(comptime T: type, expected: HumanSize(T), actual: HumanSize(T), delta: T) !void {
    try std.testing.expectApproxEqAbs(expected.value, actual.value, delta);
    try std.testing.expectEqualStrings(expected.unit, actual.unit);
}

pub const Shasum256 = struct {
    const hashMethod = std.crypto.hash.sha2.Sha256;
    pub const digest_length = hashMethod.digest_length;
    pub const digest_length_hex = digest_length * 2;

    pub fn compute(reader: anytype, out_buffer: *[digest_length_hex]u8) !void {
        var hash = hashMethod.init(.{});
        var buffer: [hashMethod.block_length]u8 = undefined;
        while (true) {
            const read = try reader.readAll(&buffer);
            if (read == 0) break;
            hash.update(buffer[0..read]);
        }
        var temp_buffer: [digest_length]u8 = undefined;
        hash.final(temp_buffer[0..]);
        // to hex
        var stream = std.io.fixedBufferStream(out_buffer[0..]);
        try std.fmt.fmtSliceHexLower(temp_buffer[0..]).format("{}", .{}, stream.writer());
    }
};

test "shasum" {
    var buffer = std.io.fixedBufferStream(&[_]u8{0} ** 1024);
    var out_buffer: [Shasum256.digest_length * 2]u8 = undefined;
    try Shasum256.compute(buffer.reader(), &out_buffer);
    try std.testing.expectEqualStrings("5f70bf18a086007016e948b04aed3b82103a36bea41755b6cddfaf10ace3c6ef", out_buffer[0..]);

    buffer = std.io.fixedBufferStream(&[_]u8{'A'} ** 1024);
    try Shasum256.compute(buffer.reader(), &out_buffer);
    try std.testing.expectEqualStrings("6ab72eeb9e77b07540897e0c8d6d23ec8eef0f8c3a47e1b3f4e93443d9536bed", out_buffer[0..]);

    buffer = std.io.fixedBufferStream("Hello, world!");
    try Shasum256.compute(buffer.reader(), &out_buffer);
    try std.testing.expectEqualStrings("315f5bdb76d078c43b8ac0064e4a0164", out_buffer[0..32]);

    buffer = std.io.fixedBufferStream("");
    try Shasum256.compute(buffer.reader(), &out_buffer);
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", out_buffer[0..]);
}
