const std = @import("std");
const net = std.net;
const mem = std.mem;
const fs = std.fs;
const io = std.io;
const os = std.os;
const win = std.os.windows;
const ws2_32 = std.os.windows.ws2_32;
const Reader = @import("reader.zig").Reader;
const StringUtils = @import("reader.zig").StringUtils;

// const res: ws2_32.WSADATA = try win.WSAStartup(2, 2);
//   const max_sockets: u16 = res.iMaxSockets;
//   defer win.WSACleanup() catch unreachable;
//   std.log.info("max sockets: {}", .{max_sockets});

//   // query https://ziglang.org/download/index.json
//   const alloc = std.heap.page_allocator;
//   const client: std.net.Stream = try net.tcpConnectToHost(alloc, "ziglang.org", 80);

//   // send request
//   // content type json
//   const request =
//       \\GET /download/index.json HTTP/1.1
//       \\User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36
//       \\Host: ziglang.org
//       \\Accept-Language: en-US
//       \\Accept-Encoding: gzip, deflate
//       \\Content-Type: application/json
//       \\Connection: keep-alive
//       \\Accept: */*
//   ;
//   comptime {
//       // check if it contains a \r
//       var i: usize = 0;
//       while (i < request.len) : (i += 1) {
//           if (request[i] == '\r') {
//               @panic("request contains \\r");
//           }
//       }
//   }
//   std.log.info("===== request =====\n{s}\n===== request =====", .{request});

//   try client.writer().writeAll(request);

//   // allocate 128kb buffer
//   var buf: [128 * 1024]u8 = undefined;
//   // write all data to buffer
//   var total: usize = 0;
//   while (true) {
//       const bytes_read = try client.reader().read(buf[total..]);
//       if (bytes_read == 0) break;
//       total += bytes_read;
//   }
//   std.log.info("total bytes read: {}", .{total});
//   std.log.info("{s}", .{buf[0..total]});

