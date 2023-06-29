const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");
const lua = @import("lua");

const State = lua.State;
const allocator = luz.allocator;

pub const ThreadArgument = union(enum) {
    pub const Userdata = struct {
        block: []const u8,
        name: [:0]const u8,
        uservalue: *ThreadArgument,
    };

    nil: void,
    boolean: bool,
    integer: State.Integer,
    number: State.Number,
    string: []const u8,
    lightuserdata: ?*anyopaque,
    userdata: Userdata,
    cfunction: State.CFn,
    function: []const u8,

    pub fn pull(L: *State, arg: State.Index) !ThreadArgument {
        switch (L.typeof(arg)) {
            .none, .nil => return .nil,
            .boolean => return .{ .boolean = L.toboolean(arg) },
            .number => if (L.isinteger(arg)) {
                return .{ .integer = L.tointeger(arg) };
            } else {
                return .{ .number = L.tonumber(arg) };
            },
            .string => return .{ .string = try allocator.dupe(u8, L.tolstring(arg).?) },
            .lightuserdata => return .{ .lightuserdata = L.touserdata(anyopaque, arg) },
            .function => if (L.iscfunction(arg)) {
                return .{ .cfunction = L.tocfunction(arg) };
            } else {
                var buf = std.ArrayList(u8).init(allocator);
                var writer = lua.luaWriter(buf.writer());

                L.pushvalue(arg);
                defer L.pop(1);

                std.debug.assert(L.dump(&writer, false) == .ok);
                return .{ .function = try buf.toOwnedSlice() };
            },
            .userdata => {
                const len = L.rawlen(arg);
                const original = @as([*]u8, @ptrCast(L.touserdata(u8, arg).?))[0..len];

                const block = try allocator.dupe(u8, original);

                if (L.getmetafield(arg, "__threadsafe") != .boolean or !L.toboolean(-1))
                    L.throw("bad argument #%d (userdata is not threadsafe)", .{@as(State.Index, arg)});

                L.pop(1);

                if (L.getmetafield(arg, "__threadtransfer") == .function) {
                    L.pushvalue(arg);
                    L.call(1, 0);
                } else {
                    L.pop(1);
                }

                if (L.getmetafield(arg, "__name") != .string)
                    L.throw("bad argument #%d (userdata has no __name)", .{@as(State.Index, arg)});

                const name = try allocator.dupeZ(u8, L.tolstring(-1).?);
                L.pop(1);

                _ = L.getuservalue(arg);
                const uvalue = try allocator.create(ThreadArgument);
                uvalue.* = try ThreadArgument.pull(L, -1);
                L.pop(1);

                return .{ .userdata = .{
                    .block = block,
                    .name = name,
                    .uservalue = uvalue,
                } };
            },
            else => |typ| L.throw("bad argument #%d (cannot send '%s' to a thread)", .{ @as(State.Index, arg), @tagName(typ).ptr }),
        }
    }

    pub fn push(arg: ThreadArgument, L: *State) !void {
        switch (arg) {
            .nil => L.pushnil(),
            .boolean => |value| L.pushboolean(value),
            .integer => |value| L.pushinteger(value),
            .number => |value| L.pushnumber(value),
            .string => |value| {
                L.pushstring(value);
                allocator.free(value);
            },
            .lightuserdata => |value| L.pushlightuserdata(value),
            .userdata => |info| {
                const ud = @as([*]u8, @ptrCast(L.newuserdata(@intCast(info.block.len))))[0..info.block.len];
                @memcpy(ud, info.block);

                L.setmetatablefor(info.name);

                allocator.free(info.block);
                allocator.free(info.name);

                try info.uservalue.push(L);
                L.setuservalue(-2);

                allocator.destroy(info.uservalue);
            },
            .cfunction => |value| L.pushclosure_unwrapped(value, 0),
            .function => |value| {
                var fbs1 = std.io.fixedBufferStream(value);
                var reader1 = try lua.luaReader(fbs1.reader());

                if (L.load(&reader1, "=none", .binary) != .ok) {
                    return;
                }

                allocator.free(value);
            },
        }
    }
};

const PackageEnvironment = struct {
    path: []const u8,
    cpath: []const u8,
    preload: std.StringHashMap(State.CFn),
};

