const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");

const State = luz.lua.State;
const allocator = luz.allocator;

pub const bindings = struct {
    pub fn getrandom(L: *State) !c_int {
        const len = L.check(usize, 1);

        const buf = try allocator.alloc(u8, len);
        defer allocator.free(buf);

        try std.os.getrandom(buf[0..]);

        L.push(buf[0..]);
        return 1;
    }

    pub fn kill(L: *State) !void {
        const pid = L.check(std.os.pid_t, 1);
        const sig = L.check(?u8, 2) orelse std.os.SIG.INT;

        try std.os.kill(pid, sig);
    }

    pub fn chdir(L: *State) !void {
        const path = L.check([]const u8, 1);
        try std.os.chdir(path);
    }

    pub fn setuid(L: *State) !void {
        const uid = L.check(std.os.uid_t, 1);
        try std.os.setuid(uid);
    }

    pub fn seteuid(L: *State) !void {
        const uid = L.check(std.os.uid_t, 1);
        try std.os.seteuid(uid);
    }

    pub fn setreid(L: *State) !void {
        const ruid = L.check(std.os.uid_t, 1);
        const euid = L.check(std.os.uid_t, 2);
        try std.os.setreuid(ruid, euid);
    }

    pub fn setgid(L: *State) !void {
        const gid = L.check(std.os.gid_t, 1);
        try std.os.setgid(gid);
    }

    pub fn setegid(L: *State) !void {
        const gid = L.check(std.os.gid_t, 1);
        try std.os.setegid(gid);
    }

    pub fn setregid(L: *State) !void {
        const rgid = L.check(std.os.gid_t, 1);
        const egid = L.check(std.os.gid_t, 2);
        try std.os.setregid(rgid, egid);
    }

    pub fn clock_gettime(L: *State) !c_int {
        const clk_id = L.check(i32, 1);

        var tp: std.os.timespec = undefined;
        try std.os.clock_gettime(clk_id, &tp);

        L.push(tp.tv_sec);
        L.push(tp.tv_nsec);
        return 2;
    }

    pub fn gethostname(L: *State) !c_int {
        var buf: [std.os.HOST_NAME_MAX]u8 = undefined;
        const str = try std.os.gethostname(buf[0..]);

        L.push(str);
        return 1;
    }

    pub fn getrlimit(L: *State) !c_int {
        const resource = L.check(std.os.rlimit_resource, 1);

        const limit = try std.os.getrlimit(resource);
        L.push(limit);
        return 1;
    }

    pub fn setrlimit(L: *State) !void {
        const resource = L.check(std.os.rlimit_resource, 1);
        const limit = L.check(std.os.rlimit, 2);

        try std.os.setrlimit(resource, limit);
    }
};

pub const resources = .{};