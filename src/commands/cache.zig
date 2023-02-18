const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const zvmDir = @import("../utils.zig").zvmDir;
const handleResult = @import("install.zig").handleResult;
const printArgv = @import("install.zig").printArgv;
const path = std.fs.path;
const ansi = @import("ansi");
const builtin = @import("builtin");

pub fn cache_clear_cmd(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    _ = stdout;
    const stderr = std.io.getStdErr().writer();
    _ = stderr;

    const zvm = try zvmDir(allocator);
    const cache = try path.join(allocator, &[_][]const u8{ zvm, "cache" });
    try std.fs.deleteTreeAbsolute(cache);
}

pub fn cache_size_cmd(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    _ = stderr;

    const zvm = try zvmDir(allocator);
    const cache = try path.join(allocator, &[_][]const u8{ zvm, "cache" });
    const cache_dir = std.fs.openIterableDirAbsolute(cache, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try stdout.print(ansi.style("The cache is empty.\n", .cyan), .{});
            return;
        },
        else => return err,
    };

    const info = try dirSize(cache_dir, allocator);
    const human_size = humanSize(info.size, allocator);
    defer allocator.free(human_size);
    try stdout.print(ansi.style("Total: " ++ ansi.bold("{d}") ++ " files, " ++ ansi.bold("{s}") ++ "\n", .cyan), .{ info.files, human_size });
}

const CacheInfo = struct {
    size: u64,
    files: u64,
};

// recuring function to get the size of a directory
fn dirSize(dir: std.fs.IterableDir, allocator: std.mem.Allocator) !CacheInfo {
    var total: CacheInfo = .{ .size = 0, .files = 0 };
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .Directory => {
                var sub_dir = try dir.dir.openIterableDir(entry.name, .{});
                defer sub_dir.close();
                const info = try dirSize(sub_dir, allocator);
                total = .{
                    .size = total.size + info.size,
                    .files = total.files + info.files,
                };
            },
            .File => {
                const stat = try dir.dir.statFile(entry.name);
                total = .{
                    .size = total.size + stat.size,
                    .files = total.files + 1,
                };
            },
            else => {},
        }
    }
    return total;
}

fn humanSize(size: u64, allocator: std.mem.Allocator) []const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" };
    var i: usize = 0;
    var s = size;
    while (s > 1024) : (s >>= 10) {
        i += 1;
    }
    return std.fmt.allocPrint(allocator, "{d} {s}", .{ s, units[i] }) catch unreachable;
}
