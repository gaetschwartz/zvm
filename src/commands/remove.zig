const std = @import("std");
const mem = std.mem;
const ansi = @import("ansi");
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const RunContext = @import("../arg_parser.zig").ArgParser.RunContext;
const VersionInfo = @import("list.zig").VersionInfo;
const printCmd = @import("../utils.zig").printCmd;

pub fn remove_cmd(ctx: RunContext) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var allocator = arena.allocator();

    const target = ctx.getPositional("target").?;

    const zvm = try zvmDir(allocator);
    const version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "versions" });
    std.log.debug("version_path: {s}", .{version_path});
    // try to access the zig binary to make sure it exists
    var dir = std.fs.openDirAbsolute(version_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print(ansi.style("There is no version installed yet.\n", .red), .{});
            try stdout.print(ansi.style("Use " ++ ansi.bold("zvm install <version>") ++ " to install a version.\n", .green), .{});
            return;
        },
        else => return err,
    };
    defer dir.close();
    // check if the version is installed
    dir.access(target, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print(ansi.style("Version " ++ ansi.bold("{s}") ++ " is not installed yet.\n", .red), .{target});
            try stdout.print(ansi.style("Use " ++ ansi.bold("zvm install {s}") ++ " to install the version.\n", .green), .{target});
            return;
        },
        else => return err,
    };
    try dir.deleteTree(target);
    try stdout.print(ansi.style("Removed version " ++ ansi.bold("{s}") ++ ".\n", .green), .{target});
}

// recuring function to get the size of a directory
fn deleteDirRecursively(dir: std.fs.IterableDir) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .Directory => {
                var sub_dir = try dir.dir.openIterableDir(entry.name, .{});
                defer sub_dir.close();
                try deleteDirRecursively(sub_dir);
            },
            .File => {
                try dir.dir.deleteFile(entry.name);
            },
            .Symlink => {
                try dir.dir.deleteTree(entry.name);
            },
            else => {},
        }
    }
}
