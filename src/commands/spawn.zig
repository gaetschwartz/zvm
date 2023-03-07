const std = @import("std");
const idx = @import("../index.zig");
const builtin = @import("builtin");
const http = std.http;
const mem = std.mem;
const ansi = @import("ansi");
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const RunContext = @import("../arg_parser.zig").ArgParser.RunContext;
const VersionInfo = @import("list.zig").VersionInfo;
const getTargetPath = @import("use.zig").getTargetPath;
const printCmd = @import("../utils.zig").printCmd;

pub fn spawn_cmd(ctx: RunContext) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var allocator = arena.allocator();

    const zvm = try zvmDir(allocator);

    const target = ctx.getPositional("target").?;
    const target_version_path: []const u8 = getTargetPath(allocator, zvm, target) catch |err| switch (err) {
        error.GitDirPathNotSet => std.os.exit(1),
        else => return err,
    };
    defer allocator.free(target_version_path);
    std.log.debug("target version path: {s}", .{target_version_path});

    const executableName = if (builtin.os.tag == .windows) "zig.exe" else "zig";
    const zig_path = try std.fs.path.join(allocator, &[_][]const u8{ target_version_path, executableName });
    // try to access the zig binary to make sure it exists
    std.fs.accessAbsolute(zig_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.debug("path {s} not found", .{zig_path});
            try stderr.print(ansi.style("Zig version " ++ ansi.bold("{s}") ++ " not found.\n", .red), .{
                target,
            });
            return;
        },
        else => |e| return e,
    };

    var argvs = std.ArrayList([]const u8).init(allocator);
    try argvs.append(zig_path);
    for (ctx.args.raw_args.items[1..]) |arg| {
        try argvs.append(arg);
    }
    const argv = try argvs.toOwnedSlice();

    if (@import("builtin").mode == .Debug) {
        try stderr.print("Spawning '", .{});
        try printArgv(argv, stderr);
        try stderr.print("'\n", .{});
    }

    var proc = std.ChildProcess.init(argv, allocator);
    proc.stderr_behavior = .Inherit;
    proc.stdout_behavior = .Inherit;

    try proc.spawn();

    const term = try proc.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                try stdout.print("{s}Command ", .{ansi.c(.RED)});
                try printArgv(argv, stdout);
                try stdout.print("exited with code {d}.{s}\n", .{ code, ansi.c(.RESET) });
            }
        },
        .Signal => |signal| {
            // std.log.debug("Command {any} was signaled with {d}\n", .{ term.cmd, signal });
            try stdout.print("{s}Command ", .{ansi.c(.RED)});
            try printArgv(argv, stdout);
            try stdout.print("was signaled with {d}.{s}\n", .{ signal, ansi.c(.RESET) });
        },
        else => {},
    }
}

inline fn printArgv(argv: [][]const u8, stdout: anytype) !void {
    for (argv) |arg| {
        try stdout.print(ansi.bold("{s} "), .{arg});
    }
}
