const std = @import("std");
const arg_parser = @import("arg_parser.zig");
const ArgParser = arg_parser.ArgParser;
const ParsedArgs = arg_parser.ParsedArgs;
const Command = arg_parser.Command;
const path = std.fs.path;
const build_options = @import("zvm_build_options");
const builtin = @import("builtin");
const ansi = @import("ansi");
const createParser = @import("parser.zig").createParser;

/// Generate the completion script for the shell.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();
    var parser = try createParser(allocator);
    defer parser.deinit();

    // print whole environment
    // var env = try std.process.getEnvMap(allocator);
    // var iter = env.hash_map.keyIterator();
    // while (iter.next()) |k| {
    //     try stderr.print("{s}={s}\n", .{ k.*, env.hash_map.get(k.*) orelse unreachable });
    // }

    var compWords = try std.process.getEnvVarOwned(allocator, "COMP_LINE");
    defer allocator.free(compWords);

    std.log.debug("completing for \"{s}\"", .{compWords});
    var split = std.mem.split(u8, compWords, " ");

    var command = &parser.root_command.?;
    var current = split.next() orelse unreachable;
    var resolved_depth: usize = 1; // 1 because the first word is the command name
    var total_depth: usize = 0;
    main_loop: while (split.next()) |command_name| {
        current = command_name;
        total_depth += 1;
        if (std.mem.startsWith(u8, command_name, "-")) {
            break;
        }
        // std.log.debug("checking {s} for child {s}", .{ command.name, command_name });
        for (command.commands.items) |c| {
            if (c.hidden) continue;
            if (std.mem.eql(u8, c.name, command_name)) {
                // std.log.debug("found child {s}", .{ c.name });
                command = c;
                resolved_depth += 1;
                continue :main_loop;
            }
        }
        // std.log.debug("no child found, stopping at {s}", .{ command.name });
        break;
    }
    while (split.next()) |command_name| {
        current = command_name;
        total_depth += 1;
    }

    std.log.debug("command=\"{s}\", current=\"{s}\", resolved_depth={d}, total_depth={d}", .{ command.name, current, resolved_depth, total_depth });
    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, current, "-")) {
        for (command.flags) |o| {
            if (o.name != null) {
                std.log.debug("flag {c} is valid", .{o.name.?});
                try stdout.print("-{c} ", .{o.name.?});
            }
        }
        for (command.options) |o| {
            if (o.name != null) {
                std.log.debug("option {c} is valid", .{o.name.?});
                try stdout.print("-{c}= ", .{o.name.?});
            }
        }
    } else if (std.mem.startsWith(u8, current, "--")) {
        for (command.flags) |o| {
            if (o.long_name != null and std.mem.startsWith(u8, o.long_name.?, current[2..])) {
                try stdout.print("--{s} ", .{o.long_name.?});
            }
        }
        for (command.options) |o| {
            if (o.long_name != null and std.mem.startsWith(u8, o.long_name.?, current[2..])) {
                try stdout.print("--{s}= ", .{o.long_name.?});
            }
        }
    } else {
        if (command.commands.items.len > 0) {
            for (command.commands.items) |c| {
                if (c.hidden) continue;
                if (std.mem.startsWith(u8, c.name, current)) {
                    try stdout.print("{s} ", .{ c.name});
                }
            }
        } else if (total_depth >= resolved_depth and command.positionals.len > total_depth - resolved_depth) {
            const pos = command.positionals[total_depth - resolved_depth];
            if (pos.completer) |completer| {
                std.log.debug("completing {s} with \"{s}\"", .{ pos.name, current });
                completer(current) catch |err| {
                    std.log.debug("error while completing: {any}", .{err});
                    return;
                };
            } else {
                std.log.debug("no completer for {s}", .{pos.name});
            }
        }
    }
}
