const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const path = std.fs.path;
const ansi = @import("ansi");

pub fn zig_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const cwd = std.fs.cwd();
    // check if the cwd is a zvm project
    var buffer = [_]u8{0} ** std.fs.MAX_PATH_BYTES;
    const zig_version = blk: {
        break :blk cwd.readLink(".zvm", buffer[0..]) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.debug(
                    "No version is configured for this project. Try running " ++ ansi.bold("zvm use <version>") ++ ".\n",
                    .{},
                );
                const zvm = try zvmDir(allocator);
                const global_version_path = try path.join(allocator, &[_][]const u8{ zvm, "default" });
                // remove the current symlink if it exists
                break :blk global_version_path;
            },
            else => |e| return e,
        };
    };
    std.fs.accessAbsolute(zig_version, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const name = path.basename(zig_version);
            try stderr.print(ansi.style(
                "Failed to find the symlinked zig version. Try re-running " ++ ansi.bold("zvm install {s}\n"),
                .red,
            ), .{name});
            return;
        },
        else => |e| return e,
    };
    const zig_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_version, "zig" });

    var argvs = std.ArrayList([]const u8).init(allocator);
    try argvs.append(zig_path);
    for (ctx.args.raw_args.items) |arg| {
        try argvs.append(arg);
    }
    const argv = try argvs.toOwnedSlice();

    if (@import("builtin").mode == .Debug) {
        try stderr.print("debug: Running ", .{});
        try printArgv(argv, stderr);
        try stderr.print("\n", .{});
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
    var first = true;

    for (argv) |arg| {
        if (!first) {
            try stdout.print(" ", .{});
        }
        first = false;
        try stdout.print(ansi.bold("{s}"), .{arg});
    }
}
