const std = @import("std");
const known = @import("known-folders");
const builtin = @import("builtin");
const math = std.math;

pub fn zvmDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try known.getPath(allocator, .home) orelse {
        std.log.err(" could not find home directory\n", .{});
        return error.CouldNotFindHomeDirectory;
    };
    defer allocator.free(home);
    std.log.debug("home: {s}", .{home});
    return try std.fs.path.join(allocator, &[_][]const u8{ home, ".zvm" });
}

const ArchiveType = enum {
    zip,
    @"tar.xz",
    Unknown,

    pub fn componentCount(self: ArchiveType) usize {
        return switch (self) {
            .zip => @intCast(usize, 1),
            .@"tar.xz" => @intCast(usize, 2),
            .Unknown => @intCast(usize, 0),
        };
    }
};

pub fn stripExtension(path: []const u8, archive_type: ArchiveType) []const u8 {
    const ext_count = archive_type.componentCount();
    var i = std.mem.lastIndexOf(u8, path, ".");
    if (i == null) {
        return path;
    }
    var count: usize = 1;
    while (count < ext_count) {
        i = std.mem.lastIndexOf(u8, path[0..i.?], ".");
        if (i == null) {
            return path;
        }
        count += 1;
    }
    return path[0..i.?];
}

pub fn archiveType(path: []const u8) ArchiveType {
    var iter = std.mem.splitBackwards(u8, path, ".");
    const last1 = iter.next() orelse return ArchiveType.Unknown;
    const last2 = iter.next() orelse return ArchiveType.Unknown;
    if (std.mem.eql(u8, last1, "zip")) {
        return ArchiveType.zip;
    } else if (std.mem.eql(u8, last2, "tar") and std.mem.eql(u8, last1, "xz")) {
        return ArchiveType.@"tar.xz";
    } else {
        std.log.debug("Unknown archive type: [{s}, {s}]\n", .{ last2, last1 });
        return ArchiveType.Unknown;
    }
}

pub fn makeDirAbsolutePermissive(absolute_path: []const u8) !void {
    std.fs.makeDirAbsolute(absolute_path) catch |err| switch (err) {
        std.os.MakeDirError.PathAlreadyExists => {},
        else => return err,
    };
}

const HumanSizes = enum {
    B,
    KB,
    MB,
    GB,
    TB,
    PB,
};

pub fn HumanSize(comptime T: type) type {
    return struct {
        value: T,
        unit: []const u8,

        const Self = @This();

        pub fn compute(size: T) Self {
            const typeInfo = @typeInfo(HumanSizes);
            const enum_obj = typeInfo.Enum;
            var x = size;
            inline for (enum_obj.fields[0 .. enum_obj.fields.len - 1]) |field| {
                if (x < 1024) {
                    return Self{
                        .value = x,
                        .unit = field.name,
                    };
                }
                x /= 1024;
            }
            return Self{
                .value = x,
                .unit = enum_obj.fields[enum_obj.fields.len - 1].name,
            };
        }
    };
}

const isDebugMode = builtin.mode == .Debug;

pub fn ArrayListPointers(comptime T: type) type {
    return struct {
        const Self = @This();
        array: std.ArrayList(*T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return ArrayListPointers(T){
                .array = std.ArrayList(*T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *ArrayListPointers(T), allocator: *std.mem.Allocator) void {
            for (self.array.items) |item| {
                allocator.destroy(item);
            }
            self.array.deinit();
        }

        pub fn append(self: *ArrayListPointers(T), item: T) !void {
            const p = try self.allocator.create(T);
            p.* = item;
            try self.array.append(p);
        }

        pub fn items(self: *ArrayListPointers(T)) []*T {
            return self.array.items;
        }
    };
}

const hashMethod = std.crypto.hash.sha2.Sha256;
pub const digest_length = hashMethod.digest_length;

pub fn shasum(reader: std.fs.File.Reader, out_buffer: *[digest_length * 2]u8) !void {
    var hash = hashMethod.init(.{});
    var buffer: [hashMethod.block_length]u8 = undefined;
    while (true) {
        const read = try reader.read(&buffer);
        if (read == 0) break;
        hash.update(buffer[0..read]);
    }
    var temp_buffer: [digest_length]u8 = undefined;
    hash.final(temp_buffer[0..]);
    // to hex
    var stream = std.io.fixedBufferStream(out_buffer[0..]);
    try std.fmt.fmtSliceHexLower(temp_buffer[0..]).format("{}", .{}, stream.writer());
}

test "human size" {
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

fn expectHumanSize(expected: HumanSize(u64), actual: HumanSize(u64)) !void {
    try std.testing.expectEqual(expected.value, actual.value);
    try std.testing.expectEqualStrings(expected.unit, actual.unit);
}
