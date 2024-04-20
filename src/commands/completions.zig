const std = @import("std");
const arg_parser = @import("../arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const ansi = @import("ansi");
const config = @import("config.zig");

pub fn gen_completions_cmd(ctx: ArgParser.RunContext) !void {
    const shell = ctx.getOption("shell").?;
    if (std.mem.eql(u8, shell, "zsh")) {
        try zvm_completions(ctx);
    } else if (std.mem.eql(u8, shell, "powershell")) {
        try powershell_completions(ctx);
    } else {
        std.debug.panic("Shell not supported: {s}", .{shell});
    }
}

fn zvm_completions(ctx: ArgParser.RunContext) !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();

    defer arena.deinit();
    var root = ctx.command;
    while (root.parent) |parent| {
        root = parent;
    }
    std.log.debug("root: {s}", .{root.name});
    std.debug.assert(root.parent == null);

    // use zvm completions

    _ = try stdout.write(
        \\#compdef _zvm zvm
        \\
        \\
        \\__zvm_debug() {
        \\    local file="~/.zvm/zvm-completions-debug.log"
        \\    if [[ -n ${file} ]]; then
        \\        echo "$*" >> "${file}"
        \\    fi
        \\}
        \\
        ,
    );

    _ = try stdout.write(
        \\
        \\__zvm_list_aliases() {
        \\  local -a aliases
        \\  aliases=()
        \\  echo "${aliases}"
        \\}
        \\
    );
    //? Write the positional completers
    _ = try stdout.write(
        \\
        \\#:-----------------------:#
        \\#  Positional completers  #
        \\#:-----------------------:#
        \\
    );

    try writePositinalCompleters(allocator, root, stdout);

    _ = try stdout.write(
        \\
        \\__zvm_commands() {
        \\  local -a commands
        \\  commands=(
    );
    for (root.commands.items) |c| {
        if (c.hidden) continue;
        try stdout.print("'{s}:{s}' ", .{ c.name, c.description });
    }

    _ = try stdout.write(
        \\  )
        \\  _describe -t commands 'zvm commands' commands
        \\}
        \\
    );

    //? Write the completion functions
    _ = try stdout.write(
        \\
        \\#:----------------------:#
        \\#  Completion functions  #
        \\#:----------------------:#
        \\
    );

    for (root.commands.items) |c| {
        if (c.hidden) continue;
        try recurseCommands(allocator, c, stdout);
    }

    _ = try stdout.write(
        \\
        \\# The main completion function
        \\_zvm() {
        \\  local curcontext="$curcontext" state state_descr line expl
        \\  local tmp ret=1
        \\
        \\  _arguments -C : \
        \\    '(-v)-v[verbose]' \
        \\    '1:command:->command' \
        \\    '*::options:->options' && return 0
        \\
        \\  case "$state" in
        \\    command)
        \\      # set default cache policy
        \\      # zstyle -s ":completion:${curcontext%:*}:*" cache-policy tmp ||
        \\      #   zstyle ":completion:${curcontext%:*}:*" cache-policy __zvm_completion_caching_policy
        \\      # zstyle -s ":completion:${curcontext%:*}:*" use-cache tmp ||
        \\      #   zstyle ":completion:${curcontext%:*}:*" use-cache true
        \\
        \\      __zvm_commands && return 0
        \\      ;;
        \\    options)
        \\      local command_or_alias command
        \\      local -A aliases
        \\
        \\      # expand alias e.g. ls -> list
        \\      command_or_alias="${line[1]}"
        \\      aliases=($(__zvm_list_aliases))
        \\      command="${aliases[$command_or_alias]:-$command_or_alias}"
        \\
        \\      # change context to e.g. zvm-list
        \\      curcontext="${curcontext%:*}-${command}:${curcontext##*:}"
        \\
        \\      # set default cache policy (we repeat this dance because the context
        \\      # service differs from above)
        \\      # zstyle -s ":completion:${curcontext%:*}:*" cache-policy tmp ||
        \\      #   zstyle ":completion:${curcontext%:*}:*" cache-policy __zvm_completion_caching_policy
        \\      # zstyle -s ":completion:${curcontext%:*}:*" use-cache tmp ||
        \\      #   zstyle ":completion:${curcontext%:*}:*" use-cache true
        \\
        \\      # call completion for named command e.g. _zvm_list
        \\      local completion_func="_zvm_${command//-/_}"
        \\      _call_function ret "${completion_func}" && return ret
        \\
        \\      _message "a completion function is not defined for command or alias: ${command_or_alias}"
        \\      return 1
        \\    ;;
        \\  esac
        \\}
        \\
    );

    // _ = try stdout.write(
    //     \\
    //     \\  _zvm "$@"
    //     \\
    // );
}

