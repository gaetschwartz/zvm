const std = @import("std");
const builtin = @import("builtin");

const zvm_version = std.builtin.Version.parse("0.2.12") catch unreachable;

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0-dev.1817+f6c934677") catch return; // package manager hashes made consistent on windows
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const options = b.addOptions();
    if (gitCommit(allocator)) |commit| {
        options.addOption(?[]const u8, "git_commit", commit[0..]);
    } else {
        options.addOption(?[]const u8, "git_commit", null);
    }
    const commit_count = commitCount(allocator);
    options.addOption(?u32, "commit_count", commit_count);

    const branch = gitBranch(allocator);
    options.addOption(?[]const u8, "git_branch", branch);
    defer if (branch) |br| {
        allocator.free(br);
    };

    const versionString = std.fmt.comptimePrint("{}", .{zvm_version});
    options.addOption([]const u8, "version", versionString);

    const isCi = std.process.getEnvVarOwned(allocator, "CI") catch "false";
    defer if (std.process.hasEnvVarConstant("CI")) allocator.free(isCi);

    options.addOption([]const u8, "is_ci", isCi);
    options.addOption(?[DATE_SIZE]u8, "build_date", date(allocator) orelse null);

    const known_folders_module = b.dependency("known_folders", .{}).module("known-folders");

    const ansi_module = b.createModule(.{
        .source_file = .{ .path = "src/ansi.zig" },
    });

    const zvm = b.addExecutable(.{
        .name = "zvm",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    zvm.addModule("known-folders", known_folders_module);
    zvm.addModule("ansi", ansi_module);
    zvm.addOptions("zvm_build_options", options);
    zvm.install();

    const run_cmd = b.addRunArtifact(zvm);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const arg_parser_test = registerTest(b, test_step, .{
        .root_source_file = .{ .path = "src/arg_parser.zig" },
        .target = target,
        .optimize = optimize,
    });
    arg_parser_test.addModule("ansi", ansi_module);

    _ = registerTest(b, test_step, .{
        .root_source_file = .{ .path = "src/index.zig" },
        .target = target,
        .optimize = optimize,
    });
    _ = registerTest(b, test_step, .{
        .root_source_file = .{ .path = "src/ansi.zig" },
        .target = target,
        .optimize = optimize,
    });
    _ = registerTest(b, test_step, .{
        .root_source_file = .{ .path = "src/utils.zig" },
        .target = target,
        .optimize = optimize,
    });
}

inline fn registerTest(b: *std.Build, step: *std.Build.Step, options: std.Build.TestOptions) *std.Build.CompileStep {
    const exe_tests = b.addTest(options);
    step.dependOn(&exe_tests.step);
    return exe_tests;
}

fn gitCommit(allocator: std.mem.Allocator) ?[40]u8 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--verify", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term != .Exited or exec_result.term.Exited != 0) return null;

    // +1 for trailing newline.
    if (exec_result.stdout.len != 40 + 1) return null;
    if (exec_result.stderr.len != 0) return null;

    var output: [40]u8 = undefined;
    std.mem.copy(u8, &output, exec_result.stdout[0..40]);
    return output;
}

fn commitCount(allocator: std.mem.Allocator) ?u32 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-list", "--count", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term != .Exited or exec_result.term.Exited != 0) return null;

    var number: u32 = 0;
    for (exec_result.stdout) |c| {
        switch (c) {
            '\n' => break,
            '0'...'9' => number = number * 10 + (c - '0'),
            else => return null,
        }
    }
    return number;
}

fn gitBranch(allocator: std.mem.Allocator) ?[]const u8 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    if (exec_result.stdout.len == 0) return null;
    if (exec_result.stderr.len != 0) return null;

    const idx = std.mem.indexOf(u8, exec_result.stdout[0..], "\n") orelse return null;
    const allocated = allocator.alloc(u8, idx) catch return null;
    std.mem.copy(u8, allocated, exec_result.stdout[0..allocated.len]);
    return allocated;
}

const DATE_SIZE = 23;

fn date(allocator: std.mem.Allocator) ?[DATE_SIZE]u8 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "date", "+%Y-%m-%d %H:%M:%S %Z" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    var output: [DATE_SIZE]u8 = undefined;
    std.mem.copy(u8, &output, exec_result.stdout[0..DATE_SIZE]);
    return output;
}
