const std = @import("std");

pub fn main() !void {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var client = std.http.Client{
            .allocator = std.heap.page_allocator,
        };
        defer client.deinit();
        var uri = try std.Uri.parse("https://ziglang.org/download/0.10.1/zig-macos-aarch64-0.10.1.tar.xz");
        var req = try client.request(uri, .{}, .{});
        defer req.deinit();

        var total_read: usize = 0;
        var temp_buffer: [32 * 1024]u8 = undefined;
        while (true) {
            const read: usize = try req.read(&temp_buffer);
            total_read += read;
            std.debug.print("[{d}] read {} bytes, total read: {} bytes\n", .{ i, read, total_read });
            if (read == 0) break;
        }
        std.debug.print("[{d}] total read: {} bytes\n", .{ i, total_read });
    }
}
