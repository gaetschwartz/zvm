const std = @import("std");
const idx = @import("../index.zig");
const builtin = @import("builtin");
const http = std.http;
const mem = std.mem;
const ansi = @import("ansi");
const utils = @import("../utils.zig");
const zvmDir = utils.zvmDir;
const RunContext = @import("../arg_parser.zig").ArgParser.RunContext;
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
        std.log.err("could not find release for channel {s}", .{target});
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

    try utils.makeDirAbsolutePermissive(zvm);
    try utils.makeDirAbsolutePermissive(zvm_versions);
    try utils.makeDirAbsolutePermissive(zvm_cache);
    try utils.makeDirAbsolutePermissive(zvm_cache_web);

    const version_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm_versions, target });
    const version_info_path = try std.fs.path.join(allocator, &[_][]const u8{ version_path, ".zvm.json" });
    blk: {
        const version_info = readVersionInfo(allocator, version_info_path) catch |err| {
            if (err == error.FileNotFound) break :blk;
            return err;
        };
        const force = ctx.args.hasFlag("force");
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

        // there is a version installed, but it is not the one we want to install
        // remove the old version recursively
        const argv = switch (builtin.os.tag) {
            .windows => &[_][]const u8{ "rmdir", "/s", "/q", version_path },
            else => &[_][]const u8{ "rm", "-rf", version_path },
        };
        const res = try std.ChildProcess.exec(.{
            .argv = argv,
            .allocator = allocator,
        });
        handleResult(res, argv) catch |err| {
            std.log.err("could not remove old version: {any}", .{err});
            return;
        };
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
            return err;
        };
        defer cached_archive.close();
        // max size of archive is 100MB

        var cached_archive_shasum: [utils.digest_length * 2]u8 = undefined;
        // compute the shasum of the cached archive
        try utils.shasum(cached_archive.reader(), &cached_archive_shasum);
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
        try stdout.print(ansi.style("Using cached archive {s}\n", .{ .green, .fade }), .{filename});
    } else {
        try stdout.print(ansi.style("Downloading " ++ ansi.bold("{s}") ++ "...", .blue) ++ ansi.fade("({s})\n"), .{ target, archive.tarball });

        try fetchArchiveChildProcess(.{
            .url = archive.tarball,
            .path = cache_path,
            .allocator = allocator,
            .total_size = archive.size,
        });
    }

    const archive_type = utils.archiveType(filename);
    switch (archive_type) {
        .zip => {
            try unarchiveZip(cache_path, zvm_versions, allocator);
        },
        .@"tar.xz" => {
            try unarchiveTarXz(cache_path, zvm_versions, allocator);
        },
        .Unknown => {
            std.log.debug("unknown archive type of {s}", .{std.fs.path.basename(filename)});
            return;
        },
    }
    std.log.debug("Unarchived {s} to {s}", .{ filename, zvm_versions });

    // rename the directory to the version
    const archive_folder = utils.stripExtension(filename, archive_type);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ zvm_versions, archive_folder });
    std.log.debug("archive path: {s}", .{archive_path});
    // try std.fs.renameAbsolute(archive_path, version_path);
    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "move", archive_path, version_path },
        else => &[_][]const u8{ "mv", archive_path, version_path },
    };
    const res = try std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = allocator,
    });
    handleResult(res, argv) catch |err| {
        std.log.err("could not rename archive: {any}", .{err});
        return;
    };
    std.log.debug("renamed {s} to {s}\n", .{ archive_path, version_path });

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
    handleResult(res, argv) catch |err| {
        std.log.err("could not fetch archive: {any}", .{err});
        return;
    };
}

pub fn handleResult(res: std.ChildProcess.ExecResult, cmd: [][]const u8) !void {
    switch (res.term) {
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
    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "powershell", "-Command", "Expand-Archive", path, dest },
        else => &[_][]const u8{ "unzip", path, "-d", dest },
    };
    const res = try std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = allocator,
    });
    handleResult(res, argv) catch |err| {
        std.log.err("could not unarchive zip: {any}", .{err});
        return;
    };
}

/// Using child process to untar
fn unarchiveTarXz(path: []const u8, dest: []const u8, allocator: std.mem.Allocator) !void {
    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "powershell", "-Command", "Expand-Archive", path, dest },
        else => &[_][]const u8{ "tar", "-xJf", path, "-C", dest },
    };
    const res = try std.ChildProcess.exec(.{
        .argv = argv,
        .allocator = allocator,
    });
    handleResult(res, argv) catch |err| {
        std.log.err("could not unarchive tar.xz: {any}", .{err});
        return;
    };
}

pub fn fetchArchiveZig(args: FetchArchiveArgs) !void {
    const total_human = utils.humanSize(@intCast(i64, args.total_size));

    // check if the file exists
    var file: std.fs.File = blk: {
        break :blk std.fs.openFileAbsolute(args.path, .{ .mode = .read_write }) catch |err| {
            std.log.debug("error: {any}\n", .{err});
            if (err == error.FileNotFound) {
                // create the file
                std.log.debug("creating file: {s}\n", .{args.path});
                break :blk try std.fs.createFileAbsolute(args.path, .{});
            } else {
                return err;
            }
        };
    };
    defer file.close();
    var writer = file.writer();

    var client = std.http.Client{
        .allocator = args.allocator,
    };
    var uri = try std.Uri.parse(args.url);
    var req = try client.request(uri, .{}, .{});

    var total_read: usize = 0;
    var temp_buffer = [_]u8{0} ** 1024;
    // current time
    var now = std.time.milliTimestamp();
    while (true) {
        const read: usize = try req.read(&temp_buffer);
        total_read += read;

        const percent = (total_read * 100) / args.total_size;
        const elapsed = std.time.milliTimestamp() - now;
        const rate = @divTrunc((@intCast(i64, total_read)), elapsed);
        const human = utils.humanSize(rate);
        const read_human = utils.humanSize(@intCast(i64, total_read));
        std.log.debug("\r{d} {s} / {d} {s} ({d}%) {d} {s}/s", .{ read_human.value, read_human.unit, total_human.value, total_human.unit, percent, human.value, human.unit });
        if (read == 0) break;
        _ = try writer.write(temp_buffer[0..read]);
    }
    try file.sync();
    std.log.debug("\nSuccessfully downloaded {s} to {s} ({d} bytes)\n", .{ args.url, args.path, total_read });
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
