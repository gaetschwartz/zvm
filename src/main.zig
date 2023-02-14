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
const destroy_cmd = @import("commands/destroy.zig").destroy_cmd;
const config_cmd = @import("commands/config.zig").config_cmd;
const zvmDir = @import("utils.zig").zvmDir;
const path = std.fs.path;
const root = @import("root");
const build_options = @import("zvm_build_options");
const builtin = @import("builtin");
const ansi = @import("ansi");

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
                .long_name = "raw-version",
                .description = "show raw version",
            },
        },
    });

    _ = try parser.addCommand(arg_parser.help_command(.{}));

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
        .name = "destroy",
        .description = "Destroy the current zvm installation",
        .handler = &destroy_cmd,
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
                .optional = true,
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
    const cfg = try parser.addCommand(.{
        .name = "config",
        .description = "Configure zvm.",
        .handler = &config_cmd,
        .flags = &[_]Command.Flag{
            .{
                .name = 'v',
                .long_name = "verbose",
                .description = "show verbose output",
                .optional = true,
            },
        },
    });

    _ = try cfg.addCommand(.{
        .name = "set",
        .description = "Set a config value",
        .handler = &config_cmd,
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
                .name = "key",
                .description = "the config key to set",
            },
            .{
                .name = "value",
                .description = "the value to set",
                .optional = true,
            },
        },
    });

    // clear config
    _ = try cfg.addCommand(.{
        .name = "clear",
        .description = "Reset the config to default",
        .handler = &config_cmd,
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

    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) != 0) {
            std.log.debug("Set console output code page to UTF-8", .{});
        } else {
            std.log.debug("Failed to set console output code page to UTF-8", .{});
        }
    }

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
