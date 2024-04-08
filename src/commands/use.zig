const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const ansi = @import("ansi");
const config = @import("config.zig");

pub fn use_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const global = ctx.args.hasFlag("global");
    const force = ctx.args.hasFlag("force");

    const zvm = try zvmDir(allocator);

    if (ctx.getPositional("target") == null) {
        var symlink_temp: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var symlink_dest: []const u8 = undefined;
        var location: []const u8 = undefined;
        if (global) {
            const global_version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "default" });
            symlink_dest = std.fs.readLinkAbsolute(global_version_path, &symlink_temp) catch |err| switch (err) {
                error.FileNotFound => {
                    try stderr.print(
                        ansi.style("You haven't set a global zig version yet." ++
                            " Use " ++ ansi.bold("zvm use --global <version>") ++
                            " to set one up.\n", .red),
                        .{},
                    );
                    return;
                },
                else => return err,
            };
            location = "globally";
        } else {
            const cwd = std.fs.cwd();

            symlink_dest = cwd.readLink(".zvm", &symlink_temp) catch |err| switch (err) {
                error.FileNotFound => {
                    try stderr.print(
                        ansi.style("You haven't set a local zig version yet." ++
                            " Use " ++ ansi.bold("zvm use <version>") ++
                            " to set one up.\n", .red),
                        .{},
                    );
                    return;
                },
                else => return err,
            };
            location = "in this directory";
        }
        try stdout.print("Currently using zig at " ++ ansi.bold("{s}") ++ " {s}.\n", .{ symlink_dest, location });
        return;
    }

    const target = ctx.getPositional("target").?;
    const target_version_path: []const u8 = getTargetPath(allocator, zvm, target) catch |err| switch (err) {
        error.GitDirPathNotSet => std.os.exit(1),
        else => return err,
    };
    defer allocator.free(target_version_path);

    std.log.debug("target_version_path: {s}", .{target_version_path});
    // check if the target version exists
    std.fs.accessAbsolute(target_version_path, .{}) catch |err| switch (err) {
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
        const global_version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "default" });
        // remove the current symlink if it exists
        std.fs.deleteFileAbsolute(global_version_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        // create the new symlink
        try std.fs.symLinkAbsolute(target_version_path, global_version_path, .{ .is_directory = true });
        // check the current path and check if the current version is in the path
        const path: ?[]const u8 = std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        defer if (path) |p|
            allocator.free(p);

        if (path) |p| {
            std.log.debug("PATH environment variable found: {s}", .{p});
            // split the path into an array

            const found = blk: {
                if (std.mem.indexOf(u8, p, global_version_path)) |idx| {
                    // check if the path is at the beginning of the string
                    if (idx == 0) {
                        break :blk true;
                    }
                    // check if the path is at the end of the string
                    if (idx + global_version_path.len == p.len) {
                        break :blk true;
                    }
                    // check if the path is surrounded by colons
                    if (p[idx - 1] == ':' and p[idx + global_version_path.len] == ':') {
                        break :blk true;
                    }
                }
                break :blk false;
            };
            if (!found) {
                try stdout.print(ansi.style("Warning: the path {s} is not in your PATH environment variable.\n", .{ .fade, .red }), .{global_version_path});
                try stdout.print(ansi.style("You need to add it to your PATH environment variable to use zig globally.\n", .{ .fade, .red }), .{});
            } else {
                std.log.debug("the path {s} is in your PATH environment variable.", .{global_version_path});
            }
        } else {
            std.log.debug("PATH environment variable not found.", .{});
        }

        try stdout.print(ansi.style("Now using zig version " ++ ansi.bold("{s}") ++ " globally.\n", .green), .{target});
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
        try cwd.symLink(target_version_path, ".zvm", .{});
        try stdout.print(ansi.style("Now using zig version " ++ ansi.bold("{s}") ++ " in this directory.\n", .green), .{target});
    }
}
pub fn version_complete(ctx: Command.CompletionContext) !std.ArrayList(Command.Completion) {
    var allocator = ctx.allocator;
    var completions = std.ArrayList(Command.Completion).init(allocator);

    const stdout = std.io.getStdOut().writer();
    _ = stdout;

    const zvm = try zvmDir(allocator);
    defer allocator.free(zvm);

    const versions_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "versions" });
    defer allocator.free(versions_path);

    var dir = try std.fs.openIterableDirAbsolute(versions_path, .{});
    defer dir.close();
    var iter = dir.iterate();

    const parsed = try config.readConfig(.{ .zvm_path = zvm, .allocator = allocator });
    defer config.freeConfig(parsed);

    const cfg = parsed.value;

    if (cfg.git_dir_path) |_| {
        try completions.append(Command.Completion{
            .name = "git",
        });
    }

    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            try completions.append(Command.Completion{
                .name = entry.name,
            });
        }
    }
    return completions;
}

pub fn getTargetPath(allocator: std.mem.Allocator, zvm: []const u8, target: []const u8) ![]const u8 {
    const stderr = std.io.getStdErr().writer();

    if (std.mem.eql(u8, target, "git")) {
        const parsed = try config.readConfig(.{ .zvm_path = zvm, .allocator = allocator });
        defer config.freeConfig(parsed);
        const cfg = parsed.value;

        if (cfg.git_dir_path) |git_dir_path| {
            std.log.debug("git_dir_path: {s}", .{git_dir_path});
            return try allocator.dupe(u8, git_dir_path);
        } else {
            try stderr.print(
                ansi.style("You haven't setup a git repository of zig yet." ++
                    " Use " ++ ansi.bold("zvm config set git_dir_path <path>") ++
                    " to set one up.\n", .red),
                .{},
            );
            return error.GitDirPathNotSet;
        }
    } else {
        std.log.debug("no git_dir_path", .{});
        return try std.fs.path.join(allocator, &[_][]const u8{ zvm, "versions", target });
    }
}
