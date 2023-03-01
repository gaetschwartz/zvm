const std = @import("std");
const builtin = @import("builtin");

const ERROR_SUCCESS = 0;
const DWORD = std.os.windows.DWORD;
const HKEY = std.os.windows.HKEY;
const BYTE = std.os.windows.BYTE;
const KEY_READ = std.os.windows.KEY_READ;
const Win32Error = std.os.windows.Win32Error;
pub const HKEY_LOCAL_MACHINE = std.os.windows.HKEY_LOCAL_MACHINE;
const TRUE = std.os.windows.TRUE;
const FALSE = std.os.windows.FALSE;

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
    return ReadValueSimple(
        HKEY_LOCAL_MACHINE,
        .REG_DWORD,
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AppModelUnlock\\AllowDevelopmentWithoutDevLicense",
    ) catch |err| {
        std.log.debug("ReadRegistryValue failed with {s}", .{@errorName(err)});
        return false;
    } == TRUE;
}

pub const RegisteryValueType = enum {
    REG_BINARY,
    REG_DWORD,
    REG_DWORD_LITTLE_ENDIAN,
    REG_DWORD_BIG_ENDIAN,
    REG_EXPAND_SZ,
    REG_LINK,
    REG_MULTI_SZ,
    REG_SZ,
    REG_QWORD,
    REG_QWORD_LITTLE_ENDIAN,
    REG_NONE,
};

fn registeryValueTypeToType(comptime valueType: RegisteryValueType, comptime wide: bool) type {
    return switch (valueType) {
        .REG_BINARY => [*]const u8,
        .REG_DWORD => std.os.windows.DWORD,
        .REG_DWORD_LITTLE_ENDIAN => std.os.windows.DWORD,
        .REG_DWORD_BIG_ENDIAN => std.os.windows.DWORD,
        .REG_EXPAND_SZ => if (wide) std.os.windows.LPWSTR else std.os.windows.LPSTR,
        .REG_LINK => if (wide) std.os.windows.LPWSTR else std.os.windows.LPSTR,
        .REG_MULTI_SZ => if (wide) std.os.windows.LPWSTR else std.os.windows.LPSTR,
        .REG_SZ => if (wide) std.os.windows.LPWSTR else std.os.windows.LPSTR,
        .REG_QWORD => std.os.windows.DWORD64,
        .REG_QWORD_LITTLE_ENDIAN => std.os.windows.DWORD64,
        .REG_NONE => std.os.windows.PVOID,
    };
}

fn regTypeW(comptime valueType: RegisteryValueType) type {
    return registeryValueTypeToType(valueType, true);
}

pub fn ReadValueSimple(hKey: HKEY, comptime valueType: RegisteryValueType, path: []const u8) ReadRegistryValueError!regTypeW(valueType) {
    if (builtin.os.tag != .windows) {
        @compileError("ReadRegistryValue is only implemented for Windows");
    }
    comptime {
        // check that its a type that doesn't need allocation
        switch (valueType) {
            .REG_BINARY, .REG_DWORD, .REG_DWORD_LITTLE_ENDIAN, .REG_DWORD_BIG_ENDIAN, .REG_QWORD, .REG_QWORD_LITTLE_ENDIAN, .REG_NONE => {},
            else => @compileError("ReadRegistryValueSimple should only be used with types that don't need allocation"),
        }
    }

    // read from the registry to see if developer mode is enabled
    // first create the key
    var key: HKEY = undefined;
    const keyDirName = std.fs.path.dirnameWindows(path).?;
    const keyDir = std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, keyDirName) catch |err| {
        std.log.debug("utf8ToUtf16LeWithNull failed with {s}", .{@errorName(err)});
        return ReadRegistryValueError.FailedToConvertToUtf8;
    };
    std.log.debug("Opening key {s}", .{keyDirName});
    const result = std.os.windows.kernel32.RegOpenKeyExW(
        hKey,
        keyDir,
        0,
        KEY_READ,
        &key,
    );
    if (result != 0) {
        std.log.debug("RegOpenKeyExW failed with error code {d}", .{result});
        return ReadRegistryValueError.RegOpenKeyExWFailed;
    }
    const keyFileName = std.fs.path.basenameWindows(path);
    const keyFile = std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, keyFileName) catch |err| {
        std.log.debug("utf8ToUtf16LeWithNull failed with {s}", .{@errorName(err)});
        return ReadRegistryValueError.FailedToConvertToUtf8;
    };
    std.log.debug("Reading {s}", .{keyFileName});

    var lpData: regTypeW(valueType) = undefined;
    var lpcbData: DWORD = @sizeOf(regTypeW(valueType));
    const result2 = std.os.windows.advapi32.RegQueryValueExW(
        key,
        keyFile,
        null,
        null,
        @ptrCast(*BYTE, &lpData),
        &lpcbData,
    );
    if (result2 != ERROR_SUCCESS) {
        std.log.debug("RegQueryValueExW failed with error code {d}", .{result2});
        return ReadRegistryValueError.RegQueryValueExWFailed;
    }
    return lpData;
}

