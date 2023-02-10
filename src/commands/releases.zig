const std = @import("std");
const idx = @import("../index.zig");
const builtin = @import("builtin");
const http = std.http;
const mem = std.mem;
const ansi = @import("../ansi.zig");
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const RunContext = @import("../arg_parser.zig").ArgParser.RunContext;
const VersionInfo = @import("list.zig").VersionInfo;
const readVersionInfo = @import("list.zig").readVersionInfo;

const Index = idx.Index;
const Release = idx.Release;
const Archive = idx.Archive;

pub fn releases_cmd(ctx: RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    _ = stderr;

    const reverse = ctx.hasFlag("reverse");
    const raw = ctx.hasFlag("raw");

    var index = try idx.fetchIndex(allocator);

    if (!raw) try stdout.print("Available releases:\n", .{});
    var items = index.releases.items;
    if (reverse) std.mem.reverse(Release, items);
    if (raw) {
        for (items) |release| {
            try stdout.print("{s} ", .{release.version});
        }
        try stdout.print("\n", .{});
    } else {
        for (items) |release| {
            try stdout.print("  - {s} " ++ ansi.fade("({s})\n"), .{ release.version, release.channel });
        }
    }
}
