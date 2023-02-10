const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("ansi.zig");
const testing = std.testing;

pub fn Tuple2(comptime T1: type, comptime T2: type) type {
    return struct {
        t1: T1,
        t2: T2,
    };
}

pub const ParsedArgs = struct {
    positionals: std.ArrayList(Tuple2(Command.Positional, []const u8)),
    flags: std.StringArrayHashMap(Tuple2(Command.Flag, usize)),
    options: std.StringArrayHashMap(Tuple2(Command.Option, []const u8)),
    additional_flags: std.StringArrayHashMap(usize),
    additional_options: std.StringArrayHashMap([]const u8),
    additional_positionals: std.StringArrayHashMap([]const u8),
    raw_args: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn hasFlag(self: *ParsedArgs, key: []const u8) bool {
        return self.flags.contains(key) or self.additional_flags.contains(key);
    }

    pub fn deinit(self: *ParsedArgs) void {
        self.positionals.deinit();
        self.flags.deinit();
        self.options.deinit();
        self.additional_flags.deinit();
        self.additional_options.deinit();
        self.additional_positionals.deinit();
        self.raw_args.deinit();
    }

    fn flagForKey(key: []const u8, command: *Command) ?Command.Flag {
        for (command.flags) |flag| {
            if (flag.name != null and std.mem.eql(u8, key, &[_]u8{flag.name.?})) {
                return flag;
            }
            // same for long name
            if (flag.long_name != null and std.mem.eql(u8, key, flag.long_name.?)) {
                return flag;
            }
        }
        return null;
    }

    fn optionForKey(key: []const u8, command: *Command) ?Command.Option {
        for (command.options) |option| {
            if (option.name != null and std.mem.eql(u8, key, &[_]u8{option.name.?})) {
                return option;
            }
            // same for long name
            if (option.long_name != null and std.mem.eql(u8, key, option.long_name.?)) {
                return option;
            }
        }
        return null;
    }

    pub fn parseArgs(allocator: std.mem.Allocator, args: [][]const u8, command: *Command) !ParsedArgs {
        var positionals = std.ArrayList(Tuple2(Command.Positional, []const u8)).init(allocator);
        var flags = std.StringArrayHashMap(Tuple2(Command.Flag, usize)).init(allocator);
        var options = std.StringArrayHashMap(Tuple2(Command.Option, []const u8)).init(allocator);
        var additional_flags = std.StringArrayHashMap(usize).init(allocator);
        var additional_options = std.StringArrayHashMap([]const u8).init(allocator);
        var additional_positionals = std.StringArrayHashMap([]const u8).init(allocator);
        var raw_args = std.ArrayList([]const u8).init(allocator);

        var current_option: ?Command.Option = null;
        var current_positional_index: usize = 0;
        for (args) |arg| {
            try raw_args.append(arg);
            if (std.mem.startsWith(u8, arg, "--")) {
                // if contains '=' then it's an option
                const indexOfEq = std.mem.indexOf(u8, arg, "=");
                if (indexOfEq) |index| {
                    const key = arg[2..index];
                    const value = arg[index + 1 ..];
                    if (optionForKey(key, command)) |option| {
                        if (option.name) |name| try options.put(&[_]u8{name}, .{ .t1 = option, .t2 = value });
                        try options.put(key, .{ .t1 = option, .t2 = value });
                    } else {
                        try additional_options.put(key, value);
                    }
                } else {
                    // if it's a single character flag like "--f".
                    // in this case we must check if it is a flag or an option
                    // if it's an option, then the next argument is the value
                    const key = arg[2..];
                    if (optionForKey(key, command)) |option| {
                        current_option = option;
                    } else if (flagForKey(key, command)) |flag| {
                        if (flag.name) |name| try flags.put(&[_]u8{name}, .{ .t1 = flag, .t2 = 1 });
                        try flags.put(key, .{ .t1 = flag, .t2 = 1 });
                    } else {
                        try additional_flags.put(key, 1);
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // if contains '=' then it's an option
                const indexOfEq = std.mem.indexOf(u8, arg, "=");
                // only if it's a single character flag with an equals sign like so:
                // -f=bar
                if (indexOfEq != null and indexOfEq.? == 2) {
                    const key = arg[1..2];
                    const value = arg[3..];
                    if (optionForKey(key, command)) |option| {
                        try options.put(key, .{ .t1 = option, .t2 = value });
                        if (option.long_name) |name| try options.put(name, .{ .t1 = option, .t2 = value });
                    } else {
                        try additional_options.put(key, value);
                    }
                } else if (args.len > 2) {
                    var i: usize = 1;
                    while (i < arg.len) : (i += 1) {
                        const key = arg[i .. i + 1];
                        if (flagForKey(key, command)) |flag| {
                            try flags.put(key, .{ .t1 = flag, .t2 = 1 });
                            if (flag.long_name) |name| try flags.put(name, .{ .t1 = flag, .t2 = 1 });
                        } else {
                            try additional_flags.put(key, 1);
                        }
                    }
                } else {
                    // if it's a single character flag like "-f".
                    // in this case we must check if it is a flag or an option
                    // if it's an option, then the next argument is the value
                    const key = arg[1..];
                    if (optionForKey(key, command)) |option| {
                        current_option = option;
                    } else if (flagForKey(key, command)) |flag| {
                        try flags.put(key, .{ .t1 = flag, .t2 = 1 });
                        if (flag.long_name) |name| try flags.put(name, .{ .t1 = flag, .t2 = 1 });
                    } else {
                        try additional_flags.put(key, 1);
                    }
                }
            } else {
                if (current_option) |option| {
                    const name = option.long_name orelse &[_]u8{option.name.?};
                    try options.put(name, .{ .t1 = option, .t2 = arg });
                    current_option = null;
                } else if (current_positional_index < command.positionals.len) {
                    const positional = command.positionals[current_positional_index];
                    try positionals.append(.{ .t1 = positional, .t2 = arg });
                    current_positional_index += 1;
                } else {
                    try additional_positionals.put(arg, arg);
                }
            }
        }

        return .{
            .positionals = positionals,
            .flags = flags,
            .options = options,
            .additional_flags = additional_flags,
            .additional_options = additional_options,
            .additional_positionals = additional_positionals,
            .allocator = allocator,
            .raw_args = raw_args,
        };
    }

    pub fn check(self: *ParsedArgs, command: *Command) !void {
        const stderr = std.io.getStdErr().writer();

        // check if any required flags/options are missing
        for (command.flags) |flag| {
            if (flag.long_name != null and self.flags.contains(flag.long_name.?)) continue;
            if (flag.name != null and self.flags.contains(&[_]u8{flag.name.?})) continue;
            if (flag.optional) continue;
            stderr.print(ansi.style("Missing required flag: " ++ ansi.bold("{s}\n"), .red), .{flag.long_name.?}) catch {};
            std.os.exit(1);
        }
        for (command.options) |option| {
            if (option.long_name != null and self.options.contains(option.long_name.?)) continue;
            if (option.name != null and self.options.contains(&[_]u8{option.name.?})) continue;
            if (option.default_value) |default_value| {
                if (option.long_name) |name| try self.options.put(name, .{ .t1 = option, .t2 = default_value });
                if (option.name) |name| try self.options.put(&[_]u8{name}, .{ .t1 = option, .t2 = default_value });
                continue;
            }
            stderr.print(ansi.style("Missing required option: " ++ ansi.bold("{s}\n"), .red), .{option.long_name.?}) catch {};
            std.os.exit(1);
        }
        if (self.positionals.items.len < command.positionals.len) {
            const missing = command.positionals[self.positionals.items.len];
            stderr.print(ansi.style("Missing required positional: " ++ ansi.bold("{s}\n"), .red), .{missing.name}) catch {};
            std.os.exit(1);
        }
    }
};

pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    args: std.ArrayList([]const u8),
    root_command: ?Command = null,

    pub fn init(allocator: std.mem.Allocator, iter: *std.process.ArgIterator) !ArgParser {
        var args = std.ArrayList([]const u8).init(allocator);
        while (iter.next()) |arg| {
            try args.append(arg);
        }
        return .{
            .allocator = allocator,
            .args = args,
        };
    }

    pub fn initWithArgs(allocator: std.mem.Allocator, arguments: []const []const u8) !ArgParser {
        var args = std.ArrayList([]const u8).init(allocator);
        try args.appendSlice(arguments);
        return .{
            .allocator = allocator,
            .args = args,
        };
    }

    pub fn setRootCommand(self: *ArgParser, command: Command.CreateCommandOptions) void {
        self.root_command = .{
            .name = command.name,
            .description = command.description,
            .handler = command.handler,
            .flags = command.flags,
            .options = command.options,
            .commands = std.ArrayList(*Command).init(self.allocator),
            .allocator = self.allocator,
        };
    }

    pub fn addCommand(self: *ArgParser, command: Command.CreateCommandOptions) !*Command {
        if (self.root_command == null) return error.NoRootCommand;
        return try self.root_command.?.addCommand(command);
    }

    pub const RunContext = struct {
        args: *ParsedArgs,
        depth: usize,
        command: *Command,

        pub fn getPositional(self: RunContext, name: []const u8) ?[]const u8 {
            var i: usize = 0;
            while (i < self.command.positionals.len) : (i += 1) {
                if (std.mem.eql(u8, self.command.positionals[i].name, name)) {
                    return self.args.positionals.items[i].t2;
                }
            }
            return null;
        }

        pub fn getOption(self: RunContext, name: []const u8) ?[]const u8 {
            if (self.args.options.get(name)) |value| {
                return value.t2;
            }
            return null;
        }

        pub fn hasFlag(self: RunContext, name: []const u8) bool {
            return self.args.flags.contains(name);
        }
    };

    pub fn run(self: *ArgParser) !void {
        var command = &self.root_command.?;
        var depth: usize = 0;
        for (self.args.items[1..]) |command_name| {
            if (std.mem.startsWith(u8, command_name, "-")) {
                break;
            }
            switch (builtin.mode) {
                inline .Debug => {
                    std.debug.print("Commands at depth {d} of {s}:\n", .{ depth, command.name });
                    for (command.commands.items) |c| {
                        std.debug.print("  {s}", .{c.name});
                    }
                    std.debug.print("\n", .{});
                },
                inline else => {},
            }
            for (command.commands.items) |c| {
                if (std.mem.eql(u8, c.name, command_name)) {
                    std.log.debug("Found command: {s} at depth {d}", .{ command_name, depth });
                    command = c;
                    depth += 1;
                }
            }
        }
        var parsed_args = ParsedArgs.parseArgs(
            self.allocator,
            self.args.items[depth + 1 ..],
            command,
        ) catch |err| {
            std.io.getStdErr().writer().print("Error parsing arguments: {any}\n", .{err}) catch {};
            std.os.exit(1);
        };
        if (command.add_help) {
            if (parsed_args.additional_flags.contains("help") or
                parsed_args.additional_flags.contains("h"))
            {
                command.printHelp(std.io.getStdOut().writer()) catch |err| {
                    std.io.getStdErr().writer().print("Error printing help: {any}\n", .{err}) catch {};
                    std.os.exit(1);
                };
                return;
            }
        }
        if (command.handler == null) {
            std.log.debug("No handler for command: {s}", .{command.name});
            command.printHelp(std.io.getStdOut().writer()) catch |err| {
                std.io.getStdErr().writer().print("Error printing help: {any}\n", .{err}) catch {};
                std.os.exit(1);
            };
            return;
        }
        // check for missing required options
        try parsed_args.check(command);
        defer parsed_args.deinit();
        const context = RunContext{
            .args = &parsed_args,
            .depth = 1,
            .command = command,
        };
        try command.handler.?(context);
        return;
    }

    pub fn deinit(self: *ArgParser) void {
        self.args.deinit();
        if (self.root_command != null) self.root_command.?.deinit();
    }
};

// support only one level of subcommands
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    handler: ?*const fn (context: ArgParser.RunContext) anyerror!void,
    flags: []const Flag = &[_]Flag{},
    options: []const Option = &[_]Option{},
    positionals: []const Positional = &[_]Positional{},
    commands: std.ArrayList(*Command),
    allocator: std.mem.Allocator,
    parent: ?*Command = null,
    add_help: bool = true,

    pub const CreateCommandOptions = struct {
        name: []const u8,
        description: []const u8,
        handler: ?*const fn (context: ArgParser.RunContext) anyerror!void,
        flags: []const Flag = &[_]Flag{},
        options: []const Option = &[_]Option{},
        positionals: []const Positional = &[_]Positional{},
        add_help: bool = true,
    };

    pub fn addCommand(self: *Command, command: CreateCommandOptions) !*Command {
        const cmd = Command{
            .name = command.name,
            .description = command.description,
            .handler = command.handler,
            .flags = command.flags,
            .options = command.options,
            .positionals = command.positionals,
            .commands = std.ArrayList(*Command).init(self.allocator),
            .allocator = self.allocator,
            .parent = self,
            .add_help = command.add_help,
        };
        const cmd_ptr: *Command = try self.allocator.create(Command);
        cmd_ptr.* = cmd;
        try self.commands.append(cmd_ptr);
        return cmd_ptr;
    }

    pub fn deinit(self: *Command) void {
        for (self.commands.items) |ptr| {
            ptr.deinit();
            self.allocator.destroy(ptr);
        }
        self.commands.deinit();
        self.parent = null;
    }

    pub fn printHelp(self: Command, writer: anytype) !void {
        var tree = std.ArrayList([]const u8).init(self.allocator);
        defer tree.deinit();
        var command = &self;
        while (command.parent) |parent| {
            try tree.append(parent.name);
            command = parent;
        }
        try writer.print("{s}\n\n", .{self.description});
        try writer.print("Usage: ", .{});
        var i: usize = tree.items.len;
        while (i > 0) : (i -= 1) {
            try writer.print("{s} ", .{tree.items[i - 1]});
        }
        try writer.print("{s} ", .{self.name});
        for (self.positionals) |positional| {
            try writer.print("<{s}> ", .{positional.name});
        }
        try writer.print("[options]\n\n", .{});

        if (self.commands.items.len > 0) {
            try writer.print("Commands:\n", .{});
            var max_len: usize = 0;
            for (self.commands.items) |c| {
                if (c.name.len > max_len) {
                    max_len = c.name.len;
                }
            }
            const buf = try self.allocator.alloc(u8, max_len);
            defer self.allocator.free(buf);
            std.mem.set(u8, buf, ' ');
            for (self.commands.items) |c| {
                const spaces = buf[0 .. max_len - c.name.len];
                try writer.print("  {s}{s}    {s}\n", .{ c.name, spaces, c.description });
            }
        }

        if (self.flags.len > 0) {
            var max_len: usize = 2;
            for (self.flags) |flag| {
                if (flag.long_name) |long_name| {
                    if (long_name.len > max_len) {
                        max_len = long_name.len + 2;
                    }
                }
            }
            const buf = try self.allocator.alloc(u8, max_len);
            defer self.allocator.free(buf);
            std.mem.set(u8, buf, ' ');

            try writer.print("Flags:\n", .{});
            for (self.flags) |flag| {
                if (flag.name) |name| {
                    try writer.print("-{c}, ", .{name});
                } else {
                    try writer.print("    ", .{});
                }
                if (flag.long_name) |long_name| {
                    try writer.print("--{s}", .{long_name});
                } else {
                    try writer.print("  ", .{});
                }
                const spaces = buf[0 .. max_len - (flag.long_name orelse "").len - 2];
                try writer.print("{s}  {s}\n", .{ spaces, flag.description });
            }
        }

        if (self.options.len > 0) {
            try writer.print("\nOptions:\n", .{});
            for (self.options) |option| {
                try writer.print("  ", .{});
                if (option.name) |name| {
                    try writer.print("-{c}", .{name});
                }
                if (option.long_name) |long_name| {
                    if (option.name) |_| {
                        try writer.print(", ", .{});
                    }
                    try writer.print("--{s}", .{long_name});
                }
                try writer.print(" <{s}>", .{option.value_name});
                try writer.print(" \t{s}\n", .{option.description});
            }
        }
    }

    pub const Option = struct {
        name: ?u8 = null,
        long_name: ?[]const u8 = null,
        default_value: ?[]const u8 = null,
        description: []const u8 = "",
        value_name: []const u8 = "value",
    };

    pub const Flag = struct {
        name: ?u8,
        long_name: ?[]const u8,
        optional: bool = true,
        description: []const u8 = "",
    };

    pub const Positional = struct {
        name: []const u8,
        description: []const u8 = "",
        optional: bool = false,
    };
};

