const std = @import("std");
const builtin = @import("builtin");

const ERROR_SUCCESS = 0;
const DWORD = std.os.windows.DWORD;
const HKEY = std.os.windows.HKEY;
const BYTE = std.os.windows.BYTE;
const KEY_READ = std.os.windows.KEY_READ;
const Win32Error = std.os.windows.Win32Error;

pub const CodePageIdentifier = enum(c_uint) {
    utf8 = 65001,
    unknown = 0,
};

pub fn GetConsoleOutputCP() c_uint {
    if (builtin.os.tag != .windows) {
        @compileError("windowsHasChcp65001 is only implemented for Windows");
    }
    const chcp = std.os.windows.kernel32.GetConsoleOutputCP();
    return chcp;
}

pub fn IsConsoleOutputCP(code_page: CodePageIdentifier) bool {
    if (builtin.os.tag != .windows) {
        @compileError("windowsHasChcp65001 is only implemented for Windows");
    }
    const chcp = GetConsoleOutputCP();
    return chcp == @enumToInt(code_page);
}

const SET_CONSOLE_OUTPUT_CP_FAILURE = 0;

pub fn SetConsoleOutputCP(code_page: CodePageIdentifier) bool {
    return SetConsoleOutputCPImpl(@enumToInt(code_page));
}

fn SetConsoleOutputCPImpl(code_page: c_uint) bool {
    if (builtin.os.tag != .windows) {
        @compileError("windowsSetChcp65001 is only implemented for Windows");
    }
    return std.os.windows.kernel32.SetConsoleOutputCP(code_page) != SET_CONSOLE_OUTPUT_CP_FAILURE;
}

pub fn isDeveloperModeEnabled() bool {
    if (builtin.os.tag != .windows) {
        @compileError("isDeveloperModeEnabled is only implemented for Windows");
    }
    // read from the registry to see if developer mode is enabled
    // first create the key
    var key: std.os.windows.HKEY = undefined;
    const appModelUnlock = comptime std.unicode.utf8ToUtf16LeStringLiteral(
        \\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock
    );
    std.log.debug("Opening key {}", .{std.unicode.fmtUtf16le(appModelUnlock)});
    const result = std.os.windows.kernel32.RegOpenKeyExW(
        std.os.windows.HKEY_LOCAL_MACHINE,
        appModelUnlock,
        0,
        std.os.windows.KEY_READ,
        &key,
    );
    if (result != 0) {
        std.log.debug("RegOpenKeyExW failed with error code {d}", .{result});
        return false;
    }
    const lpValueName = comptime std.unicode.utf8ToUtf16LeStringLiteral("AllowDevelopmentWithoutDevLicense");
    std.log.debug("Reading {}", .{std.unicode.fmtUtf16le(lpValueName)});

    var lpData: DWORD = undefined;
    var lpcbData: DWORD = @sizeOf(DWORD);
    const result2 = std.os.windows.advapi32.RegQueryValueExW(
        key,
        lpValueName,
        null,
        null,
        @ptrCast(*BYTE, &lpData),
        &lpcbData,
    );
    if (result2 != ERROR_SUCCESS) {
        std.log.debug("RegQueryValueExW failed with error code {d}", .{result2});
        return false;
    }
    return lpData == 1;
}

const testing = std.testing;

test "isDeveloperModeEnabled" {
    if (builtin.os.tag != .windows) {
        return;
    }
    const result = isDeveloperModeEnabled();
    std.log.debug("isDeveloperModeEnabled returned {}", .{result});
}

test "ConsoleOutputCP" {
    if (builtin.os.tag != .windows) {
        return;
    }
    const cp1 = GetConsoleOutputCP();
    std.log.debug("GetConsoleOutputCP returned {}", .{cp1});
    const result = SetConsoleOutputCP(.utf8);
    try testing.expect(result);
    const cp2 = GetConsoleOutputCP();
    std.log.debug("GetConsoleOutputCP returned {}", .{cp2});
    try testing.expect(cp2 == @enumToInt(CodePageIdentifier.utf8));

    // set an invalid code page
    const resul3 = SetConsoleOutputCPImpl(0);
    try testing.expect(!resul3);
    const errorCode = std.os.windows.kernel32.GetLastError();
    try testing.expectEqual(errorCode, Win32Error.INVALID_PARAMETER);
    std.debug.print("SetConsoleOutputCP failed with error code {s}\n", .{@tagName(errorCode)});

    // set it back to the original code page
    const result3 = SetConsoleOutputCP(.utf8);
    try testing.expect(result3);
}
