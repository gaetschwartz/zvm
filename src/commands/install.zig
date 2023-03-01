const std = @import("std");
const idx = @import("../index.zig");
const builtin = @import("builtin");
const http = std.http;
const mem = std.mem;
const ansi = @import("ansi");
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const RunContext = @import("../arg_parser.zig").ArgParser.RunContext;
const Command = @import("../arg_parser.zig").Command;
const VersionInfo = @import("list.zig").VersionInfo;
const readVersionInfo = @import("list.zig").readVersionInfo;

const Index = idx.Index;
const Release = idx.Release;
const Archive = idx.Archive;

pub fn install_cmd(ctx: RunContext) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const force = ctx.args.hasFlag("force");

    const target_nullable = ctx.getPositional("version");
    if (target_nullable == null) {
        std.log.err("No channel provided\n", .{});
        return;
    }
    const target = target_nullable.?;
    const is_upgrade = std.mem.eql(u8, ctx.command.name, "upgrade");

    var index = try idx.fetchIndex(allocator);

    var target_string = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag) });
    std.log.debug("target string: {s}", .{target_string});
    var is_target_a_channel = true;
    const release = getRelease(index, target, &is_target_a_channel) orelse {
        try stderr.print(ansi.style("Could not find any version for " ++ ansi.bold("{s}") ++ ".\n", .red), .{target});
        return;
    };
    if (is_upgrade and !is_target_a_channel) {
        try stderr.print(ansi.style("Only channels can be upgraded, not specific versions.\n", .red), .{});
        return;
    }

    std.log.debug("release for {s}: ", .{target});
    idx.dumpRelease(release);
    std.log.debug("\n", .{});
    const archive = archiveForTarget(release, target_string) orelse {
        try stdout.print("No archive for target {s}\n", .{target_string});
        return;
    };
    std.log.debug("archive: {s}", .{archive.tarball});

    const zvm = zvmDir(allocator) catch |err| {
        std.log.err(" could not get zvm directory: {any}", .{err});
        return;
    };
    const zvm_versions = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "versions" });
    const zvm_cache = try std.fs.path.join(allocator, &[_][]const u8{ zvm, "cache" });
    const zvm_cache_web = try std.fs.path.join(allocator, &[_][]const u8{ zvm_cache, "web" });
    const zvm_cache_temp = try std.fs.path.join(allocator, &[_][]const u8{ zvm_cache, "temp" });
    const temp_name = try std.fmt.allocPrint(allocator, "{x}", .{std.time.milliTimestamp()});
    const zvm_cache_temp_target = try std.fs.path.join(allocator, &[_][]const u8{ zvm_cache_temp, temp_name });

    const cwd = std.fs.cwd();
    // try cwd.makePath(zvm);
    try cwd.makePath(zvm_versions);
    // try cwd.makePath(zvm_cache);
    try cwd.makePath(zvm_cache_web);
    try cwd.makePath(zvm_cache_temp);
    try cwd.makePath(zvm_cache_temp_target);

    const version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm_versions, target });
    const version_info_path = try std.fs.path.join(allocator, &[_][]const u8{ version_path, ".zvm.json" });
    blk: {
        const version_info = readVersionInfo(allocator, version_info_path) catch |err| {
            if (err == error.FileNotFound) break :blk;
            return err;
        };
        if (force) {
            std.log.debug("force flag is set, removing old version", .{});
        }

        if (is_upgrade) {
            if (std.mem.eql(u8, version_info.version, release.version) and !force) {
                try stdout.print(ansi.style("Already up to date.\n", .green), .{});
                return;
            }
        } else {
            try stdout.print(ansi.style("Version {s} is already installed.\n", .green), .{target});
            if (is_target_a_channel)
                try stdout.print(ansi.fade("To upgrade, run `zvm upgrade {s}`\n"), .{target});
            return;
        }

        std.log.debug("version info: {}", .{version_info});
        std.log.debug("removing old version: {s}", .{version_path});

        try std.fs.deleteTreeAbsolute(version_path);
    }

    const filename = std.fs.path.basename(archive.tarball);
    const cache_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm_cache_web, filename });
    std.log.debug("cache path: {s}", .{cache_path});

    // check if the archive is already in the cache
    var is_cached = blk: {
        const cached_archive = std.fs.openFileAbsolute(cache_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            stderr.print("error opening cached archive: {any}\n", .{err}) catch {};
            break :blk false;
        };
        defer cached_archive.close();

        var cached_archive_shasum: [utils.Shasum256.digest_length_hex]u8 = undefined;
        // compute the shasum of the cached archive
        try utils.Shasum256.compute(cached_archive.reader(), &cached_archive_shasum);
        // compare the shasum of the cached archive with the one in the index
        if (std.mem.eql(u8, &cached_archive_shasum, archive.shasum)) {
            std.log.debug("shasum match: {s} == {s}", .{ cached_archive_shasum, archive.shasum });
            break :blk true;
        } else {
            std.log.debug("shasum mismatch: {s} != {s}", .{ cached_archive_shasum, archive.shasum });
            break :blk false;
        }
    };

    if (is_cached) {
        std.log.debug("archive is cached", .{});
        try stdout.print(ansi.style("Using {s} from cache...\n", .{ .blue, .fade }), .{release.version});
    } else {
        try stdout.print(ansi.style("Downloading " ++ ansi.bold("{s}") ++ "... ", .blue) ++ ansi.fade("({s})\n"), .{ target, archive.tarball });

        try fetchArchiveZig(.{
            .url = archive.tarball,
            .path = cache_path,
            .allocator = allocator,
            .total_size = archive.size,
        });
    }
    // Check the sha256sum of the archive
    if (!force) {
        var archive_shasum: [utils.Shasum256.digest_length_hex]u8 = undefined;
        var file = try std.fs.openFileAbsolute(cache_path, .{});
        defer file.close();
        try utils.Shasum256.compute(file.reader(), &archive_shasum);
        if (!std.mem.eql(u8, &archive_shasum, archive.shasum)) {
            stderr.print(ansi.style("error: shasum mismatch for {s}\n", .{ .red, .bold }), .{archive.tarball}) catch {};
            stderr.print(ansi.style("  expected: {s}\n", .{.red}), .{archive.shasum}) catch {};
            stderr.print(ansi.style("  got: {s}\n", .{.red}), .{archive_shasum}) catch {};
            return;
        }
    } else {
        std.log.debug("force flag is set, skipping shasum check", .{});
    }

    std.log.debug("unarchiving {s} to {s}", .{ filename, zvm_cache_temp_target });

    const archive_type = utils.archiveType(filename);
    switch (archive_type) {
        .zip => {
            try unarchiveZip(cache_path, zvm_cache_temp_target, allocator);
        },
        .@"tar.xz" => {
            try unarchiveTarXz(cache_path, zvm_cache_temp_target, allocator);
        },
        .unknown => {
            try stderr.print("Warning: unknown archive type: {s}\n", .{filename});
            try stderr.print(ansi.fade("Assuming tar.xz...\n"), .{});

            try unarchiveTarXz(cache_path, zvm_cache_temp_target, allocator);
        },
    }
    std.log.debug("Unarchiving complete", .{});

    // rename the directory to the version

    const archive_path = try getFirstDirInDir(allocator, zvm_cache_temp_target);
    defer allocator.free(archive_path);

    std.log.debug("archive path: {s}", .{archive_path});
    // remove old version if it exists
    std.log.debug("removing old version: {s}", .{version_path});
    try std.fs.deleteTreeAbsolute(version_path);
    std.log.debug("renaming {s} to {s}", .{ archive_path, version_path });
    try std.fs.renameAbsolute(archive_path, version_path);
    std.log.debug("deleting temp directory: {s}", .{zvm_cache_temp_target});
    try std.fs.deleteTreeAbsolute(zvm_cache_temp_target);

    // write the version file
    const version_file_path = try std.fs.path.join(allocator, &[_][]const u8{ version_path, ".zvm.json" });
    const version_info = VersionInfo{
        .version = release.version,
        .channel = if (is_target_a_channel) target else null,
    };
    const version_file = try std.fs.createFileAbsolute(version_file_path, .{});
    defer version_file.close();
    var writer = version_file.writer();
    try std.json.stringify(version_info, .{}, writer);
    std.log.debug("wrote version file to {s}", .{version_file_path});

    try stdout.print(ansi.style("Successfully installed " ++ ansi.bold("{s}") ++ ".\n", .green), .{target});
}