fn handler(ctx: ArgParser.RunContext) !void {
    try testing.expectEqualStrings(ctx.getPositional("positional").?, "positional_value");
    try testing.expect(ctx.hasFlag("long"));
    try testing.expect(ctx.hasFlag("s"));
    try testing.expectEqualStrings(ctx.getOption("option").?, "default_option_value");
    try testing.expectEqualStrings(ctx.getOption("p").?, "short");
}

fn throw_handler(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    return error.ThrowHandlerCalled;
}

test "parsing sample data" {
    var allocator = std.testing.allocator;
    var argv = &[_][]const u8{
        "test",
        "command",
        "positional_value",
        "-s",
        "--long",
        "-p=short",
    };
    var parser = try ArgParser.initWithArgs(allocator, argv);
    defer parser.deinit();

    parser.setRootCommand(.{
        .name = "root",
        .description = "root description",
        .handler = throw_handler,
    });

    _ = try parser.addCommand(.{
        .name = "command",
        .description = "command description",
        .handler = handler,
        .flags = &[_]Command.Flag{
            Command.Flag{
                .name = null,
                .long_name = "long",
                .description = "flag description",
            },
            Command.Flag{
                .name = 's',
                .long_name = null,
                .description = "flag description",
            },
        },
        .options = &[_]Command.Option{
            Command.Option{
                .name = 'o',
                .long_name = "option",
                .value_name = "option_value",
                .description = "option description",
                .default_value = "default_option_value",
            },
            Command.Option{
                .name = 'p',
                .long_name = "potion",
                .value_name = "option_value",
                .description = "option description",
            },
        },
        .positionals = &[_]Command.Positional{
            Command.Positional{
                .name = "positional",
                .description = "positional description",
            },
        },
    });

    try parser.run();
}

test "parsing " {
    var allocator = std.testing.allocator;
    var argv = &[_][]const u8{
        "test",
        "command",
        "positional_value",
        "-s",
        "--long",
        "-p=short",
    };
    var parser = try ArgParser.initWithArgs(allocator, argv);
    defer parser.deinit();

    parser.setRootCommand(.{
        .name = "root",
        .description = "root description",
        .handler = throw_handler,
    });

    parser.run() catch |err| switch (err) {
        error.ThrowHandlerCalled => {},
        else => return err,
    };
}
