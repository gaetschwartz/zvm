const std = @import("std");
const io = std.io;
const fs = std.fs;
const ansi = @import("ansi");

fn printCmd(argv: []const []const u8) void {
    for (argv) |arg| {
        std.log.debug("{s}{s}{s} ", .{ ansi.c(.BOLD), arg, ansi.c(.RESET_BOLD) });
    }
}

pub const CommandResult = union(enum) {
    Term: struct {
        cmd: []const []const u8,
        cwd: ?[]const u8 = null,
        term: std.ChildProcess.Term,
        stdout: ?[]const u8,
        stderr: ?[]const u8,
        allocator: ?std.mem.Allocator,
    },
    Error: struct {
        cmd: []const []const u8,
        cwd: ?[]const u8 = null,
        err: anyerror,
    },

    pub fn deinit(self: CommandResult) void {
        switch (self) {
            .Term => |term| {
                if (term.stdout) |stdout| {
                    term.allocator.?.free(stdout);
                }
                if (term.stderr) |stderr| {
                    term.allocator.?.free(stderr);
                }
            },
            .Error => |_| {},
        }
    }
};

pub const StdIo = enum {
    Inherit,
    Ignore,
    Pipe,
    Close,
    Capture,
};

fn stdioToChildProcessStdio(stdio: StdIo) std.ChildProcess.StdIo {
    return switch (stdio) {
        .Inherit => std.ChildProcess.StdIo.Inherit,
        .Ignore => std.ChildProcess.StdIo.Ignore,
        .Pipe => std.ChildProcess.StdIo.Pipe,
        .Close => std.ChildProcess.StdIo.Close,
        .Capture => std.ChildProcess.StdIo.Pipe,
    };
}

const RunArguments = struct {
    cmd: []const []const u8,
    cwd: ?[]const u8 = null,
    stdout_behavior: StdIo = .Inherit,
    stderr_behavior: StdIo = .Inherit,
    allocator: ?std.mem.Allocator = null,
    max_size: usize = 4096,
};

pub fn runAdvanced(args: RunArguments) CommandResult {
    // check that if any of the stdio is set to capture, that an allocator is provided
    var allocator: std.mem.Allocator = undefined;

    if (args.allocator) |a| {
        allocator = a;
    } else {
        allocator = std.heap.page_allocator;
        if (args.stdout_behavior == .Capture or args.stderr_behavior == .Capture) {
            return CommandResult{ .Error = .{
                .cmd = args.cmd,
                .cwd = args.cwd,
                .err = error.NoAllocatorProvided,
            } };
        }
    }

    var process: std.ChildProcess = std.ChildProcess.init(args.cmd, allocator);
    if (args.cwd) |cwd|
        process.cwd = cwd;
    process.stdout_behavior = stdioToChildProcessStdio(args.stdout_behavior);
    process.stderr_behavior = stdioToChildProcessStdio(args.stderr_behavior);
    process.spawn() catch |err| {
        return CommandResult{ .Error = .{
            .cmd = args.cmd,
            .cwd = args.cwd,
            .err = err,
        } };
    };

    var stdout: ?[]u8 = null;
    var stderr: ?[]u8 = null;

    if (args.stdout_behavior == .Capture) {
        const reader = process.stdout.?.reader();
        stdout = reader.readAllAlloc(args.allocator.?, args.max_size) catch |err| {
            return CommandResult{ .Error = .{
                .cmd = args.cmd,
                .cwd = args.cwd,
                .err = err,
            } };
        };
    }
    if (args.stderr_behavior == .Capture) {
        const reader = process.stderr.?.reader();
        stderr = reader.readAllAlloc(args.allocator.?, args.max_size) catch |err| {
            return CommandResult{ .Error = .{
                .cmd = args.cmd,
                .cwd = args.cwd,
                .err = err,
            } };
        };
    }

    const term = process.wait() catch |err| {
        return CommandResult{ .Error = .{
            .cmd = args.cmd,
            .cwd = args.cwd,
            .err = err,
        } };
    };
    return CommandResult{ .Term = .{
        .cmd = args.cmd,
        .cwd = args.cwd,
        .term = term,
        .stdout = stdout,
        .stderr = stderr,
        .allocator = args.allocator,
    } };
}

pub fn run(cmd: []const []const u8) void {
    const res = runAdvanced(.{
        .cmd = cmd,
    });
    handleResult(res);
}

pub fn runCmd(cmd: []const u8) void {
    var split = std.mem.split(u8, cmd, " ");
    var args = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer args.deinit();
    while (split.next()) |arg| {
        args.append(arg) catch unreachable;
    }
    var owned = args.toOwnedSlice();
    return run(owned);
}

pub fn handleResult(res: CommandResult) void {
    switch (res) {
        .Term => |term| {
            switch (term.term) {
                .Exited => |code| {
                    if (code != 0) {
                        std.log.debug("{s}Command ", .{ansi.c(.RED)});
                        printCmd(term.cmd);
                        std.log.debug("exited with code {d}.{s}\n", .{ code, ansi.c(.RESET) });
                    }
                },
                .Signal => |signal| {
                    // std.log.debug("Command {any} was signaled with {d}\n", .{ term.cmd, signal });
                    std.log.debug("{s}Command ", .{ansi.c(.RED)});
                    printCmd(term.cmd);
                    std.log.debug("was signaled with {d}.{s}\n", .{ signal, ansi.c(.RESET) });
                },
                else => {},
            }
        },
        .Error => |err| {
            // std.log.debug("Command {any} failed with error {any}\n", .{ err.cmd, err.err });
            std.log.debug("{s}Command ", .{ansi.c(.RED)});
            printCmd(err.cmd);
            std.log.debug("failed with error {any}.{s}\n", .{ err.err, ansi.c(.RESET) });
        },
    }
}
