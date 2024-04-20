const std = @import("std");
const http = std.http;

pub const Release = struct {
    channel: []const u8,
    version: []const u8,
    date: []const u8,
    docs: []const u8,
    stdDocs: ?[]const u8,
    archives: []Archive,

    pub fn format(self: Release, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try std.json.stringify(
            self,
            .{ .whitespace = .minified },
            writer,
        );
    }
};

pub const Archive = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: u32,
    target: []const u8,

    pub fn format(self: Archive, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;

        try std.json.stringify(
            self,
            .{ .whitespace = .{
                .indent = if (options.width) |w| .{ .Space = @intCast(@min(w, std.math.maxInt(u8))) } else .{ .None = {} },
            } },
            writer,
        );
    }
};

pub const Index = struct {
    releases: []Release,
    allocator: std.heap.ArenaAllocator,

    pub fn deinit(self: *Index) void {
        self.allocator.deinit();
    }
};

pub fn fetchIndex(allocator: std.mem.Allocator) !Index {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();
    const uri = comptime try std.Uri.parse("https://ziglang.org/download/index.json");
    var headers = http.Headers.init(allocator);
    defer headers.deinit();
    var req = try client.request(
        .GET,
        uri,
        headers,
        .{},
    );
    defer req.deinit();
    try req.start();
    try req.finish();
    try req.wait();

    // 500 kb
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var total_read: usize = 0;
    var temp: [4096]u8 = undefined;
    while (true) {
        const read = try req.read(temp[0..]);
        if (read == 0) break;
        total_read += read;
        try buffer.appendSlice(temp[0..read]);
    }

    std.log.debug("total read: {d}\n", .{total_read});

    var tree = try std.json.parseFromSlice(Value, allocator, buffer.items[0..total_read], .{});
    defer tree.deinit();

    var result = try parseTree(allocator, tree);

    return result;
}

const Value = std.json.Value;

fn parseTree(_allocator: std.mem.Allocator, tree: std.json.Parsed(Value)) !Index {
    var arena = std.heap.ArenaAllocator.init(_allocator);
    var allocator = arena.allocator();
    var arr = std.ArrayList(Release).init(allocator);
    // iterate over the keys of the root object
    const value = tree.value;
    if (value != Value.object) return error.InvalidJson;
    var rootObject = value.object;
    for (rootObject.keys()) |key| {
        const val = rootObject.get(key) orelse unreachable;
        // std.log.debug("parsing Value.{s} : ", .{std.meta.tagName(val)});
        //val.dump();
        // std.log.debug("\n", .{});

        if (val != .object) return error.InvalidJson;
        const obj: std.json.ObjectMap = val.object;
        // print all keys of the object
        const version = blk: {
            if (std.mem.eql(u8, key, "master")) {
                const v = obj.get("version") orelse return error.InvalidJson;
                if (v != .string) return error.InvalidJson;
                break :blk v.string;
            } else {
                break :blk key;
            }
        };
        var archives = std.ArrayList(Archive).init(allocator);
        // iterate through all the key-value pairs of the object and only treat the ObjectMap ones
        for (obj.keys()) |key2| {
            const val2 = obj.get(key2) orelse unreachable;
            if (val2 != .object) continue;
            const obj2: std.json.ObjectMap = val2.object;
            const tarball = (obj2.get("tarball") orelse return error.InvalidJson).string;
            const shasum = (obj2.get("shasum") orelse return error.InvalidJson).string;
            const size = (obj2.get("size") orelse return error.InvalidJson).string;
            try archives.append(Archive{
                .tarball = allocator.dupe(u8, tarball) catch return error.InvalidJson,
                .shasum = allocator.dupe(u8, shasum) catch return error.InvalidJson,
                .size = std.fmt.parseInt(u32, size, 10) catch return error.InvalidJson,
                .target = allocator.dupe(u8, key2) catch return error.InvalidJson,
            });
        }
        const channel = if (std.mem.eql(u8, key, "master")) "master" else allocator.dupe(u8, key) catch return error.InvalidJson;
        const date = (obj.get("date") orelse return error.InvalidJson).string;
        const docs = (obj.get("docs") orelse return error.InvalidJson).string;
        const stdDocs = blk: {
            const v = obj.get("stdDocs");
            if (v == null) break :blk null;
            if (v.? != .string) return error.InvalidJson;
            break :blk v.?.string;
        };
        try arr.append(Release{
            .channel = channel,
            .version = allocator.dupe(u8, version) catch return error.InvalidJson,
            .date = allocator.dupe(u8, date) catch return error.InvalidJson,
            .docs = allocator.dupe(u8, docs) catch return error.InvalidJson,
            .stdDocs = if (stdDocs) |sd| allocator.dupe(u8, sd) catch return error.InvalidJson else null,
            .archives = try archives.toOwnedSlice(),
        });
    }
    return Index{
        .releases = try arr.toOwnedSlice(),
        .allocator = arena,
    };
}

test "parse 2023-02-08.json" {
    var tree = try std.json.parseFromSlice(
        Value,
        std.testing.allocator,
        @embedFile("test_data/2023-02-08.json"),
        .{},
    );
    defer tree.deinit();

    // std.log.debug("index:", .{});
    // tree.root.dump();
    var parsed = try parseTree(std.testing.allocator, &tree.value);
    defer parsed.deinit();

    // look for the "master" release
    var master: ?Release = null;
    for (parsed.releases) |release| {
        if (std.mem.eql(u8, release.channel, "master")) {
            // only one master release
            try std.testing.expect(master == null);
            master = release;
        }
    }
    try std.testing.expect(master != null);
    try std.testing.expectEqualStrings("master", master.?.channel);
    try std.testing.expectEqualStrings("0.11.0-dev.1580+a5b34a61a", master.?.version);
    try std.testing.expectEqualStrings("2023-02-06", master.?.date);
}
