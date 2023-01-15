const std = @import("std");

const luz = @import("main.zig");
const lua = luz.lua;

/// Opens an existing file for reading. This will error if the file does not exist.
///
/// open(path: string, flags: string?)
///
/// - path: The path to the file to open. This may be relative to the current working directory.
/// - flags: A string of flags to use when opening the file. The following flags are supported:
///     - "r": Only allow reading from the file. (this is the default)
///     - "w": Only allow writing to the file.
///     - "+": Allow reading and writing to the file.
///     - "s": Obtain a shared lock for the file. Other processes may obtain a shared lock on the file.
///     - "l": Obtain an exclusive lock for the file. Other processes may not obtain a lock on the file.
///
/// Returns a File userdata.
pub fn open(L: *lua.lua_State) !c_int {
    const path = lua.checkArg(L, []const u8, 1);
    const mode_str = lua.checkArg(L, ?[]const u8, 2) orelse "";

    var flags = std.fs.File.OpenFlags{};

    if (std.mem.indexOfScalar(u8, mode_str, 'r') != null) flags.mode = .read_only;
    if (std.mem.indexOfScalar(u8, mode_str, 'w') != null) flags.mode = .write_only;
    if (std.mem.indexOfScalar(u8, mode_str, '+') != null) flags.mode = .read_write;
    if (std.mem.indexOfScalar(u8, mode_str, 's') != null) flags.lock = .Shared;
    if (std.mem.indexOfScalar(u8, mode_str, 'l') != null) flags.lock = .Exclusive;

    const fd = try std.fs.cwd().openFile(path, flags);

    const file = lua.newUserData(L, File);
    file.fd = fd;

    return 1;
}

/// Opens a file for writing. This will create the file if it does not exist.
///
/// create(path: string, flags: string?)
///
/// - path: The path to the file to open. This may be relative to the current working directory.
/// - flags: A string of flags to use when opening the file. The following flags are supported:
///     - "r": Allow reading from the file.
///     - "a": Append to the file instead of truncating it.
///     - "x": Cause an error if the file already exists.
///     - "s": Obtain a shared lock for the file. Other processes may obtain a shared lock on the file.
///     - "l": Obtain an exclusive lock for the file. Other processes may not obtain a lock on the file.
///
/// Returns a File userdata.
pub fn create(L: *lua.lua_State) !c_int {
    const path = lua.checkArg(L, []const u8, 1);
    const flags_str = lua.checkArg(L, ?[]const u8, 2) orelse "";

    var flags = std.fs.File.CreateFlags{};

    if (std.mem.indexOfScalar(u8, flags_str, 'r') != null) flags.read = true;
    if (std.mem.indexOfScalar(u8, flags_str, 'a') != null) flags.truncate = false;
    if (std.mem.indexOfScalar(u8, flags_str, 'x') != null) flags.exclusive = true;
    if (std.mem.indexOfScalar(u8, flags_str, 's') != null) flags.lock = .Shared;
    if (std.mem.indexOfScalar(u8, flags_str, 'l') != null) flags.lock = .Exclusive;

    const fd = try std.fs.cwd().createFile(path, flags);

    const file = lua.newUserData(L, File);
    file.fd = fd;

    return 1;
}

pub const library = .{
    .{ .name = "open", .func = open },
    .{ .name = "create", .func = create },
};

pub const File = struct {
    fd: std.fs.File,

    pub fn register(L: *lua.lua_State) void {
        lua.newLibrary(L, fns);
        lua.lua_setfield(L, -2, "__index");
    }

    pub fn deinit(L: *lua.lua_State) void {
        const file = lua.checkUserData(L, File, -1);

        file.fd.close();
    }

    /// Writes data to the file. May do a partial write.
    ///
    /// File:write(data: string) number
    ///
    /// - data: The data to write to the file.
    ///
    /// Returns the number of bytes written.
    fn write(L: *lua.lua_State) !usize {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);

        return try file.fd.write(data);
    }

    fn writeAll(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);

        return try file.fd.writeAll(data);
    }

    fn read(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;

        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;

        const nread = try file.fd.read(buf[0..len]);
        return buf[0..nread];
    }

    fn readAll(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;

        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;

        const nread = try file.fd.readAll(buf[0..len]);
        return buf[0..nread];
    }

    fn seekTo(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const offset = lua.checkArg(L, u64, 2);

        try file.fd.seekTo(offset);
    }

    fn seekBy(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const offset = lua.checkArg(L, i64, 2);

        try file.fd.seekBy(offset);
    }

    const fns = .{
        .{ .name = "write", .func = write },
        .{ .name = "writeAll", .func = writeAll },
        .{ .name = "read", .func = read },
        .{ .name = "readAll", .func = readAll },
        .{ .name = "seekTo", .func = seekTo },
        .{ .name = "seekBy", .func = seekBy },
    };
};
