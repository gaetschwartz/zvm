const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const zvmDir = @import("../utils.zig").zvmDir;
const path = std.fs.path;
const ansi = @import("ansi");
const config = @import("config.zig");
const builtin = @import("builtin");

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

    const zvm = try zvmDir(allocator);
    const global_version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "default" });
    // read symlink
    var temp: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const symlinked_path = blk: {
        break :blk std.fs.readLinkAbsolute(global_version_path, &temp) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.debug("global version not found", .{});
                    break :blk null;
                },
                else => return err,
            }
        };
    };
    try stdout.print("Installed versions:\x0a", .{});

    const printGitVersionThread = try std.Thread.spawn(.{}, printGitVersionThreaded, .{ allocator, zvm, symlinked_path });

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

    while (try it.next()) |entry| {
        if (entry.kind != .Directory) continue;
        const version_info_path = try path.join(allocator, &[_][]const u8{ versions, entry.name, ".zvm.json" });
        const version = readVersionInfo(allocator, version_info_path) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    try stderr.print(ansi.style("error: version info not found for {s}\x0a", .{.red}), .{entry.name});
                    try stderr.print(ansi.style("Consider destroying the current zvm installation using `zvm destroy` and reinstalling that version.\x0a", .{ .red, .fade }), .{});
                    continue;
                },
                else => return err,
            }
        };

        const is_default = symlinked_path != null and std.mem.eql(u8, symlinked_path.?, std.fs.path.dirname(version_info_path).?);
        const startSymbol = if (is_default) (comptime ansi.c(.green) ++ ">") else comptime ansi.fade("-");
        if (version.channel) |channel| {
            try stdout.print("  {s} {s} " ++ ansi.fade("({s})\x0a") ++ ansi.c(.reset), .{ startSymbol, version.version, channel });
        } else {
            try stdout.print("  {s} {s}\x0a" ++ ansi.c(.reset), .{ startSymbol, version.version });
        }
    }

    printGitVersionThread.join();
}

fn printGitVersionThreaded(allocator: std.mem.Allocator, zvm: []const u8, symlinked_path: ?[]const u8) void {
    printGitVersion(allocator, zvm, symlinked_path) catch |err| {
        std.log.err("error: {s}", .{@errorName(err)});
    };
}

fn printGitVersion(allocator: std.mem.Allocator, zvm: []const u8, symlinked_path: ?[]const u8) !void {
    std.log.debug("started printGitVersion", .{});
    const stdout = std.io.getStdOut().writer();
    // ? get current config and check if there is a git path setup
    const cfg = try config.readConfig(.{ .zvm_path = zvm, .allocator = allocator });
    defer config.freeConfig(allocator, cfg);
    if (cfg.git_dir_path) |git_dir_path| {
        blk: {
            std.log.debug("git_dir_path: {s}", .{git_dir_path});
            const executableName = if (builtin.os.tag == .windows) "zig.exe" else "zig";
            const zig_path = try path.join(allocator, &[_][]const u8{ git_dir_path, executableName });

            const stat = std.fs.cwd().statFile(zig_path) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        std.log.err("zig not found in git_dir_path ({s})", .{git_dir_path});
                        break :blk;
                    },
                    else => return err,
                }
            };

            if (stat.kind != .File) {
                std.log.err("zig is not a file in git_dir_path ({s})", .{git_dir_path});
                break :blk;
            }

            // exec zig version
            const res = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &[_][]const u8{ zig_path, "version" } });
            defer allocator.free(res.stdout);
            defer allocator.free(res.stderr);

            // read the output
            var version = res.stdout;
            for (version, 0..) |c, i| {
                if (c == '\n') {
                    version = version[0..i];
                    break;
                }
            }

            // print the output
            const is_default = symlinked_path != null and std.mem.eql(u8, symlinked_path.?, git_dir_path);
            const startSymbol = if (is_default) (comptime ansi.c(.green) ++ ">") else comptime ansi.fade("-");
            try stdout.print("  {s} {s} " ++ ansi.fade("(git)\x0a") ++ ansi.c(.reset), .{ startSymbol, version });
        }
    } else {
        std.log.debug("no git_dir_path", .{});
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
        .ignore_unknown_fields = true,
    });
    return version;
}
