const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var allocator = arena.allocator();
    defer arena.deinit();

    const options = b.addOptions();
    if (git_commit(allocator)) |commit| {
        options.addOption(?[]const u8, "git_commit", commit[0..]);
    } else {
        options.addOption(?[]const u8, "git_commit", null);
    }
    const build_info = getBuildInfo(allocator);
    const commit_count = commitCount(allocator) orelse 0;
    const branch = gitBranch(allocator);
    defer {
        if (branch) |br|
            allocator.free(br);
    }
    const versionStr = std.fmt.allocPrint(allocator, "{s}-{s}.{d}", .{ build_info.version, branch orelse "null", commit_count }) catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };

    defer allocator.free(versionStr);
    options.addOption(?[]const u8, "version", versionStr);

    const isCi = std.process.getEnvVarOwned(allocator, "CI") catch "false";
    // defer allocator.free(isCi);
    options.addOption(?[]const u8, "is_ci", isCi);
    options.addOption(?[DATE_SIZE]u8, "build_date", date(allocator) orelse null);

    const knownFolders = b.createModule(.{
        .source_file = .{ .path = "known-folders/known-folders.zig" },
    });

    const zvm = b.addExecutable(.{
        .name = "zvm",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    zvm.addModule("known-folders", knownFolders);
    zvm.addOptions("zvm_build_options", options);
    zvm.install();

    const run_cmd = zvm.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    registerTest(b, test_step, .{
        .root_source_file = .{ .path = "src/arg_parser.zig" },
        .target = target,
        .optimize = optimize,
    });
}

inline fn registerTest(b: *std.Build, step: *std.Build.Step, options: std.Build.TestOptions) void {
    const exe_tests = b.addTest(options);
    step.dependOn(&exe_tests.step);
}

fn git_commit(allocator: std.mem.Allocator) ?[40]u8 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--verify", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    // +1 for trailing newline.
    if (exec_result.stdout.len != 40 + 1) return null;
    if (exec_result.stderr.len != 0) return null;

    var output: [40]u8 = undefined;
    std.mem.copy(u8, &output, exec_result.stdout[0..40]);
    return output;
}

fn commitCount(allocator: std.mem.Allocator) ?u8 {
    const exec_result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-list", "--count", "HEAD" },
    }) catch return null;
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    var i: usize = 0;
    var number: u8 = 0;
    while (i < 8) : (i += 1) {
        switch (exec_result.stdout[i]) {
            '\n' => break,
            '1'...'9' => number = number * 10 + (exec_result.stdout[i] - '0'),
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

    // +1 for trailing newline.
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

// parse ./build.json and return a BuildInfo struct
fn getBuildInfo(allocator: std.mem.Allocator) BuildInfo {
    const build_json = std.fs.cwd().openFile("build.json", .{}) catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };
    defer build_json.close();
    const build_json_size = build_json.getEndPos() catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };
    var buffer = allocator.alloc(u8, build_json_size) catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };

    _ = build_json.readAll(buffer) catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };

    defer allocator.free(buffer);

    var stream = std.json.TokenStream.init(buffer);
    const build_info = std.json.parse(BuildInfo, &stream, .{ .allocator = allocator }) catch |err| {
        std.debug.print("error: {}\n", .{err});
        std.os.exit(1);
    };
    return build_info;
}

pub const BuildInfo = struct {
    version: []const u8,
};
