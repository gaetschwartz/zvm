const std = @import("std");
const http = std.http;
const mem = std.mem;
const SizedAtomicQueue = @import("sized_atomic_queue.zig").SizedAtomicQueue;
const builtin = @import("builtin");

pub fn main() !void {
    // fetch a 100Mb file from the internet
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var file = try std.fs.cwd().createFile("out/out.dat", .{});
    defer file.close();
    const writer = file.writer();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip the first arg, which is the program name
    const url = args.next().?;
    std.log.debug("url: {s}", .{url});
    const uri = try std.Uri.parse(url);

    const CPU_COUNT = try std.Thread.getCpuCount();
    const MAX_CHUNKS_IN_QUEUE = try std.fmt.parseUnsigned(u64, args.next().?, 10);
    const CHUNK_SIZE = try parseBytes(args.next().?);
    if (std.log.defaultLogEnabled(.info)) {
        std.log.info("cpu count: {d}", .{CPU_COUNT});
        std.log.info("max chunks in queue: {d}", .{MAX_CHUNKS_IN_QUEUE});
        const h = HumanSize(u64).compute(CHUNK_SIZE);
        std.log.info("chunk size: {d} {s}", .{ h.value, h.unit });
    }

    var client = std.http.Client{
        .allocator = gpa.allocator(),
    };
    defer client.deinit();

    std.log.debug("fetching {s}", .{url});

    var discardBuf: [8]u8 = undefined;

    var headReq = try client.request(uri, .{ .method = .HEAD }, .{});
    defer headReq.deinit();
    const read = try headReq.read(&discardBuf);
    std.debug.assert(read == 0);

    const content_length = headReq.response.headers.content_length orelse return error.ContentLengthMissing;
    if (std.log.defaultLogEnabled(.debug)) {
        const human_length = HumanSize(u64).compute(content_length);
        std.log.debug("content length: {d} {s} ({d})", .{ human_length.value, human_length.unit, content_length });
    }

    // var headReq2 = try requestRange(&client, uri, .{ .method = .HEAD }, .{}, Range{ .start = 0, .end = 0 });
    // defer headReq2.deinit();
    // while (try headReq2.read(discardBuf[0..]) > 0) {}
    // const content_len_ranged = headReq2.response.headers.content_length orelse return error.ContentLengthMissing;
    // if (content_len_ranged != 1) return error.ClientDoesNotSupportRangeRequests;

    var nodes = std.ArrayList(*std.TailQueue(DownloadContext).Node).init(allocator);
    defer {
        for (nodes.items) |node| {
            allocator.destroy(node);
        }
        nodes.deinit();
    }
    var queue = std.atomic.Queue(DownloadContext).init();
    var doneQueue = SizedAtomicQueue(DownloadContext).init(MAX_CHUNKS_IN_QUEUE);

    // progressively fill the queue

    var start: u64 = 0;
    var buffers = std.ArrayList([]u8).init(allocator);
    defer buffers.deinit();

    std.log.debug("splitting file into chunks", .{});
    var chunk_count: usize = 0;
    while (start < content_length) : (start += CHUNK_SIZE) {
        const end = std.math.min(start + CHUNK_SIZE, content_length);
        const range = Range{ .start = start, .end = end };

        const ctx = DownloadContext{
            .uri = uri,
            .range = range,
            .buffer = undefined,
            .allocator = &allocator,
        };
        chunk_count += 1;
        const node = try allocator.create(std.TailQueue(DownloadContext).Node);
        node.* = .{ .data = ctx };
        try nodes.append(node);
        queue.put(node);
    }
    std.log.debug("split file into {d} chunks", .{chunk_count});

    // start threads
    var threads = std.ArrayList(std.Thread).init(allocator);
    defer threads.deinit();
    std.log.debug("starting {d} threads", .{CPU_COUNT});
    for (0..CPU_COUNT) |_| {
        try threads.append(try std.Thread.spawn(.{}, download, .{ &queue, &doneQueue }));
    }

    var chunks_written: usize = 0;
    var bytes_written: usize = 0;
    while (chunks_written < chunk_count) {
        while (doneQueue.get()) |node| {
            const ctx = node.data;
            // write the buffer to disk
            try file.seekTo(ctx.range.start);
            try writer.writeAll(ctx.buffer);
            chunks_written += 1;
            bytes_written += ctx.buffer.len;
            // free the buffer
            ctx.allocator.free(ctx.buffer);
        }
    }

    // wait for threads to finish
    std.log.debug("waiting for threads to finish", .{});
    for (threads.items) |thread| {
        thread.join();
    }

    const human_written = HumanSize(usize).compute(bytes_written);
    std.log.info("wrote {d} {s} to file", .{ human_written.value, human_written.unit });
}

