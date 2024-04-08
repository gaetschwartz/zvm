const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const path = std.fs.path;
const ansi = @import("ansi");
const config = @import("config.zig");
const builtin = @import("builtin");
const dirSize = @import("cache.zig").dirSize;
const DirSizeResult = @import("cache.zig").DirSizeResult;
const HumanSize = utils.HumanSize;

pub fn clean_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const verbose = ctx.args.hasFlag("verbose");
    _ = verbose;
    const directory = ctx.getPositional("directory") orelse ".";

    const cwd = std.fs.cwd();

    if (builtin.mode == .Debug) {
        const dir_path = try cwd.realpathAlloc(allocator, directory);
        std.log.debug("dir_path: {s}", .{dir_path});
    }

    var dir = cwd.openDir(directory, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            stderr.print("zvm: error: no such file or directory: '{s}'\x0A", .{directory}) catch {};
            return;
        },
        else => |e| return e,
    };

    defer dir.close();

    const cache = "zig-cache";
    const cache_dir_path = try dir.realpathAlloc(allocator, cache);
    std.log.debug("cache_dir: {s}", .{cache_dir_path});

    const res: DirSizeResult = blk: {
        var cache_dir = dir.openIterableDir(cache, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                break :blk DirSizeResult{ .size = 0, .files = 0 };
            },
            else => |e| return e,
        };
        defer cache_dir.close();
        break :blk try dirSize(cache_dir);
    };
    const human_size = HumanSize(f64).compute(@floatFromInt(res.size));

    try stdout.print(ansi.style("Cleaned " ++ ansi.bold("{d:.2} {s}") ++ ".\n", .green), .{ human_size.value, human_size.unit });
}
