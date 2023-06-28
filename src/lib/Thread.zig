const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");

const State = luz.lua.State;
const allocator = luz.allocator;

pub const ThreadArgument = union(enum) {
    pub const Userdata = struct {
        block: []const u8,
        name: [:0]const u8,
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

    pub fn pull(L: *State, arg: State.Size) !ThreadArgument {
        switch (L.typeOf(arg)) {
            .none, .nil => return .nil,
            .boolean => return .{ .boolean = L.toboolean(arg) },
            .number => if (L.isinteger(arg)) {
                return .{ .integer = L.tointeger(arg) };
            } else {
                return .{ .tonumber = L.tonumber(arg) };
            },
            .string => return .{ .string = try allocator.dupe(u8, L.tolstring(arg)) },
            .lightuserdata => return .{ .lightuserdata = L.touserdata(anyopaque, arg) },
            .function => if (L.iscfunction(arg)) {
                return .{ .cfunction = L.tocfunction(arg) };
            } else {
                var buf = luz.lua.Buffer.init(L);
                std.debug.assert(L.dump(buf, false) == .ok);
                buf.final();

                const bc = try allocator.dupe(u8, L.tolstring(-1));
                L.pop(1);

                return .{ .function = bc };
            },
            .userdata => {
                const len = L.rawlen(arg);
                const original = @ptrCast([*]u8, L.touserdata(u8, arg).?)[0..len];

                const block = try allocator.dupe(u8, original);

                if (L.getmetafield(arg, "__name") != .string)
                    L.throw("bad argument #%d (userdata has no __name)", .{@as(State.Index, arg)});

                const name = try allocator.dupeZ(u8, L.tolstring(-1));
                L.pop(1);

                return .{ .userdata = .{
                    .block = block,
                    .name = name,
                } };
            },
            else => |typ| L.throw("bad argument #%d (cannot send '%s' to a thread)", .{ @as(State.Index, arg), L.typename(typ).ptr }),
        }
    }
};

fn thread(bytecode: []const u8, arguments: []ThreadArgument) void {
    const L = luz.lua.State.newstate();
    defer L.close();

    var fbs = std.io.fixedBufferStream(bytecode);
    var reader = luz.lua.luaReader(fbs.reader());

    if (L.load(reader, "thread_main", .binary) != .ok) {
        return;
    }

    for (arguments) |arg| switch (arg) {
        .nil => L.pushnil(),
        .boolean => |value| L.pushboolean(value),
        .integer => |value| L.pushinteger(value),
        .number => |value| L.pushnumber(value),
        .string => |value| L.pushlstring(value),
        .lightuserdata => |value| L.pushlightuserdata(value),
        .userdata => |info| {
            const ud = @ptrCast([*]u8, L.newuserdata(info.block.len))[0..info.block.len];
            @memcpy(ud, info.block);

            L.setmetatableFor(info.name);
        },
        .cfunction => |value| L.pushclosure_unwrapped(value, 0),
        .function => |value| {
            var fbs1 = std.io.fixedBufferStream(value);
            var reader1 = luz.lua.luaReader(fbs1.reader());

            if (L.load(reader1, "=none", .binary) != .ok) {
                return;
            }
        },
    };

    L.call(arguments.len, 0);
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
        L.ensureType(1, .function);

        const bc = blk: {
            L.pushvalue(1);
            defer L.pop(1);

            var buf = luz.lua.Buffer.init(L);
            std.debug.assert(L.dump(buf, false) == .ok);
            buf.final();

            const str = try allocator.dupe(L.tolstring(-1));
            errdefer allocator.free(str);
            L.pop(1);

            break :blk str;
        };
        _ = bc;

        const args = allocator.alloc(ThreadArgument, L.gettop() - 1);
        errdefer allocator.free(args);

        for (args, 0..) |*slot, i| {
            slot.* = try ThreadArgument.pull(L, i + 2);
        }
    }
};

pub const resources = .{
    .{ .type = std.Thread, .metatable = Thread.metatable },
};

pub const Thread = struct {
    pub const bindings = struct {
        pub fn setName(L: *State) !void {
            const thread = L.checkResource(std.Thread, 1);
            const name = L.check([]const u8, 2);

            try thread.setName(name);
        }

        pub fn getName(L: *State) !c_int {
            const thread = L.checkResource(std.Thread, 1);
            var buf: [std.Thread.max_name_len]u8 = undefined;

            const str = try thread.getName(buf[0..]);
            L.push(str);
            return 1;
        }
    };

    pub const metatable = struct {
        pub const __index = Thread.bindings;
    };
};
