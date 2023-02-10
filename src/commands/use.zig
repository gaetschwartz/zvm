const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const path = std.fs.path;
const ansi = @import("../ansi.zig");

pub fn use_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const target = ctx.getPositional("target").?;
    const global = ctx.args.hasFlag("global");
    const force = ctx.args.hasFlag("force");

    const zvm = try zvmDir(allocator);
    const target_version = try path.join(allocator, &[_][]const u8{ zvm, "versions", target });
    // check if the target version exists
    std.fs.accessAbsolute(target_version, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print(
                ansi.style("Version " ++ ansi.bold("{s}") ++ " doesn't appear to be installed.\n", .red),
                .{target},
            );
            return;
        },
        else => return err,
    };

    if (global) {
        const global_version_path = try path.join(allocator, &[_][]const u8{ zvm, "global" });
        // remove the current symlink if it exists
        std.fs.deleteFileAbsolute(global_version_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        // create the new symlink
        try std.fs.symLinkAbsolute(target_version, global_version_path, .{});
        try stdout.print(ansi.style("Now using zig version " ++ ansi.bold("{s}") ++ " globally ✓\n", .green), .{target});
    } else {
        const cwd = std.fs.cwd();
        // check if the cwd is a zvm project
        if (!force) {
            cwd.access("build.zig", .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try stderr.print(
                        ansi.style("You do not appear to be in a zig project." ++
                            " If you are sure you want to use " ++ ansi.bold("{s}") ++
                            " in this directory, run again with " ++ ansi.bold("--force") ++ ".\n", .red),
                        .{target},
                    );
                    return;
                },
                else => return err,
            };
        }

        // remove the current symlink if it exists
        cwd.deleteFile(".zvm") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        // create the new symlink
        try cwd.symLink(target_version, ".zvm", .{});
        try stdout.print(ansi.style("Now using zig version " ++ ansi.bold("{s}") ++ " in this directory ✓\n", .green), .{target});
    }
}
