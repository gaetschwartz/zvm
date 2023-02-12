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

    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "powershell", "-Command", "Remove-Item", "-Recurse", "-Force", cache },
        else => &[_][]const u8{ "rm", "-rf", cache },
    };
    const res = try std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = allocator,
    });
    handleResult(res, argv) catch {
        return;
    };
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

    const size = try dirSize(cache_dir, allocator);
    if (size == 0) {
        try stdout.print(ansi.style("The cache is empty.\n", .cyan), .{});
        return;
    }
    const human_size = humanSize(size, allocator);
    defer allocator.free(human_size);
    try stdout.print(ansi.style("The cache has a size of " ++ ansi.bold("{s}") ++ ".\n", .cyan), .{human_size});
}

// recuring function to get the size of a directory
fn dirSize(dir: std.fs.IterableDir, allocator: std.mem.Allocator) !u64 {
    var total: u64 = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .Directory => {
                var sub_dir = try dir.dir.openIterableDir(entry.name, .{});
                defer sub_dir.close();
                total += try dirSize(sub_dir, allocator);
            },
            .File => {
                const stat = try dir.dir.statFile(entry.name);
                total += stat.size;
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
