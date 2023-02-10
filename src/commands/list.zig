const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const zvmDir = @import("../utils.zig").zvmDir;
const path = std.fs.path;
const ansi = @import("../ansi.zig");

pub const VersionInfo = struct {
    version: []const u8,
    channel: ?[]const u8,
};

pub fn list_cmd(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    _ = stderr;

    const zvm = try zvmDir(allocator);
    const versions = try path.join(allocator, &[_][]const u8{ zvm, "versions" });

    var dir = std.fs.openIterableDirAbsolute(versions, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try stdout.print("No versions installed\x0a", .{});
                return;
            },
            else => return err,
        }
    };
    defer dir.close();

    var it = dir.iterate();
    try stdout.print("Installed versions:\x0a", .{});

    while (try it.next()) |entry| {
        if (entry.kind != .Directory) continue;
        const version_info_path = try path.join(allocator, &[_][]const u8{ versions, entry.name, ".zvm.json" });
        const version = readVersionInfo(allocator, version_info_path) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.debug("skipping {s} because it doesn't have a .zvm.json file", .{entry.name});
                    continue;
                },
                else => return err,
            }
        };
        if (version.channel) |channel| {
            try stdout.print("  - {s} " ++ ansi.fade("({s})\x0a"), .{ channel, version.version });
        } else {
            try stdout.print("  - {s}\x0a", .{version.version});
        }
    }
}

pub fn readVersionInfo(allocator: std.mem.Allocator, version_path: []const u8) !VersionInfo {
    const file = try std.fs.openFileAbsolute(version_path, .{});
    defer file.close();

    // read the file
    const file_size = try file.getEndPos();
    // check that the file size can fit in u32
    if (file_size > std.math.maxInt(u32)) return error.FileTooLarge;
    var buffer = try allocator.alloc(u8, @intCast(u32, file_size));
    defer allocator.free(buffer);
    _ = try file.readAll(buffer[0..]);

    // parse the json
    var stream = std.json.TokenStream.init(buffer);
    const version = try std.json.parse(VersionInfo, &stream, .{
        .allocator = allocator,
    });
    return version;
}