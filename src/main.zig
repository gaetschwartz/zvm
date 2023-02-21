const std = @import("std");
const arg_parser = @import("arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const path = std.fs.path;
const root = @import("root");
const build_options = @import("zvm_build_options");
const builtin = @import("builtin");
const ansi = @import("ansi");
const createParser = @import("parser.zig").createParser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    // parse args
    var parser = try createParser(allocator);
    defer parser.deinit();

    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) != 0) {
            std.log.debug("Set console output code page to UTF-8", .{});
        } else {
            std.log.debug("Failed to set console output code page to UTF-8", .{});
        }
    }

    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();
    try parser.parseArgv(&iter);

    parser.run() catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Zvm encountered an error while running " ++ ansi.c(.bold), .{});
        var args = try std.process.argsWithAllocator(std.heap.page_allocator);
        defer args.deinit();
        while (args.next()) |arg| {
            try stderr.print("{s} ", .{arg});
        }
        try stderr.print(ansi.c(.reset_bold) ++ ": " ++ ansi.style("{any}\n", .red), .{err});

        std.os.exit(1);
    };
}

pub fn zvm_cmd(ctx: ArgParser.RunContext) !void {
    const version = ctx.hasFlag("version");
    const verbose = ctx.hasFlag("verbose");
    const raw_version = ctx.hasFlag("raw-version");
    const stdout = std.io.getStdOut().writer();

    if (raw_version) {
        try stdout.print("{s}\n", .{build_options.version});
        return;
    }

    const zvmSimple =
        \\     ______   ___ __ ___  
        \\    |_  /\ \ / / '_ ` _ \ 
        \\     / /  \ V /| | | | | |
        \\    /___|  \_/ |_| |_| |_|
        \\                          
    ;
    const zvmComplex =
        \\                                          
        \\     █████████ █████ █████ █████████████  
        \\    ░█░░░░███ ░░███ ░░███ ░░███░░███░░███ 
        \\    ░   ███░   ░███  ░███  ░███ ░███ ░███ 
        \\      ███░   █ ░░███ ███   ░███ ░███ ░███ 
        \\     █████████  ░░█████    █████░███ █████
        \\    ░░░░░░░░░    ░░░░░    ░░░░░ ░░░ ░░░░░ 
        \\                                                                       
    ;

    try stdout.print("{s}\n", .{if (builtin.os.tag != .windows or windowsHasChcp65001()) zvmComplex else zvmSimple});

    if (version) {
        const start = comptime "  " ++ ansi.fade("-") ++ ansi.c(.blue) ++ ansi.c(.BOLD);
        const end = comptime ansi.c(.reset) ++ "\n";
        const rstBold = comptime ansi.c(.reset_bold);
        _ = try stdout.write(start ++ " version      " ++ rstBold ++ (build_options.version) ++ end);
        _ = try stdout.write(start ++ " commit_hash  " ++ rstBold ++ (build_options.git_commit orelse "unknown") ++ end);
        _ = try stdout.write(start ++ " build_date   " ++ rstBold ++ (build_options.build_date orelse "unknown") ++ end);
        _ = try stdout.write(start ++ " branch       " ++ rstBold ++ (build_options.git_branch orelse "unknown") ++ end);
        _ = try stdout.write(start ++ " zig          " ++ rstBold ++ std.fmt.comptimePrint("{}", .{builtin.zig_version}) ++ end);
        _ = try stdout.write(start ++ " target       " ++ rstBold ++ std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag) }) ++ end);

        if (verbose) {
            _ = try stdout.write(start ++ " is_ci        " ++ rstBold ++ (build_options.is_ci) ++ end);
        }
        return;
    }
    try ctx.command.printHelpWithOptions(std.io.getStdOut().writer(), .{
        .show_flags = false,
        .show_options = false,
    });
}

inline fn windowsHasChcp65001() bool {
    const chcp = std.os.windows.kernel32.GetConsoleOutputCP();
    std.log.debug("chcp: {d}", .{chcp});
    return chcp == 65001;
}
