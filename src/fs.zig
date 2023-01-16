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

    pub const deinit = close;

    /// Closes the file. It is an error to use the file after it has been closed.
    ///
    /// File:close()
    fn close(L: *lua.lua_State) void {
        const file = lua.checkUserData(L, File, 1);

        file.fd.close();
    }

    /// Blocks until all pending file contents and metadata modifications
    /// for the file have been synchronized with the underlying filesystem.
    ///
    /// Note that this does not ensure that metadata for the
    /// directory containing the file has also reached disk.
    ///
    /// File:sync()
    fn sync(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);

        return try file.fd.sync();
    }

    /// Test whether the file refers to a terminal.
    ///
    /// File:isTty() bool
    fn isTty(L: *lua.lua_State) !bool {
        const file = lua.checkUserData(L, File, 1);

        return file.fd.isTty();
    }

    /// Test whether ANSI escape codes will be treated as such.
    ///
    /// File:supportsAnsiEscapeCodes() bool
    fn supportsAnsiEscapeCodes(L: *lua.lua_State) !bool {
        const file = lua.checkUserData(L, File, 1);

        return file.fd.supportsAnsiEscapeCodes();
    }

    /// Shrinks or expands the file.
    /// The file offset after this call is left unchanged.
    ///
    /// File:setEndPos(length: uinteger)
    ///
    /// - length: The new length of the file.
    fn setEndPos(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const length = lua.checkArg(L, u64, 2);

        return try file.fd.setEndPos(length);
    }

    /// Repositions read/write file offset relative to the current offset.
    ///
    /// File:seekBy(offset: integer)
    ///
    /// - offset: The offset to seek to. This may be negative.
    fn seekBy(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const offset = lua.checkArg(L, i64, 2);

        return try file.fd.seekBy(offset);
    }

    /// Repositions read/write file offset relative to the end.
    ///
    /// File:seekFromEnd(offset: integer)
    ///
    /// - offset: The offset to seek to. This may be negative.
    fn seekFromEnd(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const offset = lua.checkArg(L, i64, 2);

        return try file.fd.seekFromEnd(offset);
    }

    /// Repositions read/write file offset relative to the beginning.
    ///
    /// File:seekTo(offset: integer)
    ///
    /// - offset: The offset to seek to.
    fn seekTo(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const offset = lua.checkArg(L, u64, 2);

        return try file.fd.seekTo(offset);
    }

    /// Returns the current read/write file offset.
    ///
    /// File:getPos() uinteger
    fn getPos(L: *lua.lua_State) !u64 {
        const file = lua.checkUserData(L, File, 1);

        return try file.fd.getPos();
    }

    /// Returns the size of the file.
    ///
    /// File:getEndPos() uinteger
    fn getEndPos(L: *lua.lua_State) !u64 {
        const file = lua.checkUserData(L, File, 1);

        return try file.fd.getEndPos();
    }

    /// Returns the mode of the file. This is always zero on windows.
    ///
    /// File:mode() uinteger
    fn mode(L: *lua.lua_State) !std.os.mode_t {
        const file = lua.checkUserData(L, File, 1);

        return try file.fd.mode();
    }

    /// Returns information about a file.
    ///
    /// File:stat() table
    fn stat(L: *lua.lua_State) !c_int {
        const file = lua.checkUserData(L, File, 1);

        const stat_data = try file.fd.stat();

        lua.lua_createtable(L, 0, 7);
        lua.push(L, stat_data.inode);
        lua.lua_setfield(L, -2, "inode");
        lua.push(L, stat_data.size);
        lua.lua_setfield(L, -2, "size");
        lua.push(L, stat_data.mode);
        lua.lua_setfield(L, -2, "mode");
        lua.push(L, stat_data.kind);
        lua.lua_setfield(L, -2, "kind");
        lua.push(L, stat_data.atime);
        lua.lua_setfield(L, -2, "atime");
        lua.push(L, stat_data.mtime);
        lua.lua_setfield(L, -2, "mtime");
        lua.push(L, stat_data.ctime);
        lua.lua_setfield(L, -2, "ctime");

        return 1;
    }

    /// Changes the mode of the file.
    /// The process must have the correct privileges in order to do this
    /// successfully, or must have the effective user ID matching the owner
    /// of the file.
    ///
    /// File:chmod(mode: uinteger)
    ///
    /// - mode: The new mode of the file.
    fn chmod(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const mode_int = lua.checkArg(L, std.os.mode_t, 2);

        return try file.fd.chmod(mode_int);
    }

    /// Changes the owner and group of the file.
    /// The process must have the correct privileges in order to do this
    /// successfully. The group may be changed by the owner of the file to
    /// any group of which the owner is a member.
    ///
    /// File:chown(uid: ?integer, gid: ?integer)
    ///
    /// - uid: The new user ID. If `nil`, the user ID is not changed.
    /// - gid: The new group ID. If `nil`, the group ID is not changed.
    fn chown(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const uid = lua.checkArg(L, ?std.os.uid_t, 2);
        const gid = lua.checkArg(L, ?std.os.gid_t, 3);

        return try file.fd.chown(uid, gid);
    }

    // TODO: setPermissions
    // TODO: metadata

    /// The underlying file system may have a different granularity than nanoseconds,
    /// and therefore this function cannot guarantee any precision will be stored.
    /// Further, the maximum value is limited by the system ABI. When a value is provided
    /// that exceeds this range, the value is clamped to the maximum.
    ///
    /// File:updateTimes(atime: integer, mtime: integer)
    ///
    /// - atime: The new access time.
    /// - mtime: The new modification time.
    fn updateTimes(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const atime = lua.checkArg(L, i128, 2);
        const mtime = lua.checkArg(L, i128, 3);

        return try file.fd.updateTimes(atime, mtime);
    }

    /// Reads data from the file. May do a partial read.
    ///
    /// File:read(len: uinteger?) string
    ///
    /// - len: The number of bytes to read. If not specified, will read up to 4096 bytes.
    fn read(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;
        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;

        const nread = try file.fd.read(buf[0..len]);
        return buf[0..nread];
    }

    /// Reads data from the file. Will never do a partial read.
    ///
    /// File:readAll(len: uinteger?) string
    ///
    /// - len: The number of bytes to read. If not specified, will read up to 4096 bytes.
    fn readAll(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;

        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;

        const nread = try file.fd.readAll(buf[0..len]);
        return buf[0..nread];
    }

    /// Reads data from the file. May do a partial read.
    ///
    /// File:pread(len: uinteger?, offset: uinteger) string
    ///
    /// - len: The number of bytes to read. If not specified, will read up to 4096 bytes.
    /// - offset: The offset to read from.
    fn pread(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;
        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;
        const offset = lua.checkArg(L, u64, 3);

        const nread = try file.fd.pread(buf[0..len], offset);
        return buf[0..nread];
    }

    /// Reads data from the file. Will never do a partial read.
    ///
    /// File:preadAll(len: uinteger?, offset: uinteger) string
    ///
    /// - len: The number of bytes to read. If not specified, will read up to 4096 bytes.
    /// - offset: The offset to read from.
    fn preadAll(L: *lua.lua_State) ![]const u8 {
        var buf: [4096]u8 = undefined;

        const file = lua.checkUserData(L, File, 1);
        const len = lua.checkArg(L, ?usize, 2) orelse buf.len;
        const offset = lua.checkArg(L, u64, 3);

        const nread = try file.fd.preadAll(buf[0..len], offset);
        return buf[0..nread];
    }

    /// Writes data to the file. May do a partial write.
    ///
    /// File:write(data: string) uinteger
    ///
    /// - data: The data to write to the file.
    ///
    /// Returns the number of bytes written.
    fn write(L: *lua.lua_State) !usize {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);

        return try file.fd.write(data);
    }

    /// Writes data to the file. Will never do a partial write.
    ///
    /// File:write(data: string)
    ///
    /// - data: The data to write to the file.
    fn writeAll(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);

        return try file.fd.writeAll(data);
    }

    /// Writes data to the file. May do a partial write.
    ///
    /// File:pwrite(data: string, offset: uinteger) uinteger
    ///
    /// - data: The data to write to the file.
    /// - offset: The offset to write to.
    ///
    /// Returns the number of bytes written.
    fn pwrite(L: *lua.lua_State) !usize {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);
        const offset = lua.checkArg(L, u64, 3);

        return try file.fd.pwrite(data, offset);
    }

    /// Writes data to the file. Will never do a partial write.
    ///
    /// File:pwrite(data: string, offset: uinteger)
    ///
    /// - data: The data to write to the file.
    /// - offset: The offset to write to.
    fn pwriteAll(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const data = lua.checkArg(L, []const u8, 2);
        const offset = lua.checkArg(L, u64, 3);

        return try file.fd.pwriteAll(data, offset);
    }

    /// Copies data from one file to another. May do a partial copy
    ///
    /// File:copyRange(src_offset: uinteger, dest: File, dest_offset: uinteger, len: uinteger) uinteger
    ///
    /// - src_offset: The offset to copy from.
    /// - dest: The destination file.
    /// - dest_offset: The offset to copy to.
    /// - len: The number of bytes to copy.
    ///
    /// Returns the number of bytes copied.
    fn copyRange(L: *lua.lua_State) !u64 {
        const file = lua.checkUserData(L, File, 1);
        const src_offset = lua.checkArg(L, u64, 2);
        const dest = lua.checkUserData(L, File, 3);
        const dest_offset = lua.checkArg(L, u64, 4);
        const len = lua.checkArg(L, u64, 5);

        return try file.fd.copyRange(src_offset, dest.fd, dest_offset, len);
    }

    /// Copies data from one file to another. Will never do a partial copy.
    ///
    /// File:copyRangeAll(src_offset: uinteger, dest: File, dest_offset: uinteger, len: uinteger)
    ///
    /// - src_offset: The offset to copy from.
    /// - dest: The destination file.
    /// - dest_offset: The offset to copy to.
    /// - len: The number of bytes to copy.
    ///
    /// Returns the number of bytes copied.
    fn copyRangeAll(L: *lua.lua_State) !u64 {
        const file = lua.checkUserData(L, File, 1);
        const src_offset = lua.checkArg(L, u64, 2);
        const dest = lua.checkUserData(L, File, 3);
        const dest_offset = lua.checkArg(L, u64, 4);
        const len = lua.checkArg(L, u64, 5);

        return try file.fd.copyRangeAll(src_offset, dest.fd, dest_offset, len);
    }

    // TODO: writeFileAll (sendfile)
    // TODO: writeFileAllUnseekable

    // TODO: reader
    // TODO: writer
    // TODO seekableStream

    /// Blocks when an incompatible lock is held by another process.
    /// A process may hold only one type of lock (shared or exclusive) on
    /// a file. When a process terminates in any way, the lock is released.
    ///
    /// File:lock(exclusive: boolean)
    fn lock(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);
        const exclusive = lua.checkArg(L, bool, 2);

        return try file.fd.lock(if (exclusive) .Exclusive else .Shared);
    }

    /// Releases a lock held by the process.
    ///
    /// File:unlock()
    fn unlock(L: *lua.lua_State) void {
        const file = lua.checkUserData(L, File, 1);

        return file.fd.unlock();
    }

    /// Attempts to acquire a lock without blocking.
    ///
    /// File:tryLock(exclusive: boolean) boolean
    ///
    /// Returns true if the lock was acquired, false otherwise.
    fn tryLock(L: *lua.lua_State) !bool {
        const file = lua.checkUserData(L, File, 1);
        const exclusive = lua.checkArg(L, bool, 2);

        return try file.fd.tryLock(if (exclusive) .Exclusive else .Shared);
    }

    /// Assumes the file is already locked in exclusive mode.
    /// This modifies the lock to be shared without releasing it.
    ///
    /// File:downgradeLock()
    fn downgradeLock(L: *lua.lua_State) !void {
        const file = lua.checkUserData(L, File, 1);

        return try file.fd.downgradeLock();
    }

    const fns = .{
        .{ .name = "close", .func = close },
        .{ .name = "sync", .func = sync },
        .{ .name = "isTty", .func = isTty },
        .{ .name = "supportsAnsiEscapeCodes", .func = supportsAnsiEscapeCodes },
        .{ .name = "setEndPos", .func = setEndPos },
        .{ .name = "seekBy", .func = seekBy },
        .{ .name = "seekFromEnd", .func = seekFromEnd },
        .{ .name = "seekTo", .func = seekTo },
        .{ .name = "getPos", .func = getPos },
        .{ .name = "getEndPos", .func = getEndPos },
        .{ .name = "mode", .func = mode },
        .{ .name = "stat", .func = stat },
        .{ .name = "chmod", .func = chmod },
        .{ .name = "chown", .func = chown },
        .{ .name = "updateTimes", .func = updateTimes },
        .{ .name = "read", .func = read },
        .{ .name = "readAll", .func = readAll },
        .{ .name = "pread", .func = pread },
        .{ .name = "preadAll", .func = preadAll },
        .{ .name = "write", .func = write },
        .{ .name = "writeAll", .func = writeAll },
        .{ .name = "pwrite", .func = pwrite },
        .{ .name = "pwriteAll", .func = pwriteAll },
        .{ .name = "copyRange", .func = copyRange },
        .{ .name = "copyRangeAll", .func = copyRangeAll },
        .{ .name = "lock", .func = lock },
        .{ .name = "unlock", .func = unlock },
        .{ .name = "tryLock", .func = tryLock },
        .{ .name = "downgradeLock", .func = downgradeLock },
    };
};
