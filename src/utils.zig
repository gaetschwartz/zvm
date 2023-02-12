const std = @import("std");
const known = @import("known-folders");
const builtin = @import("builtin");
const math = std.math;

pub fn zvmDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try known.getPath(allocator, .home) orelse {
        std.log.err(" could not find home directory\n", .{});
        return error.CouldNotFindHomeDirectory;
    };
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

const HumanSize = struct {
    value: i64,
    unit: []const u8,
};

fn humanSize(size: i64) HumanSize {
    const KB = 1024;
    const MB = KB * 1024;
    const GB = MB * 1024;

    if (size < KB) {
        return HumanSize{ .value = size, .unit = "B" };
    } else if (size < MB) {
        return HumanSize{ .value = @divTrunc(size, KB), .unit = "KB" };
    } else if (size < GB) {
        return HumanSize{ .value = @divTrunc(size, MB), .unit = "MB" };
    } else {
        return HumanSize{ .value = @divTrunc(size, GB), .unit = "GB" };
    }
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
    try std.fmt.fmtSliceHexLower(temp_buffer[0..]).format("", .{}, stream.writer());
    std.log.debug("Wrote shasum: {s}\n", .{out_buffer[0..]});
}