const DownloadContext = struct {
    uri: std.Uri,
    range: Range,
    buffer: []u8,
    allocator: *std.mem.Allocator,
};

// takes a queue of DownloadContext and downloads the data
fn download(
    queue: *std.atomic.Queue(DownloadContext),
    doneQueue: *SizedAtomicQueue(DownloadContext),
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var client = http.Client{ .allocator = gpa.allocator() };
    defer client.deinit();

    while (queue.get()) |node| {
        const ctx = node.data;
        const buf = try ctx.allocator.alloc(u8, ctx.range.end - ctx.range.start);
        std.log.debug("[thread {d}] downloading range: {d}-{d}", .{ std.Thread.getCurrentId(), ctx.range.start, ctx.range.end });

        var req = try requestRange(&client, ctx.uri, .{ .method = .GET, .version = .@"HTTP/1.1" }, .{}, ctx.range);
        defer req.deinit();

        std.log.debug("[thread {d}] reading data", .{std.Thread.getCurrentId()});

        const read = try req.readAll(buf);

        if (std.log.defaultLogEnabled(.debug) and read != buf.len) {
            std.log.debug("[thread {d}] read {d} bytes, expected {d}", .{ std.Thread.getCurrentId(), read, ctx.buffer.len });
        }

        node.data.buffer = buf[0..read];
        std.log.debug("[thread {d}] putting ctx on done queue", .{std.Thread.getCurrentId()});
        doneQueue.put(node);

        if (std.log.defaultLogEnabled(.debug)) {
            const human = HumanSize(usize).compute(read);
            std.log.debug("[thread {d}] downloaded {d} {s}", .{ std.Thread.getCurrentId(), human.value, human.unit });
        }
    }
}

pub const Range = struct { start: u64, end: u64 };

fn requestRange(
    client: *http.Client,
    uri: std.Uri,
    headers: http.Client.Request.Headers,
    options: http.Client.Request.Options,
    range: Range,
) !http.Client.Request {
    const protocol: http.Client.Connection.Protocol = if (mem.eql(u8, uri.scheme, "http"))
        .plain
    else if (mem.eql(u8, uri.scheme, "https"))
        .tls
    else
        return error.UnsupportedUrlScheme;

    const port: u16 = uri.port orelse switch (protocol) {
        .plain => 80,
        .tls => 443,
    };

    const host = uri.host orelse return error.UriMissingHost;

    if (client.next_https_rescan_certs and protocol == .tls) {
        try client.ca_bundle.rescan(client.allocator);
        client.next_https_rescan_certs = false;
    }

    var req: http.Client.Request = .{
        .client = client,
        .headers = headers,
        .connection = try client.connect(host, port, protocol),
        .redirects_left = options.max_redirects,
        .response = switch (options.header_strategy) {
            .dynamic => |max| http.Client.Request.Response.initDynamic(max),
            .static => |buf| http.Client.Request.Response.initStatic(buf),
        },
    };

    {
        var h = try std.BoundedArray(u8, 1000).init(0);
        try h.appendSlice(@tagName(headers.method));
        try h.appendSlice(" ");
        try h.appendSlice(uri.path);
        try h.appendSlice(" ");
        try h.appendSlice(@tagName(headers.version));
        try h.appendSlice("\r\nHost: ");
        try h.appendSlice(host);
        try h.appendSlice("\r\nConnection: keep-alive");
        // add range header
        try h.appendSlice("\r\nRange: bytes=");
        try h.writer().print("{d}-{d}", .{ range.start, range.end });
        try h.appendSlice("\r\n\r\n");

        const header_bytes = h.slice();
        try req.connection.writeAll(header_bytes);
    }

    return req;
}

pub fn HumanSize(comptime T: type) type {
    return struct {
        value: T,
        unit: []const u8,

        const Self = @This();

        const Sizes = enum {
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

const Sized = enum(u64) {
    B = 1,
    KB = 1024,
    MB = 1024 * 1024,
    GB = 1024 * 1024 * 1024,
};

fn parseBytes(s: []const u8) !u64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}
    const value = try std.fmt.parseUnsigned(u64, s[0..end], 10);

    const unit = s[end..];
    const size = std.meta.stringToEnum(Sized, unit) orelse return error.InvalidUnit;
    return value * @enumToInt(size);
}
