const std = @import("std");
const arg_parser = @import("arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const install_cmd = @import("commands/install.zig").install_cmd;
const list_cmd = @import("commands/list.zig").list_cmd;
const spawn_cmd = @import("commands/spawn.zig").spawn_cmd;
const remove_cmd = @import("commands/remove.zig").remove_cmd;
const use_cmd = @import("commands/use.zig").use_cmd;
const zig_cmd = @import("commands/zig.zig").zig_cmd;
const releases_cmd = @import("commands/releases.zig").releases_cmd;
const zvmDir = @import("utils.zig").zvmDir;
const path = std.fs.path;
const root = @import("root");
const build_options = @import("zvm_build_options");
const builtin = @import("builtin");
const ansi = @import("ansi.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    // parse args
    var iter = try std.process.argsWithAllocator(allocator);
    var parser = try ArgParser.init(allocator, &iter);
    defer parser.deinit();

    parser.setRootCommand(.{
        .name = "zvm",
        .description = "A version manager for zig.",
        .handler = &zvm_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = null,
                .long_name = "version",
                .description = "show version",
            },
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
            },
            .{
                .name = null,
                .long_name = "raw",
                .description = "show raw version",
            },
        },
    });

    _ = try parser.addCommand(.{
        .name = "install",
        .description = "Install a new version",
        .handler = &install_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
            },
            .{
                .name = 'f',
                //.long_name = "force",
                .long_name = null,
                .description = "force install",
            },
        },
        .positionals = &[_]Command.Positional{
            .{
                .name = "version",
                .description = "the target version to install",
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "upgrade",
        .description = "Upgrade a currently installed channel",
        .handler = &install_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
            },
            .{
                .name = 'f',
                .long_name = "force",
                .description = "force upgrade",
            },
        },
        .positionals = &[_]Command.Positional{
            .{
                .name = "version",
                .description = "the target channel to upgrade",
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "list",
        .description = "List installed versions",
        .handler = &list_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "spawn",
        .description = "Run a command with a specific version of zig",
        .handler = &spawn_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
        .positionals = &[_]Command.Positional{
            .{
                .name = "target",
                .description = "the target version to run",
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "use",
        .description = "Set to use a specific version of zig",
        .handler = &use_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
            .{
                .name = null,
                .long_name = "global",
                .description = "set the global version",
                .optional = true,
            },
            // force
            .{
                .name = 'f',
                .long_name = "force",
                .description = "force use",
                .optional = true,
            },
        },
        .positionals = &[_]Command.Positional{
            .{
                .name = "target",
                .description = "the target version to use",
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "zig",
        .description = "Run the currently active version of zig",
        .handler = &zig_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "releases",
        .description = "List available releases",
        .handler = &releases_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
            // raw
            .{
                .name = 'r',
                .long_name = "raw",
                .description = "show raw output",
                .optional = true,
            },
            // reverse
            .{
                .name = 'R',
                .long_name = "reverse",
                .description = "show releases in reverse order",
                .optional = true,
            },
        },
    });
    _ = try parser.addCommand(.{
        .name = "remove",
        .description = "Remove a version",
        .handler = &remove_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
        .positionals = &[_]Command.Positional{
            .{
                .name = "target",
                .description = "the target version to remove",
            },
        },
    });
    var cache_command = try parser.addCommand(.{
        .name = "cache",
        .description = "Manage the zvm cache",
        .handler = null,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });
    _ = try cache_command.addCommand(.{
        .name = "clear",
        .description = "Clear the zvm cache",
        .handler = &@import("commands/cache.zig").cache_clear_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });
    _ = try cache_command.addCommand(.{
        .name = "size",
        .description = "Show the size of the zvm cache",
        .handler = &@import("commands/cache.zig").cache_size_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });

    try parser.run();
}

pub fn zvm_cmd(ctx: ArgParser.RunContext) !void {
    const version = ctx.hasFlag("version");
    const verbose = ctx.hasFlag("verbose");
    const raw = ctx.hasFlag("raw");

    if (version) {
        const stdout = std.io.getStdOut().writer();
        if (raw) {
            try stdout.print("{s}\n", .{build_options.version});
            return;
        }
        const start = comptime "  " ++ ansi.fade("•") ++ ansi.BLUE ++ ansi.BOLD;
        const end = comptime ansi.RESET ++ "\n";
        try stdout.print(start ++ " zvm          " ++ ansi.RESET_BOLD ++ (build_options.version) ++ end, .{});
        try stdout.print(start ++ " commit_hash  " ++ ansi.RESET_BOLD ++ (build_options.git_commit orelse "unknown") ++ end, .{});
        try stdout.print(start ++ " build_date   " ++ ansi.RESET_BOLD ++ (build_options.build_date orelse "unknown") ++ end, .{});
        try stdout.print(start ++ " zig          " ++ ansi.RESET_BOLD ++ std.fmt.comptimePrint("{}", .{builtin.zig_version}) ++ end, .{});
        if (verbose) {
            try stdout.print(start ++ " is_ci        " ++ ansi.RESET_BOLD ++ (build_options.is_ci) ++ end, .{});
        }
        return;
    }
    try ctx.command.printHelp(std.io.getStdOut().writer());
}
