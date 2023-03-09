const std = @import("std");
const http = std.http;
const mem = std.mem;
const builtin = @import("builtin");
const BoundedAtomicQueue = @import("bounded_atomic_queue.zig").BoundedAtomicQueue;
const ownLog = @import("log.zig");

pub const MultiConnectionOptions = struct {
    max_chunks_in_queue: u64 = 8,
    chunk_size: u64 = 10 * 1024 * 1024, // 10MB
    thread_count: ?usize = null,
    allocator: std.mem.Allocator,
    on_progress: *const fn (bytes_written: usize, bytes_total: usize) void = &no_op,

    fn no_op(bytes_written: usize, bytes_total: usize) void {
        _ = bytes_written;
        _ = bytes_total;
    }
};

pub fn fetchMultiConnections(uri: std.Uri, file: std.fs.File, options: MultiConnectionOptions) !void {
    const scope = .multi_connections;
    const log = ownLog.scoped(scope);

    var client = std.http.Client{ .allocator = options.allocator };
    defer client.deinit();

    const THREADS_COUNT = options.thread_count orelse try std.Thread.getCpuCount();
    const MAX_CHUNKS_IN_QUEUE = options.max_chunks_in_queue;
    const CHUNK_SIZE = options.chunk_size;

    var discardBuf: [8]u8 = undefined;

    var headReq = try client.request(uri, .{ .method = .HEAD }, .{});
    defer headReq.deinit();
    const read = try headReq.read(&discardBuf);
    std.debug.assert(read == 0);

    const content_length = headReq.response.headers.content_length orelse return error.ContentLengthMissing;

    if (comptime std.log.logEnabled(.debug, scope)) {
        const human_length = HumanSize(u64).compute(content_length);
        log.debug("content length: {d} {s} ({d})", .{ human_length.value, human_length.unit, content_length });
    }

    const acceptRanges = getHeader(&headReq.response, "Accept-Ranges") orelse return error.BytesRangeNotSupported;
    if (!mem.eql(u8, acceptRanges, "bytes")) {
        return error.BytesRangeNotSupported;
    }
    log.debug("accept ranges: {s}", .{acceptRanges});

    var queue = std.atomic.Queue(DownloadContext).init();
    var doneQueue = BoundedAtomicQueue(DownloadContext).init(MAX_CHUNKS_IN_QUEUE);

    log.debug("splitting file into chunks", .{});
    var chunk_count: usize = 0;
    var start: u64 = 0;
    while (start < content_length) : (start += CHUNK_SIZE) {
        const end = std.math.min(start + CHUNK_SIZE, content_length);
        const range = Range{ .start = start, .end = end };

        const ctx: DownloadContext = .{
            .uri = uri,
            .range = range,
            .buffer = undefined,
            .allocator = options.allocator,
        };

        const node = try options.allocator.create(std.TailQueue(DownloadContext).Node);
        node.* = .{ .data = ctx };
        queue.put(node);

        chunk_count += 1;
    }
    log.debug("split file into {d} chunks", .{chunk_count});

    // start threads
    var threads = try std.ArrayList(std.Thread).initCapacity(options.allocator, THREADS_COUNT);
    defer threads.deinit();

    log.debug("starting {d} threads", .{THREADS_COUNT});
    for (0..THREADS_COUNT) |_| {
        threads.appendAssumeCapacity(try std.Thread.spawn(.{}, download, .{ &queue, &doneQueue }));
    }

    var chunks_written: usize = 0;
    var bytes_written: usize = 0;
    while (chunks_written < chunk_count) {
        while (doneQueue.get()) |node| {
            const ctx = node.data;
            // write the buffer to disk
            try file.seekTo(ctx.range.start);
            try file.writeAll(ctx.buffer);
            chunks_written += 1;
            bytes_written += ctx.buffer.len;

            // call the progress callback
            options.on_progress(bytes_written, content_length);

            // free the resources allocated for this chunk
            defer {
                ctx.allocator.free(ctx.buffer);
                ctx.allocator.destroy(node);
            }
        }
    }

    // wait for threads to finish
    log.debug("waiting for threads to finish", .{});
    for (threads.items) |thread| {
        thread.join();
    }

    if (comptime std.log.logEnabled(.debug, scope)) {
        const human_written = HumanSize(usize).compute(bytes_written);
        log.debug("wrote {d} {s} to file", .{ human_written.value, human_written.unit });
    }
}

fn getHeader(response: *const std.http.Client.Request.Response, name: []const u8) ?[]const u8 {
    var lines = std.mem.split(u8, response.header_bytes.items, "\r\n");
    while (lines.next()) |line| {
        var kv = std.mem.split(u8, line, ": ");
        const key = kv.next().?;
        if (std.ascii.eqlIgnoreCase(key, name)) {
            return kv.next();
        }
    }
    return null;
}

const DownloadContext = struct {
    uri: std.Uri,
    range: Range,
    buffer: []u8,
    allocator: std.mem.Allocator,
};

// takes a queue of DownloadContext and downloads the data
fn download(
    queue: *std.atomic.Queue(DownloadContext),
    doneQueue: *BoundedAtomicQueue(DownloadContext),
) !void {
    const scope = .multi_connections_thread;
    const log = ownLog.scoped(scope);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var client = http.Client{ .allocator = gpa.allocator() };
    defer client.deinit();

    while (queue.get()) |node| {
        const ctx = node.data;
        const buf = try ctx.allocator.alloc(u8, ctx.range.end - ctx.range.start);
        log.debug("[thread {d}] downloading range: {d}-{d}", .{ std.Thread.getCurrentId(), ctx.range.start, ctx.range.end });

        var req = try requestRange(&client, ctx.uri, .{ .method = .GET, .version = .@"HTTP/1.1" }, .{}, ctx.range);
        defer req.deinit();

        log.debug("[thread {d}] reading data", .{std.Thread.getCurrentId()});

        const read = try req.readAll(buf);

        if (comptime std.log.logEnabled(.debug, scope) and read != buf.len) {
            log.debug("[thread {d}] read {d} bytes, expected {d}", .{ std.Thread.getCurrentId(), read, ctx.buffer.len });
        }

        node.data.buffer = buf[0..read];
        log.debug("[thread {d}] putting ctx on done queue", .{std.Thread.getCurrentId()});
        doneQueue.put(node);

        if (comptime std.log.logEnabled(.debug, scope)) {
            const human = HumanSize(usize).compute(read);
            log.debug("[thread {d}] downloaded {d} {s}", .{ std.Thread.getCurrentId(), human.value, human.unit });
        }
    }
}

const Range = struct { start: u64, end: u64 };

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

fn HumanSize(comptime T: type) type {
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
