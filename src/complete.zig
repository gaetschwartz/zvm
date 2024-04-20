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

pub const WordsIterator = struct {
    words: []const []const u8,
    index: usize = 0,

    pub fn init(words: []const []const u8) WordsIterator {
        return WordsIterator{
            .words = words,
        };
    }

    pub fn next(self: *WordsIterator) ?[]const u8 {
        if (self.index >= self.words.len) return null;
        const word = self.words[self.index];
        self.index += 1;
        return word;
    }

    pub fn rest(self: *WordsIterator) []const []const u8 {
        return self.words[self.index..];
    }

    pub fn peek(self: *WordsIterator) ?[]const u8 {
        if (self.index >= self.words.len) return null;
        return self.words[self.index];
    }

    pub fn skip(self: *WordsIterator) void {
        self.index += 1;
    }

    pub fn reset(self: *WordsIterator) void {
        self.index = 0;
    }
};

/// Generate the completion script for the shell.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();
    var parser = try createParser(allocator);
    defer parser.deinit();

    // var compWords = try std.process.getEnvVarOwned(allocator, "COMP_LINE");
    // defer allocator.free(compWords);
    // var split = std.mem.split(u8, compWords, " ");

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    var arr = std.ArrayList([]const u8).init(allocator);
    defer arr.deinit();
    while (args.next()) |arg| {
        try arr.append(arg);
    }
    const compWords = try arr.toOwnedSlice();
    var split = WordsIterator.init(compWords);
    std.log.debug("completing for \"{s}\"", .{compWords});

    var command = &parser.root_command.?;
    // skip the first word, it's the command name
    _ = split.next() orelse unreachable;
    // skip the second word, it's "complete"
    const second = split.next() orelse unreachable;
    std.debug.assert(std.mem.eql(u8, second, "complete"));
    var current: []const u8 = split.next() orelse unreachable;
    var resolved_depth: usize = 0; // 1 because the first word is the command name
    var total_depth: usize = 0;
    main_loop: while (split.next()) |command_name| {
        current = command_name;
        total_depth += 1;
        if (std.mem.startsWith(u8, command_name, "-")) {
            break;
        }
        std.log.debug("checking {s} for child {s}", .{ command.name, command_name });
        for (command.commands.items) |c| {
            if (c.hidden) continue;
            if (std.mem.eql(u8, c.name, command_name)) {
                std.log.debug("found child {s}", .{c.name});
                command = c;
                resolved_depth += 1;
                continue :main_loop;
            }
        }
        std.log.debug("no child found, stopping at {s}", .{command.name});
        break;
    }
    while (split.next()) |command_name| {
        current = command_name;
        total_depth += 1;
    }

    std.log.debug("command=\"{s}\", current=\"{s}\", resolved_depth={d}, total_depth={d}", .{ command.name, current, resolved_depth, total_depth });
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

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
                    try stdout.print("{s} ", .{c.name});
                }
            }
        } else if (total_depth >= resolved_depth and command.positionals.len >= total_depth - resolved_depth) {
            const pos = command.positionals[total_depth - resolved_depth - 1];
            if (pos.completer) |completer| {
                std.log.debug("completing {s} with \"{s}\"", .{ pos.name, current });
                var completions: Command.CompletionArrayList = completer(.{
                    .allocator = allocator,
                }) catch |err| {
                    std.log.debug("error while completing: {any}", .{err});
                    return;
                };
                defer completions.deinit();
                for (try completions.toOwnedSlice()) |completion| {
                    if (std.mem.startsWith(u8, completion.name, current)) {
                        if (completion.description) |desc| {
                            try stdout.print("'{s}:{s}' ", .{ completion.name, desc });
                            try stderr.print("'{s}:{s}' ", .{ completion.name, desc });
                        } else {
                            try stderr.print("'{s}' ", .{completion.name});
                            try stdout.print("'{s}' ", .{completion.name});
                        }
                    }
                }
            } else {
                std.log.debug("no completer for {s}", .{pos.name});
            }
        }
    }
}