fn getFirstDirInDir(allocator: std.mem.Allocator, dir: []const u8) ![]const u8 {
    var dir_file = try std.fs.openIterableDirAbsolute(dir, .{});
    defer dir_file.close();

    var dir_it = dir_file.iterate();
    var found: ?[]const u8 = null;
    while (try dir_it.next()) |entry| {
        if (entry.kind == .Directory) {
            if (builtin.mode != .Debug) {
                if (found != null) {
                    return error.MultipleDirectoriesFound;
                }
            }
            found = try std.fs.path.join(allocator, &[_][]const u8{ dir, entry.name });
            if (builtin.mode != .Debug) {
                break;
            }
        }
    }
    if (found != null) {
        return found.?;
    } else {
        return error.NoDirectoryFound;
    }
}

fn getLatestReleaseForChannel(index: Index, channel: []const u8) ?Release {
    var latest: ?Release = null;
    for (index.releases.items) |entry| {
        const isChannel = std.mem.eql(u8, entry.channel, channel);
        if (isChannel and (latest == null or std.mem.order(u8, entry.date, latest.?.date) == .gt)) {
            latest = entry;
        }
    }
    return latest;
}

fn getReleaseWithVersion(index: Index, version: []const u8) ?Release {
    for (index.releases.items) |entry| {
        if (std.mem.eql(u8, entry.version, version)) {
            return entry;
        }
    }
    return null;
}

