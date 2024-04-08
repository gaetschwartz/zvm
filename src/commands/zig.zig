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

pub fn zig_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const verbose = ctx.args.hasFlag("verbose");
    _ = verbose;

    const cwd = std.fs.cwd();
    // check if the cwd is a zvm project
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const zvm = try zvmDir(allocator);
    const zig_dir_path = blk: {
        break :blk cwd.readLink(".zvm", buffer[0..]) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.debug(
                    "No version is configured for this project. Try running " ++ ansi.bold("zvm use <version>") ++ ".\n",
                    .{},
                );
                const global_version_path = try path.join(allocator, &[_][]const u8{ zvm, "default" });
                // remove the current symlink if it exists
                break :blk global_version_path;
            },
            else => |e| return e,
        };
    };
    std.fs.accessAbsolute(zig_dir_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const name = path.basename(zig_dir_path);
            try stderr.print(ansi.style(
                "Failed to find the symlinked zig version. Try re-running " ++ ansi.bold("zvm install {s}\n"),
                .red,
            ), .{name});
            return;
        },
        else => |e| return e,
    };

    const parsed = try config.readConfig(.{ .zvm_path = zvm, .allocator = allocator });
    defer parsed.deinit();

    const cfg = parsed.value;

    var zig_path: []const u8 = undefined;
    if (cfg.git_dir_path) |git_dir_path| {
        std.log.debug("git_dir_path: {s}", .{git_dir_path});
        var temp: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const symlinked = std.fs.readLinkAbsolute(zig_dir_path, &temp) catch |err| switch (err) {
            error.NotLink => zig_dir_path,
            else => |e| return e,
        };
        if (std.mem.eql(u8, symlinked, git_dir_path)) {
            // symlinked to the same path, so we need to update it
            zig_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_dir_path, "zig" });
        } else {
            zig_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_dir_path, "zig" });
        }
    } else {
        std.log.debug("git_dir_path: null", .{});
        zig_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_dir_path, "zig" });
    }

    std.log.debug("Using zig version {s} at {s}...", .{ path.basename(zig_dir_path), zig_dir_path });

    var argvs = std.ArrayList([]const u8).init(allocator);
    try argvs.append(zig_path);
    for (ctx.args.raw_args.items) |arg| {
        try argvs.append(arg);
    }
    const argv = try argvs.toOwnedSlice();

    if (builtin.mode == .Debug) {
        try stderr.print("debug: Running ", .{});
        try printArgv(argv, stderr);
        try stderr.print("\n", .{});
    }

    var proc = std.ChildProcess.init(argv, allocator);
    proc.stderr_behavior = .Inherit;
    proc.stdout_behavior = .Inherit;
    proc.stdin_behavior = .Inherit;

    try proc.spawn();

    const term = try proc.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                try stdout.print("{s}Command ", .{ansi.c(.RED)});
                try printArgv(argv, stdout);
                try stdout.print(" exited with code {d}.{s}\n", .{ code, ansi.c(.RESET) });
            }
        },
        .Signal => |signal| {
            // std.log.debug("Command {any} was signaled with {d}\n", .{ term.cmd, signal });
            try stdout.print("{s}Command ", .{ansi.c(.RED)});
            try printArgv(argv, stdout);
            try stdout.print(" was signaled with {d}.{s}\n", .{ signal, ansi.c(.RESET) });
        },
        else => {},
    }
}

inline fn printArgv(argv: [][]const u8, stdout: anytype) !void {
    if (argv.len == 0) return;
    try stdout.print(ansi.bold("{s}"), .{argv[0]});
    for (argv[1..]) |arg| {
        try stdout.print(ansi.bold(" {s}"), .{arg});
    }
}
