const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const zvmDir = @import("../utils.zig").zvmDir;
const path = std.fs.path;
const ansi = @import("ansi");

pub const ZvmConfig = struct {
    git_dir_path: ?[]const u8 = null,

    pub const default = ZvmConfig{};
};

const FieldDesc = struct {
    name: []const u8,
    desc: []const u8,
};

const descriptions = std.ComptimeStringMap([]const u8, .{
    .{ "git_dir_path", "The path to the git directory" },
});

comptime {
    const typeInfo = @typeInfo(ZvmConfig);
    inline for (typeInfo.Struct.fields) |field| {
        if (!descriptions.has(field.name)) {
            @compileError("Missing description for field: " ++ field.name);
        }
    }
}

pub fn config_cmd(ctx: ArgParser.RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    const stdout = std.io.getStdOut().writer();

    const zvm = try zvmDir(allocator);
    std.log.debug("Config command: {s}", .{ctx.command.name});

    if (std.mem.eql(u8, ctx.command.name, "config")) {
        // print the config
        const cfg = try readConfig(.{ .allocator = allocator, .zvm_path = zvm });
        defer freeConfig(allocator, cfg);

        if (@import("builtin").mode == .Debug) {
            std.log.debug("config: {any}", .{cfg});
        }
        const config_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "config.json" });
        try stdout.print("Current config: " ++ ansi.fade("({s})\n"), .{config_path});
        const typeInfo = @typeInfo(ZvmConfig);
        inline for (typeInfo.Struct.fields) |field| {
            const value = @field(cfg, field.name);
            const ti = @typeInfo(@TypeOf(value));
            switch (ti) {
                .Optional => {
                    if (value) |v| {
                        const ti2 = @typeInfo(@TypeOf(v));
                        switch (ti2) {
                            .Pointer => {
                                // check if it is a string
                                if (ti2.Pointer.child == u8) {
                                    try stdout.print("  {s}: {s}\n", .{ field.name, v });
                                } else {
                                    try stdout.print("  {s}: {any}\n", .{ field.name, v });
                                }
                            },
                            else => {
                                std.log.debug("unhandled type: {any}", .{@typeInfo(@TypeOf(v))});
                                try stdout.print("  {s}: {any}\n", .{ field.name, v });
                            },
                        }
                    } else {
                        try stdout.print("  {s}: null\n", .{field.name});
                    }
                },
                .Pointer => {
                    // check if it is a string
                    if (ti.Pointer.child == u8) {
                        try stdout.print("  {s}: {s}\n", .{ field.name, value });
                    } else {
                        std.log.debug("unhandled type: {any}", .{@typeInfo(@TypeOf(value))});
                        try stdout.print("  {s}: {any}\n", .{ field.name, value });
                    }
                },
                else => {
                    try stdout.print("  {s}: {any}\n", .{ field.name, value });
                },
            }
        }
    } else if (std.mem.eql(u8, ctx.command.name, "set")) {
        // set the config
        const cfg = try readConfig(.{ .allocator = allocator, .zvm_path = zvm });
        defer freeConfig(allocator, cfg);

        const key = ctx.getPositional("key").?;
        const value = ctx.getPositional("value");

        var new_cfg = ZvmConfig{};
        const typeInfo = @typeInfo(ZvmConfig);
        var found = false;
        inline for (typeInfo.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                found = true;
                if (value) |v| {
                    @field(new_cfg, field.name) = v;
                } else {
                    // dont set the field
                }
            } else {
                // copy the field
                const old = @field(cfg, field.name);
                const new = try allocator.create(@TypeOf(old));
                new.* = old;
                @field(new_cfg, field.name) = new.*;
            }
        }
        if (!found) {
            try stdout.print(ansi.style("Unknown config field: " ++ ansi.bold("{s}\n"), .red), .{key});
            try stdout.print(ansi.fade("Available fields:\n"), .{});

            inline for (typeInfo.Struct.fields) |field| {
                try stdout.print(ansi.fade("  {s}: {s}\n"), .{ field.name, descriptions.get(field.name).? });
            }
            std.os.exit(1);
        }

        try writeConfig(.{ .allocator = allocator, .zvm_path = zvm }, new_cfg);
    } else if (std.mem.eql(u8, ctx.command.name, "clear")) {
        // clear the config
        try writeConfig(.{ .allocator = allocator, .zvm_path = zvm }, ZvmConfig.default);
    }
}

const Context = struct {
    allocator: std.mem.Allocator,
    zvm_path: []const u8,
};

pub fn readConfig(context: Context) !ZvmConfig {
    const zvm = context.zvm_path;
    const config_path = try std.fs.path.join(context.allocator, &[_][]const u8{ zvm, "config.json" });
    defer context.allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ZvmConfig.default,
        else => return err,
    };
    defer file.close();

    // read the file
    const file_size = try file.getEndPos();
    // check that the file size can fit in u32
    if (file_size > std.math.maxInt(u32)) return error.FileTooLarge;
    var buffer = try context.allocator.alloc(u8, @intCast(u32, file_size));
    defer context.allocator.free(buffer);
    _ = try file.readAll(buffer[0..]);

    // parse the json
    var stream = std.json.TokenStream.init(buffer);
    const cfg = try std.json.parse(ZvmConfig, &stream, .{
        .allocator = context.allocator,
        .ignore_unknown_fields = true,
    });
    return cfg;
}

pub fn freeConfig(allocator: std.mem.Allocator, cfg: ZvmConfig) void {
    std.json.parseFree(ZvmConfig, cfg, .{ .allocator = allocator });
}

pub fn writeConfig(context: Context, config: ZvmConfig) !void {
    const zvm = context.zvm_path;
    const config_path = try std.fs.path.join(context.allocator, &[_][]const u8{ zvm, "config.json" });
    const file = try std.fs.createFileAbsolute(config_path, .{});
    defer file.close();

    try std.json.stringify(
        config,
        .{},
        file.writer(),
    );
}

pub fn complete_config_keys(ctx: Command.CompletionContext) !std.ArrayList(Command.Completion) {
    const stdout = std.io.getStdOut().writer();
    _ = stdout;
    var completions = std.ArrayList(Command.Completion).init(ctx.allocator);

    const typeInfo = @typeInfo(ZvmConfig);
    inline for (typeInfo.Struct.fields) |field| {
        try completions.append(Command.Completion{
            .name = field.name,
            .description = "The " ++ field.name ++ " config key",
        });
    }

    return completions;
}
