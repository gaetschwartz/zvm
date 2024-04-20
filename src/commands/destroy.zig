const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const path = std.fs.path;
const ansi = @import("ansi");

pub fn destroy_cmd(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const zvm = zvmDir(allocator) catch |err| {
        try stderr.print(ansi.style("Could not get zvm directory: {any}", .red), .{err});
        return;
    };

    std.fs.deleteTreeAbsolute(zvm) catch |err| {
        try stderr.print(ansi.style("Could not delete zvm directory: {any}", .red), .{err});
        return;
    };

    try stdout.print(ansi.style("Successfully destroyed the current zvm installation.\n", .green), .{});
}
