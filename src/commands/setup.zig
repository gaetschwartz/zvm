const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const ansi = @import("ansi");
const config = @import("config.zig");

pub fn setup_cmd(ctx: ArgParser.RunContext) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // try to infer shell
    const shell = std.process.getEnvVarOwned(allocator, "SHELL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            _ = try stderr.write(ansi.c(.red) ++ "Could not infer shell, please setup manually.\n" ++ ansi.c(.RESET));
            return;
        },
        else => return err,
    };

    const shellName = std.fs.path.basename(shell);
    inline for (shells) |s| {
        if (std.mem.eql(u8, shellName, s.@"0")) {
            const setup: *const SetupFn = s.@"1";
            setup(ctx) catch |err| {
                try stderr.print(ansi.c(.RED) ++ "Error setting up shell: {s}\n" ++ ansi.c(.RESET), .{@errorName(err)});
                return;
            };
            try stdout.print(ansi.c(.GREEN) ++ "Successfully setup shell.\n" ++ ansi.c(.RESET), .{});
            return;
        }
    }
}
const SetupError = error{Io} || utils.ZvmDirError || std.os.WriteError || std.os.SeekError || std.fs.File.OpenError || std.process.GetEnvVarOwnedError;
const SetupFn = fn (ctx: ArgParser.RunContext) SetupError!void;
const shells = [_]std.meta.Tuple(&.{ []const u8, *const SetupFn }){
    // .{ "bash", setup_bash },
    .{ "zsh", &setup_zsh },
    // .{ "fish", setup_fish },
};

fn setup_zsh(_: ArgParser.RunContext) SetupError!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const zvm = try utils.zvmDir(allocator);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    const zshrcPath = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zshrc" });
    const zshrc = try std.fs.openFileAbsolute(zshrcPath, .{ .mode = .read_write });
    defer zshrc.close();

    try zshrc.seekFromEnd(0);

    try zshrc.writeAll("\n# ZVM setup\n");
    try zshrc.writeAll("export ZVM_DIR=");
    try zshrc.writeAll(zvm);
    try zshrc.writeAll("\nexport PATH=\"$ZVM_DIR/default/:$PATH\"\n# End ZVM setup\n");
}