fn getRelease(index: Index, target: []const u8, is_target_a_channel: *bool) ?Release {
    return getLatestReleaseForChannel(index, target) orelse {
        is_target_a_channel.* = false;
        return getReleaseWithVersion(index, target);
    };
}

fn archiveForTarget(release: Release, target: []const u8) ?Archive {
    for (release.archives.items) |archive| {
        if (std.mem.eql(u8, archive.target, target)) {
            return archive;
        }
    }
    return null;
}

const FetchArchiveArgs = struct {
    url: []const u8,
    path: []const u8,
    total_size: usize,
    allocator: std.mem.Allocator,
};

fn fetchArchiveChildProcess(args: FetchArchiveArgs) !void {
    const argv = switch (builtin.os.tag) {
        // use bitsadmin on windows
        .windows => &[_][]const u8{ "bitsadmin", "/transfer", "zvm", args.url, args.path },
        else => &[_][]const u8{ "curl", "-L", args.url, "-o", args.path },
    };
    if (@import("builtin").mode == .Debug) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("fetching archive with command: '", .{});
        printArgv(argv);
        try stderr.print("'\n", .{});
    }
    const res = try std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = args.allocator,
    });
    handleResult(res.term, argv) catch |err| {
        std.log.err("could not fetch archive: {any}", .{err});
        return;
    };
}

pub fn handleResult(res: std.ChildProcess.Term, cmd: [][]const u8) !void {
    switch (res) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("{s}Command ", .{ansi.c(.RED)});
                printArgv(cmd);
                std.debug.print("exited with code {d}.{s}\n", .{ code, ansi.c(.RESET) });
                // exit(1);
                return error.CommandFailed;
            }
        },
        .Signal => |signal| {
            // std.log.debug("Command {any} was signaled with {d}\n", .{ term.cmd, signal });
            std.debug.print("{s}Command ", .{ansi.c(.RED)});
            printArgv(cmd);
            std.debug.print("was signaled with {d}.{s}\n", .{ signal, ansi.c(.RESET) });
            // exit(1);
            return error.CommandFailed;
        },
        else => {},
    }
}

/// Using child process to unzip
fn unarchiveZip(path: []const u8, dest: []const u8, allocator: std.mem.Allocator) !void {
    const concat = std.fmt.allocPrint(allocator, "-o{s}", .{dest}) catch |err| {
        std.log.err("could not concat path and dest: {any}", .{err});
        return;
    };
    defer allocator.free(concat);
    const argv = switch (builtin.os.tag) {
        .windows => if (check7Zip())
            &[_][]const u8{ "7z", "x", path, concat, "-y" }
        else
            &[_][]const u8{ "powershell", "-Command", "Expand-Archive", path, dest, "-Force" },
        else => &[_][]const u8{ "unzip", path, "-d", dest },
    };
    var process = std.ChildProcess.init(argv, allocator);
    process.stderr_behavior = .Ignore;
    process.stdout_behavior = if (@import("builtin").mode == .Debug) .Pipe else .Ignore;

    const res = try process.spawnAndWait();

    handleResult(res, argv) catch |err| {
        std.log.err("could not unarchive zip: {any}", .{err});
        return;
    };
}

fn check7Zip() bool {
    const argv = &[_][]const u8{"7z"};
    const res = std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = std.heap.page_allocator,
    }) catch |err| {
        std.log.debug("could not check find 7zip: {any}", .{err});
        return false;
    };
    std.log.debug("7zip found, terminated with {any}", .{res.term});
    return res.term == .Exited and res.term.Exited == 0;
}

/// Using child process to untar
fn unarchiveTarXz(path: []const u8, dest: []const u8, allocator: std.mem.Allocator) !void {
    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "powershell", "-Command", "Expand-Archive", path, dest },
        else => &[_][]const u8{ "tar", "-xJf", path, "-C", dest },
    };
    var process = std.ChildProcess.init(argv, allocator);
    process.stderr_behavior = .Ignore;

    const res = try process.spawnAndWait();
    handleResult(res, argv) catch |err| {
        std.log.err("could not unarchive tar.xz: {any}", .{err});
        return;
    };
}

// clear current line using ansi escape sequence
const CLEAR_LINE = "\x1b[2K";
// SET CURSOR TO 0
const CURSOR_TO_0 = "\x1b[0G";

