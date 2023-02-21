const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("ansi");
const testing = std.testing;

pub fn Pair(comptime T1: type, comptime T2: type) type {
    return struct { t1: T1, t2: T2 };
}

pub const ParsedArgs = struct {
    positionals: std.ArrayList(Pair(Command.Positional, []const u8)),
    flags: StructArrayHashMap(ShortOrLong, Pair(Command.Flag, usize)),
    options: StructArrayHashMap(ShortOrLong, Pair(Command.Option, []const u8)),
    additional_flags: StructArrayHashMap(ShortOrLong, usize),
    additional_options: StructArrayHashMap(ShortOrLong, []const u8),
    additional_positionals: std.ArrayList([]const u8),
    raw_args: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn hasFlag(self: *ParsedArgs, key: []const u8) bool {
        if (key.len == 1) {
            return self.flags.contains(.{ .short = key[0] }) or self.additional_flags.contains(.{ .short = key[0] });
        } else {
            return self.flags.contains(.{ .long = key }) or self.additional_flags.contains(.{ .long = key });
        }
        return false;
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

    pub const ShortOrLong = union(enum) {
        short: u8,
        long: []const u8,
    };

    fn addOrIncrementAddiFlag(flags: *StructArrayHashMap(ShortOrLong, usize), key: ShortOrLong) !void {
        if (flags.get(key)) |count| {
            try flags.put(key, count + 1);
        } else {
            try flags.put(key, 1);
        }
    }

    pub fn parseArgs(allocator: std.mem.Allocator, args: [][]const u8, command: *Command) !ParsedArgs {
        var positionals = std.ArrayList(Pair(Command.Positional, []const u8)).init(allocator);
        var flags = StructArrayHashMap(ShortOrLong, Pair(Command.Flag, usize)).init(allocator);
        var options = StructArrayHashMap(ShortOrLong, Pair(Command.Option, []const u8)).init(allocator);
        var additional_flags = StructArrayHashMap(ShortOrLong, usize).init(allocator);
        var additional_options = StructArrayHashMap(ShortOrLong, []const u8).init(allocator);
        var additional_positionals = std.ArrayList([]const u8).init(allocator);
        var raw_args = std.ArrayList([]const u8).init(allocator);

        var current_option: ?Command.Option = null;
        var current_positional_index: usize = 0;
        for (args) |arg| {
            try raw_args.append(arg);
            //* If its a long option/flag like "--foo"
            if (std.mem.startsWith(u8, arg, "--")) {
                //* if contains '=' then it's an option
                const indexOfEq = std.mem.indexOf(u8, arg, "=");
                if (indexOfEq) |index| {
                    const key = arg[2..index];
                    const value = arg[index + 1 ..];
                    if (optionForKey(key, command)) |option| {
                        if (option.name) |name| try options.put(.{ .short = name }, .{ .t1 = option, .t2 = value });
                        try options.put(.{ .long = key }, .{ .t1 = option, .t2 = value });
                    } else {
                        try additional_options.put(.{ .long = key }, value);
                    }
                } else
                //* if it doesn't contain '=' then it's a flag
                {
                    // if it's a single character flag like "--f".
                    // in this case we must check if it is a flag or an option
                    // if it's an option, then the next argument is the value
                    const key = arg[2..];
                    if (optionForKey(key, command)) |option| {
                        current_option = option;
                    } else if (flagForKey(key, command)) |flag| {
                        if (flag.name) |name| try flags.put(.{ .short = name }, .{ .t1 = flag, .t2 = 1 });
                        try flags.put(.{ .long = key }, .{ .t1 = flag, .t2 = 1 });
                    } else {
                        try addOrIncrementAddiFlag(&additional_flags, .{ .long = key });
                    }
                }
            }
            //* If its a short option/flag like "-f"
            else if (std.mem.startsWith(u8, arg, "-")) {
                // if contains '=' then it's an option
                const indexOfEq = std.mem.indexOf(u8, arg, "=");
                // only if it's a single character flag with an equals sign like so:
                // -f=bar
                if (indexOfEq) |index| {
                    if (index == 2) {
                        const key = arg[1..2];
                        const value = arg[3..];
                        if (optionForKey(key, command)) |option| {
                            try options.put(.{ .short = key[0] }, .{ .t1 = option, .t2 = value });
                            if (option.long_name) |name| try options.put(.{ .long = name }, .{ .t1 = option, .t2 = value });
                        } else {
                            try additional_options.put(.{ .short = arg[1] }, value);
                        }
                    } else {
                        // ignore it
                    }
                }
                // if there are multiple flags like so: -abc
                else if (arg.len > 2) {
                    var i: usize = 1;
                    while (i < arg.len) : (i += 1) {
                        const key = arg[i .. i + 1];
                        if (flagForKey(key, command)) |flag| {
                            try flags.put(.{ .short = arg[i] }, .{ .t1 = flag, .t2 = 1 });
                            if (flag.long_name) |name| try flags.put(.{ .long = name }, .{ .t1 = flag, .t2 = 1 });
                        } else {
                            try addOrIncrementAddiFlag(&additional_flags, .{ .short = arg[i] });
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
                        try flags.put(.{ .short = arg[1] }, .{ .t1 = flag, .t2 = 1 });
                        if (flag.long_name) |name| try flags.put(.{ .long = name }, .{ .t1 = flag, .t2 = 1 });
                    } else {
                        try addOrIncrementAddiFlag(&additional_flags, .{ .short = arg[1] });
                    }
                }
            }
            //* If it doesn't start with '-' then it's a positional.
            else {
                if (current_option) |option| {
                    if (option.long_name) |name| try options.put(.{ .long = name }, .{ .t1 = option, .t2 = arg });
                    if (option.name) |name| try options.put(.{ .short = name }, .{ .t1 = option, .t2 = arg });
                    current_option = null;
                } else if (current_positional_index < command.positionals.len) {
                    const positional = command.positionals[current_positional_index];
                    try positionals.append(.{ .t1 = positional, .t2 = arg });
                    current_positional_index += 1;
                } else {
                    try additional_positionals.append(arg);
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
            if (flag.long_name != null and self.flags.contains(.{ .long = flag.long_name.? })) continue;
            if (flag.name != null and self.flags.contains(.{ .short = flag.name.? })) continue;
            if (flag.optional) continue;
            stderr.print(ansi.style("Missing required flag: " ++ ansi.bold("{s}\n"), .red), .{flag.long_name.?}) catch {};
            std.os.exit(1);
        }
        for (command.options) |option| {
            if (option.long_name != null and self.options.contains(.{ .long = option.long_name.? })) continue;
            if (option.name != null and self.options.contains(.{ .short = option.name.? })) continue;
            if (option.default_value) |default_value| {
                if (option.long_name) |name| try self.options.put(.{ .long = name }, .{ .t1 = option, .t2 = default_value });
                if (option.name) |name| try self.options.put(.{ .short = name }, .{ .t1 = option, .t2 = default_value });
                continue;
            }
            stderr.print(ansi.style("Missing required option: " ++ ansi.bold("{s}\n"), .red), .{(option.long_name orelse &[_]u8{option.name.?})}) catch {};
            std.os.exit(1);
        }
        var hasSeenOptional = false;

        for (command.positionals) |positional, i| {
            if (positional.optional) {
                hasSeenOptional = true;
                continue;
            } else if (hasSeenOptional) {
                stderr.print(ansi.style("Required positional cannot come after optional positional: " ++ ansi.bold("{s}\n"), .red), .{positional.name}) catch {};
                std.os.exit(1);
            }
            if (self.positionals.items.len > i) continue;
            stderr.print(ansi.style("Missing required positional: " ++ ansi.bold("{s}\n"), .red), .{positional.name}) catch {};
            std.os.exit(1);
        }
    }
};

pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    args: std.ArrayList([]const u8),
    root_command: ?Command = null,

    pub fn init(allocator: std.mem.Allocator) ArgParser {
        var args = std.ArrayList([]const u8).init(allocator);
        return .{
            .allocator = allocator,
            .args = args,
        };
    }

    pub fn parseArgv(self: *ArgParser, iter: *std.process.ArgIterator) !void {
        while (iter.next()) |arg| {
            try self.args.append(arg);
        }
    }

    pub fn parse(self: *ArgParser, args: []const []const u8) !void {
        try self.args.appendSlice(args);
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
            .parent = null,
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
            for (self.command.positionals) |positional, i| {
                if (std.mem.eql(u8, positional.name, name)) {
                    // if out of bounds, return null
                    if (self.args.positionals.items.len <= i) return null;
                    return self.args.positionals.items[i].t2;
                }
            }
            return null;
        }

        pub fn getOption(self: RunContext, name: []const u8) ?[]const u8 {
            if (self.args.options.get(if (name.len == 1) .{ .short = name[0] } else .{ .long = name })) |value| {
                return value.t2;
            }
            return null;
        }

        pub fn hasFlag(self: RunContext, name: []const u8) bool {
            return self.args.flags.contains(if (name.len == 1) .{ .short = name[0] } else .{ .long = name });
        }
    };

    pub fn run(self: *ArgParser) !void {
        var command = &self.root_command.?;
        var depth: usize = 0;
        for (self.args.items[1..]) |command_name| {
            if (std.mem.startsWith(u8, command_name, "-")) {
                break;
            }
            if (builtin.mode == .Debug) {
                std.debug.print("Commands at depth {d} of {s}:\n", .{ depth, command.name });
                for (command.commands.items) |c| {
                    std.debug.print("  {s}", .{c.name});
                }
                std.debug.print("\n", .{});
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
            if (parsed_args.additional_flags.contains(.{ .short = 'h' }) or
                parsed_args.additional_flags.contains(.{ .long = "help" }))
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
        std.log.debug("Finished running command: {s}", .{command.name});
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
    hidden: bool = false,

    pub const Completion = struct {
        name: []const u8,
        description: ?[]const u8 = null,
    };

    pub const CompletionArrayList = std.ArrayList(Completion);

    pub const CompletionContext = struct {
        allocator: std.mem.Allocator,
    };

    pub const PositionalCompleter = *const fn (ctx: CompletionContext) anyerror!CompletionArrayList;
    pub const CreateCommandOptions = struct {
        name: []const u8,
        description: []const u8,
        flags: []const Flag = &[_]Flag{},
        options: []const Option = &[_]Option{},
        positionals: []const Positional = &[_]Positional{},
        add_help: bool = true,
        handler: ?*const fn (context: ArgParser.RunContext) anyerror!void,
        hidden: bool = false,
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
            .hidden = command.hidden,
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

    pub const HelpOtions = struct {
        show_flags: bool = true,
        show_options: bool = true,
        show_usage: bool = true,
        show_commands: bool = true,
    };

    pub fn printHelp(self: Command, writer: anytype) !void {
        try self.printHelpWithOptions(writer, .{});
    }

    pub fn printHelpWithOptions(self: Command, writer: anytype, options: HelpOtions) !void {
        var tree = std.ArrayList([]const u8).init(self.allocator);
        defer tree.deinit();
        var command = &self;
        while (command.parent) |parent| {
            try tree.append(parent.name);
            command = parent;
        }
        try writer.print("{s}\n\n", .{self.description});
        if (options.show_usage) {
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
        }

        if (options.show_commands and self.commands.items.len > 0) {
            try writer.print("Commands:\n", .{});
            var max_len: usize = 0;
            for (self.commands.items) |c| {
                if (c.hidden) continue;
                if (c.name.len > max_len) {
                    max_len = c.name.len;
                }
            }
            const buf = try self.allocator.alloc(u8, max_len);
            defer self.allocator.free(buf);
            std.mem.set(u8, buf, ' ');
            for (self.commands.items) |c| {
                if (c.hidden) continue;
                const spaces = buf[0 .. max_len - c.name.len];
                try writer.print("  {s}{s}    {s}\n", .{ c.name, spaces, c.description });
            }
        }

        if (options.show_flags and self.flags.len > 0) {
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

        if (options.show_options and self.options.len > 0) {
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

    pub const Flag = struct {
        name: ?u8,
        long_name: ?[]const u8,
        optional: bool = true,
        description: []const u8 = "",

        pub fn hash(self: Flag) u32 {
            var h: u32 = 0;
            if (self.name) |name| {
                h ^= @bitCast(u32, name);
            }
            if (self.long_name) |long_name| {
                for (long_name) |c| {
                    h ^= @bitCast(u32, c);
                }
            }
            return h;
        }
    };

    pub const Option = struct {
        name: ?u8 = null,
        long_name: ?[]const u8 = null,
        default_value: ?[]const u8 = null,
        description: []const u8 = "",
        value_name: []const u8 = "value",

        pub fn hash(self: Option) u32 {
            var h: u32 = 0;
            if (self.name) |name| {
                h ^= @bitCast(u32, name);
            }
            if (self.long_name) |long_name| {
                for (long_name) |c| {
                    h ^= @bitCast(u32, c);
                }
            }
            return h;
        }
    };

    pub const Positional = struct {
        name: []const u8,
        description: []const u8 = "",
        optional: bool = false,
        completer: ?PositionalCompleter = null,
    };
};

pub const HelpCommandCreateOptions = struct {
    name: []const u8 = "help",
    description: []const u8 = "Show help",
};

pub fn help_command(opt: HelpCommandCreateOptions) Command.CreateCommandOptions {
    return .{
        .name = opt.name,
        .description = opt.description,
        .handler = &help_cmd_impl,
    };
}

fn help_cmd_impl(ctx: ArgParser.RunContext) !void {
    std.log.debug("help command called", .{});
    var command = ctx.command;
    while (command.parent) |p| {
        command = p;
    }
    for (ctx.args.raw_args.items[0..]) |command_name| {
        std.log.debug("command name: {s}", .{command_name});
        if (std.mem.startsWith(u8, command_name, "-")) {
            break;
        }
        for (command.commands.items) |c| {
            if (std.mem.eql(u8, c.name, command_name)) {
                command = c;
            }
        }
    }
    try command.printHelp(std.io.getStdOut().writer());
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
        "-q",
        "i_love_silence",
    };
    var parser = ArgParser.init(allocator);
    defer parser.deinit();
    try parser.parse(argv);

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
                .description = "long flag description",
            },
            Command.Flag{
                .name = 's',
                .long_name = null,
                .description = "short flag description",
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
                .value_name = "potion_value",
                .description = "potions are good",
            },
            Command.Option{
                .name = 'q',
                .long_name = "quiet",
                .value_name = "quiet_value",
                .description = "quiet description",
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

fn handler(ctx: ArgParser.RunContext) !void {
    // for (ctx.args.options.keys()) |k| {
    //     std.debug.print("option: {s} = {s}\n", .{ if (k == .short) &[_]u8{k.short} else k.long, (ctx.args.options.get(k) orelse unreachable).t2 });
    // }
    // for (ctx.args.flags.keys()) |k| {
    //     const key = if (k == .short) &[_]u8{k.short} else k.long;
    //     var alloc = std.testing.allocator;
    //     const key_str = try std.fmt.allocPrint(alloc, "{s}", .{key});
    //     defer alloc.free(key_str);
    //     try testing.expectEqualStrings(key_str, key);
    //     try testing.expectEqual(key_str.len, key.len);
    //     const key_hash = blk: {
    //         var hasher = std.hash.Wyhash.init(0);
    //         std.hash.autoHashStrat(&hasher, key, .DeepRecursive);
    //         break :blk @truncate(u32, hasher.final());
    //     };
    //     const key_str_hash = blk: {
    //         var hasher = std.hash.Wyhash.init(0);
    //         std.hash.autoHashStrat(&hasher, key_str, .DeepRecursive);
    //         break :blk @truncate(u32, hasher.final());
    //     };
    //     try testing.expectEqual(key_hash, key_str_hash);
    //     const k_hash = blk: {
    //         var hasher = std.hash.Wyhash.init(0);
    //         std.hash.autoHashStrat(&hasher, k, .DeepRecursive);
    //         break :blk @truncate(u32, hasher.final());
    //     };
    //     const k2_hash = blk: {
    //         var hasher = std.hash.Wyhash.init(0);
    //         const k2: ParsedArgs.ShortOrLong = if (key_str.len == 1) .{ .short = key_str[0] } else .{ .long = key_str };
    //         std.hash.autoHashStrat(&hasher, k2, .DeepRecursive);
    //         break :blk @truncate(u32, hasher.final());
    //     };
    //     try testing.expectEqual(k_hash, k2_hash);
    //     std.debug.print("flag: {s} ({}, {})\n", .{ key, ctx.hasFlag(key), ctx.hasFlag(key_str) });
    // }

    try testing.expectEqualStrings(ctx.getPositional("positional").?, "positional_value");
    try testing.expect(ctx.hasFlag("long"));
    try testing.expect(ctx.hasFlag("s"));
    try testing.expectEqualStrings(ctx.getOption("o").?, "default_option_value");
    try testing.expectEqualStrings(ctx.getOption("option").?, "default_option_value");
    try testing.expectEqualStrings(ctx.getOption("p").?, "short");
    try testing.expectEqualStrings(ctx.getOption("potion").?, "short");
    try testing.expectEqualStrings(ctx.getOption("q").?, "i_love_silence");
    try testing.expectEqualStrings(ctx.getOption("quiet").?, "i_love_silence");
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
    var parser = ArgParser.init(allocator);
    defer parser.deinit();
    try parser.parse(argv);

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

fn AutoStructContext(comptime K: type) type {
    return struct {
        pub const hash = getDeepHashFn(K, @This());
        pub const eql = getHashEqlFn(K, @This());
    };
}

fn getDeepHashFn(comptime K: type, comptime Context: type) (fn (Context, K) u32) {
    return struct {
        fn hash(ctx: Context, key: K) u32 {
            _ = ctx;
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHashStrat(&hasher, key, .DeepRecursive);
            return @truncate(u32, hasher.final());
        }
    }.hash;
}

fn getHashEqlFn(comptime K: type, comptime Context: type) (fn (Context, K, K, usize) bool) {
    return struct {
        fn eql(ctx: Context, a: K, b: K, b_index: usize) bool {
            _ = b_index;
            return Context.hash(ctx, a) == Context.hash(ctx, b);
        }
    }.eql;
}

fn StructArrayHashMap(comptime K: type, comptime V: type) type {
    return std.ArrayHashMap(K, V, AutoStructContext(K), true);
}

const TestUnion = union(enum) {
    a: u8,
    b: u16,
    c: u32,
};

test "ArrayHashMap" {
    var alloc = std.testing.allocator;
    var map = StructArrayHashMap(TestUnion, u8).init(alloc);
    defer map.deinit();

    const a = TestUnion{ .a = 1 };
    const b = TestUnion{ .b = 2 };
    const c = TestUnion{ .c = 3 };

    try map.put(a, 1);
    try std.testing.expectEqual(map.get(a), 1);
    try map.put(b, 2);
    try std.testing.expectEqual(map.get(a), 1);
    try std.testing.expectEqual(map.get(b), 2);
    try map.put(c, 3);
    try std.testing.expectEqual(map.get(a), 1);
    try std.testing.expectEqual(map.get(b), 2);
    try std.testing.expectEqual(map.get(c), 3);
    try map.put(a, 4);
    try std.testing.expectEqual(map.get(a), 4);
}