const SimpleHtttpClient = struct {
    const Self = @This();

    const Header = struct {
        key: []const u8,
        value: []const u8,

        pub fn init(key: []const u8, value: []const u8) SimpleHtttpClient.Header {
            return .{ .key = key, .value = value };
        }
    };

    const Request = struct {
        const Method = enum {
            GET,
            POST,
            PUT,
            DELETE,
            HEAD,
            OPTIONS,
            PATCH,

            pub fn toSlice(self: Self.Request.Method) []const u8 {
                return switch (self) {
                    .GET => "GET",
                    .POST => "POST",
                    .PUT => "PUT",
                    .DELETE => "DELETE",
                    .HEAD => "HEAD",
                    .OPTIONS => "OPTIONS",
                    .PATCH => "PATCH",
                };
            }
        };

        method: Self.Request.Method,
        path: []const u8,
        headers: []const Self.Header,
        body: []const u8,

        pub fn init(method: Self.Request.Method, path: []const u8, headers: []const Self.Header, body: []const u8) Self.Request {
            return .{
                .method = method,
                .path = path,
                .headers = headers,
                .body = body,
            };
        }
    };

    const Response = struct {
        alloc: std.mem.Allocator,
        status_code: u16,
        headers: []const Self.Header,
        body: []const u8,

        pub fn init(alloc: std.mem.Allocator, status_code: u16, headers: []const Self.Header, body: []const u8) Response {
            return .{
                .alloc = alloc,
                .status_code = status_code,
                .headers = headers,
                .body = body,
            };
        }

        pub fn deinit(self: Response) void {
            self.alloc.free(self.headers);
            self.alloc.free(self.body);
        }
    };

    const Method = Self.Request.Method;

    const HeaderStr = enum {
        USER_AGENT,
        HOST,
        ACCEPT_LANGUAGE,
        ACCEPT_ENCODING,
        CONTENT_TYPE,
        CONNECTION,
        ACCEPT,

        pub fn toSlice(self: SimpleHtttpClient.HeaderStr) []const u8 {
            return switch (self) {
                .USER_AGENT => "User-Agent",
                .HOST => "Host",
                .ACCEPT_LANGUAGE => "Accept-Language",
                .ACCEPT_ENCODING => "Accept-Encoding",
                .CONTENT_TYPE => "Content-Type",
                .CONNECTION => "Connection",
                .ACCEPT => "Accept",
            };
        }
    };

    pub const RequestResult = union(enum) {
        Response: Response,
        Error: HttpClientError,

        pub fn deinit(self: RequestResult) void {
            switch (self) {
                .Response => |r| r.deinit(),
                .Error => {},
            }
        }
    };

    pub const HttpClientError = struct {
        message: []const u8,
        err: ?anyerror = null,
    };

    pub const max_response_size: usize = 128 * 1024;

    pub fn sendRequest(alloc: std.mem.Allocator, host: []const u8, port: u16, request: Self.Request) RequestResult {
        // startup wsa
        const res: ws2_32.WSADATA = win.WSAStartup(2, 2) catch |err| {
            return .{ .Error = .{ .message = "failed to startup wsa", .err = err } };
        };
        const max_sockets: u16 = res.iMaxSockets;
        std.log.info("max sockets: {d}", .{max_sockets});
        defer win.WSACleanup() catch unreachable;
        const client: std.net.Stream = net.tcpConnectToHost(alloc, host, port) catch |err| {
            return .{ .Error = .{ .message = "failed to connect to host", .err = err } };
        };
        defer client.close();

        // send request
        // content type json
        var rqBuf = std.ArrayList(u8).init(alloc);
        defer rqBuf.deinit();

        // method
        rqBuf.appendSlice(request.method.toSlice()) catch |err| {
            return .{ .Error = .{ .message = "failed to append method to request buffer", .err = err } };
        };

        // path

        rqBuf.append(' ') catch |err|
            return .{ .Error = .{ .message = "failed to append space to request buffer", .err = err } };
        rqBuf.appendSlice(request.path) catch |err|
            return .{ .Error = .{ .message = "failed to append path to request buffer", .err = err } };

        // http version
        rqBuf.appendSlice(" HTTP/1.1\n") catch |err|
            return .{ .Error = .{ .message = "failed to append http version to request buffer", .err = err } };

        // headers
        for (request.headers) |header| {
            rqBuf.appendSlice(header.key) catch |err|
                return .{ .Error = .{ .message = "failed to append header key to request buffer", .err = err } };
            rqBuf.appendSlice(": ") catch |err|
                return .{ .Error = .{ .message = "failed to append header value to request buffer", .err = err } };
            rqBuf.appendSlice(header.value) catch |err|
                return .{ .Error = .{ .message = "failed to append header value to request buffer", .err = err } };
            rqBuf.append('\n') catch |err|
                return .{ .Error = .{ .message = "failed to append header value to request buffer", .err = err } };
        }

        // body

        if (request.body.len > 0) {
            rqBuf.appendSlice("Content-Length: ") catch unreachable;
            const content_length = std.fmt.allocPrint(alloc, "{d:.}", .{request.body.len}) catch unreachable;
            defer alloc.free(content_length);
            rqBuf.appendSlice(content_length) catch unreachable;
            rqBuf.appendSlice("\nContent-Type: application/json\n\n") catch unreachable;
            rqBuf.appendSlice(request.body) catch unreachable;
        } else {
            rqBuf.append('\n') catch unreachable;
        }

        std.log.warn("request: {s}", .{rqBuf.items});

        // send request
        client.writer().writeAll(rqBuf.toOwnedSlice()) catch |err| {
            return .{ .Error = .{ .message = "failed to send request", .err = err } };
        };

        std.log.warn("request sent", .{});

        // read response
        var rcvBuf = std.ArrayList(u8).init(alloc);
        defer rcvBuf.deinit();

        // read all to buffer
        client.reader().readAllArrayList(&rcvBuf, max_response_size) catch |err| {
            return .{ .Error = .{ .message = "failed to read response", .err = err } };
        };
        const slc = rcvBuf.toOwnedSlice();

        std.log.warn("response: {s}", .{slc});

        var reader = Reader(u8).init(slc);

        // parse response

        // HTTP/1.1
        const http = reader.readUntilDelimiterN(' ') catch |err| {
            return .{ .Error = .{ .message = "failed to read http version", .err = err } };
        };
        if (!std.mem.eql(u8, http, "HTTP/1.1")) {
            return .{ .Error = .{ .message = "Invalid HTTP version" } };
        }

        // status code
        var status_code_bytes = reader.readUntilDelimiterN(' ') catch |err| {
            return .{ .Error = .{ .message = "failed to read status code", .err = err } };
        };
        const status_code = std.fmt.parseInt(u16, status_code_bytes, 10) catch |err| {
            return .{ .Error = .{ .message = "failed to parse status code", .err = err } };
        };

        // msg
        _ = reader.readUntil('\n') catch |err| {
            return .{ .Error = .{ .message = "failed to read message", .err = err } };
        };

        // headers
        var headers = std.ArrayList(Self.Header).init(alloc);
        defer headers.deinit();

        while (true) {
            const key = StringUtils.trim(reader.readUntil(':') catch |err| {
                return .{ .Error = .{ .message = "failed to read header key", .err = err } };
            });
            const value = StringUtils.trim(reader.readUntil('\n') catch |err| {
                return .{ .Error = .{ .message = "failed to read header value", .err = err } };
            });
            if (key.len == 0 or value.len == 0) break;
            headers.append(Self.Header.init(key, value)) catch |err| {
                return .{ .Error = .{ .message = "failed to append header", .err = err } };
            };
        }

        // body
        const body = reader.readAll() catch |err| {
            return .{ .Error = .{ .message = "failed to read body", .err = err } };
        };

        // alloc headers
        const headers_slice = headers.toOwnedSlice();
        const headers_alloc = alloc.alloc(Self.Header, headers_slice.len) catch |err| {
            return .{ .Error = .{ .message = "Failed to allocate memory for headers", .err = err } };
        };
        std.mem.copy(Self.Header, headers_alloc, headers_slice);
        // alloc body
        const body_alloc = alloc.alloc(u8, body.len) catch |err| {
            return .{ .Error = .{ .message = "Failed to allocate memory for body", .err = err } };
        };
        std.mem.copy(u8, body_alloc, body);

        return .{ .Response = .{
            .alloc = alloc,
            .status_code = status_code,
            .headers = headers_alloc,
            .body = body_alloc,
        } };
    }
};