fn threadMain(bytecode: []const u8, arguments: []ThreadArgument, package: PackageEnvironment) !void {
    const L = try State.newstate();
    defer L.close();

    L.openlibs();

    {
        const scheck = lua.StackCheck.init(L);
        defer _ = scheck.check(threadMain, L, 0);
        std.debug.assert(L.getglobal("package") == .table);

        L.push(package.cpath);
        L.setfield(-2, "cpath");
        allocator.free(package.cpath);

        L.push(package.path);
        L.setfield(-2, "path");
        allocator.free(package.path);

        std.debug.assert(L.getfield(-1, "preload") == .table);

        L.pushclosure_unwrapped(luz.entrypoint, 0);
        L.setfield(-2, "luz");

        var it = package.preload.iterator();
        while (it.next()) |entry| {
            L.pushstring(entry.key_ptr.*);
            L.pushclosure_unwrapped(entry.value_ptr.*, 0);
            L.settable(-3);

            allocator.free(entry.key_ptr.*);
        }

        var preload = package.preload;
        preload.deinit();

        L.pop(2);

        if (std.c.dlsym(null, "luaopen_luv")) |luaopen_luv| {
            L.requiref("uv", @ptrCast(@alignCast(luaopen_luv)), false);
            L.pop(1);
        }

        if (std.c.dlsym(null, "luaopen_luz")) |luaopen_luz| {
            L.requiref("luz", @ptrCast(@alignCast(luaopen_luz)), false);
            L.pop(1);
        }
    }

    var fbs = std.io.fixedBufferStream(bytecode);
    var reader = try lua.luaReader(fbs.reader());

    if (L.load(&reader, "thread_main", .binary) != .ok) {
        return;
    }

    allocator.free(bytecode);

    for (arguments) |arg| try arg.push(L);
    allocator.free(arguments);

    L.call(@intCast(arguments.len), 0);
}

pub const bindings = struct {
    pub fn getCurrentId(L: *State) std.Thread.Id {
        _ = L;
        return std.Thread.getCurrentId();
    }

    pub fn getCpuCount(L: *State) !usize {
        _ = L;
        return try std.Thread.getCpuCount();
    }

    pub fn spawn(L: *State) !c_int {
        L.ensuretype(1, .function);

        const bytecode = blk: {
            L.pushvalue(1);
            defer L.pop(1);

            var bytecode_buf = std.ArrayList(u8).init(allocator);
            var writer = lua.luaWriter(bytecode_buf.writer());

            std.debug.assert(L.dump(&writer, false) == .ok);

            break :blk try bytecode_buf.toOwnedSlice();
        };

        const args = try allocator.alloc(ThreadArgument, @intCast(L.gettop() - 1));
        errdefer allocator.free(args);

        for (args, 0..) |*slot, i| {
            slot.* = try ThreadArgument.pull(L, @intCast(i + 2));
        }

        var env: PackageEnvironment = .{ .cpath = "", .path = "", .preload = std.StringHashMap(State.CFn).init(allocator) };
        if (L.getglobal("package") == .table) {
            if (L.getfield(-1, "cpath") == .string) {
                env.cpath = try allocator.dupe(u8, L.tolstring(-1).?);
            }

            L.pop(1);

            if (L.getfield(-1, "path") == .string) {
                env.path = try allocator.dupe(u8, L.tolstring(-1).?);
            }

            L.pop(1);

            if (L.getfield(-1, "preload") == .table) {
                L.pushnil();
                while (L.next(-2)) {
                    if (L.iscfunction(-1) and L.typeof(-2) == .string) {
                        const name = try allocator.dupe(u8, L.tolstring(-2).?);
                        try env.preload.put(name, L.tocfunction(-1));
                    }

                    L.pop(1);
                }
            }

            L.pop(1);
        }

        L.pop(1);

        L.resource(std.Thread).* = try std.Thread.spawn(.{}, threadMain, .{ bytecode, args, env });
        return 1;
    }

    pub fn yield(L: *State) !void {
        _ = L;
        try std.Thread.yield();
    }

    pub fn Mail(L: *State) !c_int {
        const mail = try allocator.create(ThreadMail);
        mail.* = .{};

        L.resource(*ThreadMail).* = mail;
        return 1;
    }
};

pub const resources = .{
    .{ .type = std.Thread, .metatable = Thread.metatable },
    .{ .type = *ThreadMail, .metatable = ThreadMail.metatable },
};

