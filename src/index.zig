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
        _ = fmt;

        try std.json.stringify(
            self,
            .{ .whitespace = .{
                .indent = if (options.width) |w| .{ .Space = @intCast(u8, @min(w, std.math.maxInt(u8))) } else .{ .None = {} },
            } },
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
                .indent = if (options.width) |w| .{ .Space = @intCast(u8, @min(w, std.math.maxInt(u8))) } else .{ .None = {} },
            } },
            writer,
        );
    }
};

pub const Index = struct {
    releases: []Release,
    allocator: std.mem.Allocator,
    tree: ?std.json.ValueTree,

    pub fn deinit(self: *Index) void {
        for (self.releases) |release| {
            self.allocator.free(release.archives);
        }
        self.allocator.free(self.releases);

        if (self.tree) |_| self.tree.?.deinit();
    }
};

pub fn fetchIndex(allocator: std.mem.Allocator) !Index {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();
    const uri = comptime try std.Uri.parse("https://ziglang.org/download/index.json");
    var req = try client.request(
        uri,
        .{ .method = .GET, .connection = .close },
        .{ .max_redirects = 0 },
    );
    defer req.deinit();

    // 500 kb
    const BUFFER_SIZE = 1024 * 1024;
    var buffer: [BUFFER_SIZE]u8 = undefined;
    const total_read = try req.readAll(&buffer);

    std.log.debug("total read: {d}\n", .{total_read});

    // var token_stream = std.json.TokenStream.init(array.items[0..total_read]);
    var parser = std.json.Parser.init(allocator, true);
    defer parser.deinit();
    var tree = try parser.parse(buffer[0..total_read]);
    // ! we dont want to deinit the tree because it would free all the strings

    // std.log.debug("index:", .{});
    // tree.root.dump();
    var result = try parseTree(allocator, &tree.root);
    result.tree = tree;
    return result;
}

const Value = std.json.Value;

fn parseTree(allocator: std.mem.Allocator, tree: *const Value) !Index {
    var arr = std.ArrayList(Release).init(allocator);
    // iterate over the keys of the root object
    if (tree.* != Value.Object) return error.InvalidJson;
    var rootObject: std.StringArrayHashMap(Value) = tree.Object;
    for (rootObject.keys()) |key| {
        const val = rootObject.get(key) orelse unreachable;
        // std.log.debug("parsing Value.{s} : ", .{std.meta.tagName(val)});
        //val.dump();
        // std.log.debug("\n", .{});

        if (val != .Object) return error.InvalidJson;
        const obj: std.json.ObjectMap = val.Object;
        // print all keys of the object
        const version = blk: {
            const v = obj.get("version") orelse break :blk key;
            if (v != .String) return error.InvalidJson;
            break :blk v.String;
        };
        var archives = std.ArrayList(Archive).init(allocator);
        // iterate through all the key-value pairs of the object and only treat the ObjectMap ones
        for (obj.keys()) |key2| {
            const val2 = obj.get(key2) orelse unreachable;
            if (val2 != .Object) continue;
            const obj2: std.json.ObjectMap = val2.Object;
            const tarball = (obj2.get("tarball") orelse return error.InvalidJson).String;
            const shasum = (obj2.get("shasum") orelse return error.InvalidJson).String;
            const size = (obj2.get("size") orelse return error.InvalidJson).String;
            try archives.append(Archive{
                .tarball = tarball,
                .shasum = shasum,
                .size = std.fmt.parseInt(u32, size, 10) catch return error.InvalidJson,
                .target = key2,
            });
        }
        try arr.append(Release{
            .channel = if (obj.get("version") != null) key else "stable",
            .version = version,
            .date = (obj.get("date") orelse return error.InvalidJson).String,
            .docs = (obj.get("docs") orelse return error.InvalidJson).String,
            .stdDocs = blk: {
                const v = obj.get("stdDocs");
                if (v == null) break :blk null;
                if (v.? != .String) return error.InvalidJson;
                break :blk v.?.String;
            },
            .archives = try archives.toOwnedSlice(),
        });
    }
    return Index{
        .releases = try arr.toOwnedSlice(),
        .allocator = allocator,
        .tree = null,
    };
}

test "parse 2023-02-08.json" {
    // var token_stream = std.json.TokenStream.init(array.items[0..total_read]);
    var parser = std.json.Parser.init(std.testing.allocator, true);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("test_data/2023-02-08.json"));
    defer tree.deinit();

    // std.log.debug("index:", .{});
    // tree.root.dump();
    var parsed = try parseTree(std.testing.allocator, &tree.root);
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
