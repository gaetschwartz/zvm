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
    std.log.debug("Installing completions...", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();
    var parser = try createParser(allocator);
    _ = parser;

    const completion_script: std.fs.File = try std.fs.cwd().createFile("zig-out/zvm_completion.zsh", .{});
    var writer = completion_script.writer();

    // calls 'zvm completions' to get the completions for the current command
    _ = try writer.write(
        \\#!/usr/bin/env zsh
        \\
        \\ _zvm_complete() {
        \\     local -a completions
        \\     local -a completions_with_descriptions
        \\     local -a response
        \\     read -Ac response < <(zvm completions ${(qqq)LBUFFER}})
        \\     for key descr in ${(kv)response}; do
        \\         if [[ -z "$descr" ]]; then
        \\             completions+=("$key")
        \\         else
        \\             completions_with_descriptions+=("$key":"$descr")
        \\         fi
        \\     done
        \\     if [[ ${#completions_with_descriptions} -gt 0 ]]; then
        \\         _describe -V unsorted completions_with_descriptions -U
        \\     else
        \\         _describe -V unsorted completions -U
        \\     fi
        \\ }
        \\
        \\ complete -F _zvm_complete zvm
        ,
    );
    // 'zvm completions' now needs to print the completions for the current command
    // to print with descriptions, use the format 'key:descr'
}