pub fn fetchArchiveZig(args: FetchArchiveArgs) !void {
    const stdout = std.io.getStdOut().writer();
    const total_human = utils.HumanSize(f64).compute(@intToFloat(f64, args.total_size));

    // check if the file exists
    var file = try std.fs.createFileAbsolute(args.path, .{});
    defer file.close();
    var writer = file.writer();

    var client = std.http.Client{ .allocator = args.allocator };
    var uri = try std.Uri.parse(args.url);
    var req = try client.request(uri, .{}, .{});

    var total_read: usize = 0;
    var temp_buffer: [32 * 1024]u8 = undefined;
    // current time
    var now = std.time.milliTimestamp();
    while (true) {
        const read: usize = try req.read(&temp_buffer);
        total_read += read;

        const percent = (total_read * 100) / args.total_size;
        const elapsed: i64 = std.time.milliTimestamp() - now;
        const rate = @intToFloat(f64, 1000 * total_read) / @intToFloat(f64, elapsed);
        const human = utils.HumanSize(f64).compute(rate);
        const read_human = utils.HumanSize(f64).compute(@intToFloat(f64, total_read));
        try stdout.print(CLEAR_LINE ++ CURSOR_TO_0 ++ "[{d}%] {d:.2} {s} / {d:.2} {s} | {d:.0} {s}/s", .{ percent, read_human.value, read_human.unit, total_human.value, total_human.unit, human.value, human.unit });
        if (read == 0) break;
        _ = try writer.write(temp_buffer[0..read]);
    }
    const d = std.time.milliTimestamp() - now;
    try stdout.print(ansi.style(CLEAR_LINE ++ CURSOR_TO_0 ++ "Downloaded " ++ ansi.bold("{d:.1} {s}") ++ " in " ++ ansi.bold("{d:.1}s") ++ ".\n", .blue), .{ total_human.value, total_human.unit, @intToFloat(f64, d) / 1000 });

    try file.sync();
}

inline fn printArgv(argv: [][]const u8) void {
    for (argv) |arg| {
        std.debug.print("{s} ", .{arg});
    }
}

fn request(client: *http.Client, uri: std.Uri, headers: http.Client.Request.Headers, options: http.Client.Request.Options) !http.Client.Request {
    const protocol: http.Client.Connection.Protocol = if (mem.eql(u8, uri.scheme, "http"))
        .plain
    else if (mem.eql(u8, uri.scheme, "https"))
        .tls
    else
        return error.UnsupportedUrlScheme;

    const port: u16 = uri.port orelse switch (protocol) {
        .plain => 80,
        .tls => 443,
    };

    const host = uri.host orelse return error.UriMissingHost;

    if (client.next_https_rescan_certs and protocol == .tls) {
        try client.ca_bundle.rescan(client.allocator);
        client.next_https_rescan_certs = false;
    }

    var req: http.Client.Request = .{
        .client = client,
        .headers = headers,
        .connection = try client.connect(host, port, protocol),
        .redirects_left = options.max_redirects,
        .response = switch (options.header_strategy) {
            .dynamic => |max| http.Client.Request.Response.initDynamic(max),
            .static => |buf| http.Client.Request.Response.initStatic(buf),
        },
    };

    {
        var h = try std.BoundedArray(u8, 1000).init(0);
        try h.appendSlice(@tagName(headers.method));
        try h.appendSlice(" ");
        try h.appendSlice(uri.path);
        try h.appendSlice(" ");
        try h.appendSlice(@tagName(headers.version));
        try h.appendSlice("\r\nHost: ");
        try h.appendSlice(host);
        try h.appendSlice("\r\nConnection: keep-alive\r\n\r\n");

        const header_bytes = h.slice();
        try req.connection.writeAll(header_bytes);
    }

    return req;
}

pub fn IndexCompleter(comptime doShowVerions: bool) type {
    return struct {
        const Self = @This();

        pub fn complete(ctx: Command.CompletionContext) !std.ArrayList(Command.Completion) {
            var completions = std.ArrayList(Command.Completion).init(ctx.allocator);
            const stdout = std.io.getStdOut().writer();
            _ = stdout;

            var index = try idx.fetchIndex(ctx.allocator);
            defer index.deinit();

            var channels = std.StringHashMap(bool).init(ctx.allocator);
            defer channels.deinit();

            for (index.releases.items) |release| {
                if (doShowVerions) {
                    try completions.append(.{ .name = release.version, .description = release.channel });
                }
                if (!channels.contains(release.channel)) {
                    try completions.append(.{ .name = release.channel });
                    try channels.put(release.channel, true);
                }
            }
            return completions;
        }
    };
}
