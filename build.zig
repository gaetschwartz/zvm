const std = @import("std");
const builtin = @import("builtin");

const zvm_version = std.SemanticVersion.parse("0.2.14") catch unreachable;

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0") catch unreachable;
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

    const hash: ?[]const u8 = if (gitCommitHash(allocator)) |h| h[0..] else null;
    options.addOption(?[]const u8, "git_commit_hash", hash);
    options.addOption(?u32, "git_commit_count", gitCommitCount(allocator));

    const branch = gitBranch(allocator);
    options.addOption(?[]const u8, "git_branch", branch);
    defer if (branch) |br| {
        allocator.free(br);
    };

    const versionString = std.fmt.comptimePrint("{}", .{zvm_version});
    options.addOption([]const u8, "version", versionString);

    const isCi = blk: {
        const ci = std.process.getEnvVarOwned(allocator, "CI") catch break :blk false;
        defer allocator.free(ci);
        break :blk std.mem.eql(u8, ci, "true");
    };

    options.addOption(bool, "is_ci", isCi);
    options.addOption(?[DATE_SIZE]u8, "build_date", date(allocator) orelse null);

    _ = b.addModule("ansi", .{
        .root_source_file = b.path("src/ansi.zig"),
    });

    const zvm = b.addExecutable(.{
        .name = "zvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(zvm);

    const run_cmd = b.addRunArtifact(zvm);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    _ = registerTest(b, test_step, .{
        .root_source_file = b.path("src/arg_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = registerTest(b, test_step, .{
        .root_source_file = b.path("src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = registerTest(b, test_step, .{
        .root_source_file = b.path("src/ansi.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = registerTest(b, test_step, .{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
}

inline fn registerTest(b: *std.Build, step: *std.Build.Step, options: std.Build.TestOptions) *std.Build.Step.Compile {
    const exe_tests = b.addTest(options);
    step.dependOn(&exe_tests.step);
    return exe_tests;
}

fn gitCommitHash(allocator: std.mem.Allocator) ?[40]u8 {
    const exec_result = std.ChildProcess.run(.{
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
    @memcpy(&output, exec_result.stdout[0..40]);
    return output;
}

fn gitCommitCount(allocator: std.mem.Allocator) ?u32 {
    const exec_result = std.ChildProcess.run(.{
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
    const exec_result = std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    if (exec_result.stdout.len == 0) return null;
    if (exec_result.stderr.len != 0) return null;

    const idx = std.mem.indexOf(u8, exec_result.stdout[0..], "\n") orelse return null;
    const allocated = allocator.alloc(u8, idx) catch return null;
    @memcpy(allocated, exec_result.stdout[0..allocated.len]);
    return allocated;
}

const DATE_SIZE = 25;

fn date(allocator: std.mem.Allocator) ?[DATE_SIZE]u8 {
    const exec_result = std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &.{ "date", "+%Y-%m-%d %H:%M:%S %z" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    var output: [DATE_SIZE]u8 = undefined;
    @memcpy(&output, exec_result.stdout[0..DATE_SIZE]);
    return output;
}
