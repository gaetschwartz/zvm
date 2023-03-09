const std = @import("std");
const http = std.http;
const mem = std.mem;
const builtin = @import("builtin");
const MultiConnectionOptions = @import("multi-http").MultiConnectionOptions;
const fetchMultiConnections = @import("multi-http").fetchMultiConnections;

pub const multi_http_scope_levels = &[_]std.log.ScopeLevel{};

pub fn main() !void {
    // fetch a 100Mb file from the internet
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var file = try std.fs.cwd().createFile("out/out.dat", .{});
    defer file.close();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip the first arg, which is the program name
    const url = args.next().?;
    std.log.debug("url: {s}", .{url});
    const uri = try std.Uri.parse(url);

    const THREAD_COUNT = try std.Thread.getCpuCount();
    const MAX_CHUNKS_IN_QUEUE = try std.fmt.parseUnsigned(u64, args.next().?, 10);
    const CHUNK_SIZE = try parseBytes(args.next().?);
    if (std.log.defaultLogEnabled(.info)) {
        std.log.info("thread count: {d}", .{THREAD_COUNT});
        std.log.info("max chunks in queue: {d}", .{MAX_CHUNKS_IN_QUEUE});
        const h = HumanSize(u64).compute(CHUNK_SIZE);
        std.log.info("chunk size: {d} {s}", .{ h.value, h.unit });
    }

    const options = MultiConnectionOptions{
        .max_chunks_in_queue = MAX_CHUNKS_IN_QUEUE,
        .chunk_size = CHUNK_SIZE,
        .thread_count = THREAD_COUNT,
        .allocator = allocator,
        .on_progress = &on_progress,
    };

    fetchMultiConnections(uri, file, options) catch |err| switch (err) {
        error.ContentLengthMissing => std.log.err("content length missing", .{}),
        error.BytesRangeNotSupported => std.log.err("bytes range not supported", .{}),
        else => |e| return e,
    };
}

fn on_progress(bytes_written: usize, bytes_total: usize) void {
    const hw = HumanSize(usize).compute(bytes_written);
    const ht = HumanSize(usize).compute(bytes_total);
    std.log.info("{d} {s} / {d} {s}", .{ hw.value, hw.unit, ht.value, ht.unit });
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