fn recurseCommands(allocator: std.mem.Allocator, cmd: *Command, stdout: std.fs.File.Writer) !void {
    std.log.debug("Writing completion function for {s}", .{cmd.name});

    //? Print the function name
    var tree = std.ArrayList([]const u8).init(allocator);
    defer tree.deinit();
    var root = cmd;
    // std.log.debug("parent of current: {s}", .{cmd.parent.?.name});
    std.debug.assert(!std.mem.eql(u8, cmd.parent.?.name, "zvm") or cmd.parent.?.parent == null);
    while (root.parent) |parent| {
        //  std.log.debug("parent of current: {s}", .{parent.name});
        try tree.append(parent.name);
        root = parent;
    }

    try stdout.print("# ", .{});
    var i: usize = tree.items.len;
    while (i > 0) : (i -= 1) {
        const name = tree.items[i - 1];
        try stdout.print("{s} ", .{name});
    }
    try stdout.print("{s}\n", .{cmd.name});
    try stdout.print("_", .{});
    i = tree.items.len;
    while (i > 0) : (i -= 1) {
        const name = tree.items[i - 1];
        try stdout.print("{s}_", .{name});
    }
    try stdout.print("{s}() {{\n", .{cmd.name});
    //? end function name

    try stdout.print("  _arguments \\\n", .{});
    for (cmd.flags) |flag| {
        if (flag.long_name) |long_name| {
            try stdout.print("    '--{s}[{s}]' \\\n", .{ long_name, flag.description });
        } else {
            try stdout.print("    '-{c}[{s}]' \\\n", .{ flag.name.?, flag.description });
        }
    }
    for (cmd.options) |option| {
        if (option.long_name) |long_name| {
            try stdout.print("    '--{s}[{s}]' \\\n", .{ long_name, option.description });
        } else {
            try stdout.print("    '-{c}[{s}]' \\\n", .{ option.name.?, option.description });
        }
    }
    // subcommands
    if (cmd.commands.items.len > 0) {
        try stdout.print(
            \\    - subcommand \
            \\    '::subcommand:(
        , .{});
        var first = true;
        for (cmd.commands.items) |c| {
            if (c.hidden) continue;
            if (first) {
                first = false;
                try stdout.print("{s}", .{c.name});
            } else {
                try stdout.print(" {s}", .{c.name});
            }
        }
        try stdout.print(")' \\\n", .{});
    }
    if (cmd.positionals.len > 0) {
        try stdout.print(
            \\    - positional \
            \\    '::positional:__completer_
        , .{});
        // write the rest of the function name
        i = tree.items.len;
        while (i > 0) : (i -= 1) {
            const name = tree.items[i - 1];
            try stdout.print("{s}_", .{name});
        }
        try stdout.print("{s}' \\\n", .{cmd.name});
    }

    try stdout.print("  ;\n", .{});
    try stdout.print("}}\n\n", .{});

    for (cmd.commands.items) |c| {
        if (c.hidden) continue;
        try recurseCommands(allocator, c, stdout);
    }
}

fn writePositinalCompleters(allocator: std.mem.Allocator, cmd: *Command, stdout: std.fs.File.Writer) !void {
    std.log.debug("Writing positional completers for function for {s}", .{cmd.name});

    //? Print the function name
    var tree = std.ArrayList([]const u8).init(allocator);
    defer tree.deinit();
    var root = cmd;
    // std.log.debug("parent of current: {s}", .{cmd.parent.?.name});
    while (root.parent) |parent| {
        //  std.log.debug("parent of current: {s}", .{parent.name});
        try tree.append(parent.name);
        root = parent;
    }

    for (cmd.positionals) |pos| {
        if (pos.completer) |_| {
            try stdout.print("# ", .{});
            var i: usize = tree.items.len;
            while (i > 0) : (i -= 1) {
                const name = tree.items[i - 1];
                try stdout.print("{s} ", .{name});
            }
            try stdout.print("{s} <", .{cmd.name});
            try stdout.print("{s}>\n", .{pos.name});

            try stdout.print("__completer_", .{});
            i = tree.items.len;
            while (i > 0) : (i -= 1) {
                const name = tree.items[i - 1];
                try stdout.print("{s}_", .{name});
            }
            try stdout.print("{s}() {{\n", .{cmd.name});
            try stdout.print("  local -a completions\n", .{});
            try stdout.print("  string=$(zvm complete ", .{});

            i = tree.items.len;
            while (i > 0) : (i -= 1) {
                const name = tree.items[i - 1];
                try stdout.print("{s} ", .{name});
            }
            try stdout.print("{s} \"\")\n", .{cmd.name});
            _ = try stdout.write("  completions=(\"${(@Q)${(z)string}}\")\n");
            try stdout.print("  _describe '{s}' completions\n", .{pos.name});
            try stdout.print("}}\n", .{});
        }
    }
    //? end function name

    for (cmd.commands.items) |c| {
        if (c.hidden) continue;
        try writePositinalCompleters(allocator, c, stdout);
    }
}

fn powershell_completions(ctx: ArgParser.RunContext) !void {
    _ = ctx;
    const stdout = std.io.getStdOut().writer();

    _ = try stdout.write(@embedFile("../scripts/completions.ps1"));
}
