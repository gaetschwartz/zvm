const std = @import("std");
const http = std.http;

pub const Release = struct {
    channel: []const u8,
    version: []const u8,
    date: []const u8,
    docs: []const u8,
    stdDocs: ?[]const u8,
    archives: std.ArrayList(Archive),
};

pub const Archive = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: u32,
    target: []const u8,
};

pub const Index = struct {
    releases: std.ArrayList(Release),
    allocator: std.mem.Allocator,
    tree: ?std.json.ValueTree,

    pub fn deinit(self: *Index) void {
        for (self.releases.items) |release| {
            release.archives.deinit();
        }
        self.releases.deinit();
        if (self.tree) |_| self.tree.?.deinit();
    }
};

pub fn fetchIndex(allocator: std.mem.Allocator) anyerror!Index {
    var client = http.Client{
        .allocator = allocator,
    };
    var uri = try std.Uri.parse("https://ziglang.org/download/index.json");
    var req = try client.request(uri, .{}, .{});

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const BUFFER_SIZE = 1024;
    var total_read: usize = 0;
    var temp_buffer = [_]u8{0} ** BUFFER_SIZE;
    while (true) {
        //std.log.debug("reading from request with state {any}\n", .{req.response.state});
        const read: usize = try req.readAtLeast(&temp_buffer, 1);
        total_read += read;
        //std.log.debug("read: {d} bytes, total read: {d} ({d}B)\n", .{ read, total_read, total_read / 1024 });
        if (read == 0) break;
        try buffer.appendSlice(temp_buffer[0..read]);
    }
    //std.log.debug("total read: {d}\n", .{total_read});

    // var token_stream = std.json.TokenStream.init(array.items[0..total_read]);
    var parser = std.json.Parser.init(allocator, true);
    defer parser.deinit();
    var tree = try parser.parse(buffer.items[0..total_read]);
    // ! we dont want to deinit the tree because it would free all the strings

    // std.log.debug("index:", .{});
    // tree.root.dump();
    var result = try parseTree(allocator, &tree.root);
    result.tree = tree;
    return result;
}

const Value = std.json.Value;

fn parseTree(allocator: std.mem.Allocator, tree: *const Value) anyerror!Index {
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
            .archives = archives,
        });
    }
    return Index{
        .releases = arr,
        .allocator = allocator,
        .tree = null,
    };
}

pub fn dumpRelease(channel: Release) void {
    std.log.debug("channel: {{", .{});
    std.log.debug("  channel: {s}", .{channel.channel});
    std.log.debug("  version: {s}", .{channel.version});
    std.log.debug("  date: {s}", .{channel.date});
    std.log.debug("  docs: {s}", .{channel.docs});
    if (channel.stdDocs) |stdDocs| {
        std.log.debug("  stdDocs: {s}", .{stdDocs});
    }
    std.log.debug("  archives: {{", .{});
    for (channel.archives.items) |archive| {
        std.log.debug("    {{", .{});
        std.log.debug("      target: {s}", .{archive.target});
        std.log.debug("      tarball: {s}", .{archive.tarball});
        std.log.debug("      shasum: {s}", .{archive.shasum});
        std.log.debug("      size: {d}", .{archive.size});
        std.log.debug("    }}", .{});
    }
    std.log.debug("}}", .{});
}

test "parse 2023-02-08.json" {
    // var token_stream = std.json.TokenStream.init(array.items[0..total_read]);
    var parser = std.json.Parser.init(std.testing.allocator, true);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("test_data/2023-02-08.json"));
    defer tree.deinit();

    // std.log.debug("index:", .{});
    // tree.root.dump();
    var result = try parseTree(std.testing.allocator, &tree.root);
    for (result.releases.items) |item| {
        dumpRelease(item);
    }
    defer result.deinit();
}