fn regTypePtrW(comptime valueType: RegisteryValueType) type {
    return switch (valueType) {
        .REG_BINARY => [*]const u8,
        .REG_DWORD => *std.os.windows.DWORD,
        .REG_DWORD_LITTLE_ENDIAN => *std.os.windows.DWORD,
        .REG_DWORD_BIG_ENDIAN => *std.os.windows.DWORD,
        .REG_EXPAND_SZ => std.os.windows.LPWSTR,
        .REG_LINK => std.os.windows.LPWSTR,
        .REG_MULTI_SZ => std.os.windows.LPWSTR,
        .REG_SZ => std.os.windows.LPWSTR,
        .REG_QWORD => *std.os.windows.DWORD64,
        .REG_QWORD_LITTLE_ENDIAN => *std.os.windows.DWORD64,
        .REG_NONE => std.os.windows.PVOID,
    };
}

pub fn ReadValue(hKey: HKEY, comptime valueType: RegisteryValueType, ptr: regTypePtrW(valueType), len: *u32, path: []const u8) ReadRegistryValueError!void {
    if (builtin.os.tag != .windows) {
        @compileError("ReadRegistryValue is only implemented for Windows");
    }

    // read from the registry to see if developer mode is enabled
    // first create the key
    var key: HKEY = undefined;
    const keyDirName = std.fs.path.dirnameWindows(path).?;
    const keyDir = std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, keyDirName) catch |err| {
        std.log.debug("utf8ToUtf16LeWithNull failed with {s}", .{@errorName(err)});
        return ReadRegistryValueError.FailedToConvertToUtf8;
    };
    std.log.debug("Opening key {s}", .{keyDirName});
    const result = std.os.windows.kernel32.RegOpenKeyExW(
        hKey,
        keyDir,
        0,
        KEY_READ,
        &key,
    );
    if (result != 0) {
        std.log.debug("RegOpenKeyExW failed with error code {d}", .{result});
        return ReadRegistryValueError.RegOpenKeyExWFailed;
    }
    const keyFileName = std.fs.path.basenameWindows(path);
    const keyFile = std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, keyFileName) catch |err| {
        std.log.debug("utf8ToUtf16LeWithNull failed with {s}", .{@errorName(err)});
        return ReadRegistryValueError.FailedToConvertToUtf8;
    };
    std.log.debug("Reading {s}", .{keyFileName});

    comptime switch (valueType) {
        .REG_NONE => std.debug.assert(len == 0),
        // if the type is an int, we need to pass the size of the int
        .REG_DWORD, .REG_DWORD_LITTLE_ENDIAN, .REG_DWORD_BIG_ENDIAN, .REG_QWORD, .REG_QWORD_LITTLE_ENDIAN => std.debug.assert(len == @sizeOf(regTypeW(valueType))),
        // if they are strings, return the length of the string pointed to by the pointer
        .REG_SZ, .REG_EXPAND_SZ, .REG_MULTI_SZ, .REG_BINARY, .REG_LINK => {},
    };
    var lpcbData: *DWORD = len;
    std.log.debug("lpcbData is {d}", .{lpcbData.*});
    const result2 = std.os.windows.advapi32.RegQueryValueExW(
        key,
        keyFile,
        null,
        null,
        @ptrCast(*BYTE, ptr),
        lpcbData,
    );
    std.log.debug("lpcbData is now {d}", .{lpcbData.*});
    if (result2 != ERROR_SUCCESS) {
        std.log.debug("RegQueryValueExW failed with error code {d}", .{result2});
        return ReadRegistryValueError.RegQueryValueExWFailed;
    }
}

pub const ReadRegistryValueError = error{
    RegOpenKeyExWFailed,
    RegQueryValueExWFailed,
    FailedToConvertToUtf8,
};

const testing = std.testing;

test "isDeveloperModeEnabled" {
    if (builtin.os.tag != .windows) {
        return;
    }
    const result = isDeveloperModeEnabled();
    if (result) {
        std.debug.print("Developer mode is enabled\n", .{});
    } else {
        std.debug.print("Developer mode is not enabled\n", .{});
    }
}

test "ConsoleOutputCP" {
    if (builtin.os.tag != .windows) {
        return;
    }
    const cp1 = GetConsoleOutputCP();
    const result = SetConsoleOutputCP(.utf8);
    try testing.expect(result);
    const cp2 = GetConsoleOutputCP();
    try testing.expect(cp2 == @enumToInt(CodePageIdentifier.utf8));

    // set an invalid code page
    const resul3 = SetConsoleOutputCPImpl(0);
    try testing.expect(!resul3);
    const errorCode = std.os.windows.kernel32.GetLastError();
    try testing.expectEqual(errorCode, Win32Error.INVALID_PARAMETER);

    // set it back to the original code page
    const result3 = SetConsoleOutputCPImpl(cp1);
    try testing.expect(result3);
}
