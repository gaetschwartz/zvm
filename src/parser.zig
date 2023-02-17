const std = @import("std");
const arg_parser = @import("arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const install_cmd = @import("commands/install.zig").install_cmd;
const IndexCompleter = @import("commands/install.zig").IndexCompleter;
const list_cmd = @import("commands/list.zig").list_cmd;
const spawn_cmd = @import("commands/spawn.zig").spawn_cmd;
const remove_cmd = @import("commands/remove.zig").remove_cmd;
const use_cmd = @import("commands/use.zig").use_cmd;
const complete_versions = @import("commands/use.zig").version_complete;
const zig_cmd = @import("commands/zig.zig").zig_cmd;
const releases_cmd = @import("commands/releases.zig").releases_cmd;
const destroy_cmd = @import("commands/destroy.zig").destroy_cmd;
const config_cmd = @import("commands/config.zig").config_cmd;
const gen_completions_cmd = @import("commands/completions.zig").gen_completions_cmd;
const complete_config_keys = @import("commands/config.zig").complete_config_keys;
const zvm_cmd = @import("main.zig").zvm_cmd;
const zvmDir = @import("utils.zig").zvmDir;
const path = std.fs.path;
const root = @import("root");
const build_options = @import("zvm_build_options");
const builtin = @import("builtin");
const ansi = @import("ansi");
const complete = @import("complete.zig").main;

// Needs to be inline so that it doesn't release the created commands
pub inline fn createParser(allocator: std.mem.Allocator) !ArgParser {
    var parser = ArgParser.init(allocator);

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
                .completer = &IndexCompleter(true).complete,
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
                .completer = &IndexCompleter(false).complete,
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
        .name = "complete",
        .description = "Complete a command",
        .handler = &complete_cmd,
        .hidden = true,
    });
    _ = try parser.addCommand(.{
        .name = "completions",
        .description = "Generate shell completions",
        .handler = &gen_completions_cmd,
        .hidden = true,
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
                .completer = &complete_versions,
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
                .completer = &complete_versions,
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
                .completer = &complete_versions,
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
                .completer = &complete_config_keys,
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
    return parser;
}

pub fn complete_cmd(ctx: ArgParser.RunContext) !void {
    std.log.debug("complete_cmd", .{});
    _ = ctx;
    try complete();
}