pub const Thread = struct {
    pub const bindings = struct {
        /// setName(self: std.Thread, name: string) !void
        pub fn setName(L: *State) !void {
            const thread = L.checkResource(std.Thread, 1);
            const name = L.check([]const u8, 2);

            try thread.setName(name);
        }

        /// getName(self: std.Thread) !string
        pub fn getName(L: *State) !c_int {
            const thread = L.checkResource(std.Thread, 1);
            var buf: [std.Thread.max_name_len:0]u8 = undefined;

            const str = try thread.getName(buf[0..]);
            L.push(str);
            return 1;
        }

        /// join(self: std.Thread) void
        pub fn join(L: *State) void {
            const thread = L.checkResource(std.Thread, 1);

            L.pushboolean(true);
            L.setuservalue(1);

            thread.join();
        }
    };

    pub const metatable = struct {
        pub const __index = Thread.bindings;

        pub fn __gc(L: *State) void {
            const thread = L.checkResource(std.Thread, 1);

            // TODO: This is unsafe, a still running thread *MAY* remain alive even after the lua state closes.
            // Which is undefined behavior. (dlclose is called on our library)
            if (L.getuservalue(1) != .boolean or !L.toboolean(-1))
                thread.detach();

            L.pop(1);
        }
    };
};

pub const ThreadMail = struct {
    args: []ThreadArgument = &.{},
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    acknowledged: bool = false,
    available: bool = false,

    pub const bindings = struct {
        /// wait(self: *ThreadMail) ...
        pub fn wait(L: *State) !c_int {
            const mail = L.checkResource(*ThreadMail, 1).*;

            mail.mutex.lock();
            defer mail.mutex.unlock();

            while (!mail.available)
                mail.condition.wait(&mail.mutex);

            for (mail.args) |arg| try arg.push(L);

            mail.available = false;
            mail.acknowledged = true;
            mail.condition.signal();

            while (mail.acknowledged)
                mail.condition.wait(&mail.mutex);

            return @intCast(mail.args.len);
        }

        /// wait(self: *ThreadMail, timeout_ns: integer) ...
        pub fn timedWait(L: *State) !c_int {
            const mail = L.checkResource(*ThreadMail, 1).*;
            const timeout = L.check(u64, 2);

            mail.mutex.lock();
            defer mail.mutex.unlock();

            while (!mail.available)
                mail.condition.timedWait(&mail.mutex, timeout) catch {
                    mail.mutex.unlock();
                    L.throw("timed out", .{});
                };

            for (mail.args) |arg| try arg.push(L);

            mail.available = false;
            mail.acknowledged = true;
            mail.condition.signal();

            while (mail.acknowledged)
                mail.condition.wait(&mail.mutex);

            return @intCast(mail.args.len);
        }

        /// send(self: *ThreadMail, ...) void
        pub fn send(L: *State) !void {
            const mail = L.checkResource(*ThreadMail, 1).*;

            mail.mutex.lock();
            defer mail.mutex.unlock();

            mail.args = try allocator.realloc(mail.args, @intCast(L.gettop() - 1));
            for (mail.args, 0..) |*slot, i| {
                slot.* = try ThreadArgument.pull(L, @intCast(i + 2));
            }

            mail.available = true;
            mail.condition.signal();

            while (!mail.acknowledged)
                mail.condition.wait(&mail.mutex);

            mail.acknowledged = false;
            mail.condition.signal();
        }
    };

    pub const metatable = struct {
        pub const __index = ThreadMail.bindings;
        pub const __threadsafe = true;

        pub fn __gc(L: *State) void {
            defer L.pop(1);
            if (L.getuservalue(1) == .lightuserdata) {
                const ref = L.touserdata(u32, -1).?;
                ref.* -= 1;

                if (ref.* != 0) return;
            }

            const mail = L.checkResource(*ThreadMail, 1).*;

            allocator.free(mail.args);
            allocator.destroy(mail);
        }

        pub fn __threadtransfer(L: *State) !void {
            if (L.getuservalue(1) == .lightuserdata) {
                const ref = L.touserdata(u32, -1).?;
                ref.* += 1;
            } else {
                const ref = try allocator.create(u32);
                ref.* = 1 + 1;

                L.pushlightuserdata(ref);
                L.setuservalue(1);
            }

            L.pop(1);
        }
    };
};