pub const Header = SimpleHtttpClient.Header;
pub const MethodStr = SimpleHtttpClient.Method;
pub const HeaderStr = SimpleHtttpClient.HeaderStr;
pub const Request = SimpleHtttpClient.Request;

test "send request" {
    const alloc = std.testing.allocator;
    const host = "httpbin.org";
    const port: u16 = 80;
    const path = "/anything";
    const method = MethodStr.GET;
    const headers = [_]Header{
        Header.init(HeaderStr.USER_AGENT.toSlice(), "Zig HTTP Client"),
        Header.init(HeaderStr.HOST.toSlice(), "httpbin.org"),
        Header.init(HeaderStr.ACCEPT_LANGUAGE.toSlice(), "en-US,en;q=0.9"),
        Header.init(HeaderStr.ACCEPT_ENCODING.toSlice(), "gzip, deflate, br"),
        Header.init(HeaderStr.CONTENT_TYPE.toSlice(), "application/json"),
        Header.init(HeaderStr.CONNECTION.toSlice(), "keep-alive"),
        Header.init(HeaderStr.ACCEPT.toSlice(), "application/json"),
    };
    const body = "Hello World";

    const request = Request.init(method, path, &headers, body);
    const response = SimpleHtttpClient.sendRequest(alloc, host, port, request);
    defer response.deinit();
    if (response == SimpleHtttpClient.RequestResult.Error) {
        std.debug.print("Error: {s} ({?})", .{ response.Error.message, response.Error.err });

        @panic("Failed to send request");
    } else {
        std.debug.print("Status Code: {d}\n", .{response.Response.status_code});
        std.debug.print("Headers: {d}\n", .{response.Response.headers.len});
        std.debug.print("Body: {s}\n", .{response.Response.body});
    }
}
