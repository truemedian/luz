const std = @import("std");
const luz = @import("main.zig");

const assert = std.debug.assert;

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
});

pub usingnamespace c;

/// Registers a new userdata type for use in this library.
/// Associates the provided type with a metatable under the given name.
/// __gc is automatically mapped to T.deinit.
/// `register` is called with the metatable at the top of the stack.
pub fn registerUserData(L: *c.lua_State, comptime T: type, comptime name: []const u8) void {
    _ = c.luaL_newmetatable(L, "luz_" ++ name);

    push(L, T.deinit);
    c.lua_setfield(L, -2, "__gc");

    T.register(L);

    c.lua_pop(L, 1);
}

pub fn newUserData(L: *c.lua_State, comptime T: type) *T {
    const name = comptime blk: {
        for (luz.userdata) |ud| {
            if (T == ud.type) break :blk ud.name;
        }

        @compileError(@typeName(T) ++ " is not a registered userdata type");
    };

    const ptr = c.lua_newuserdata(L, @sizeOf(T));
    assert(ptr != null);

    _ = c.lua_getfield(L, c.LUA_REGISTRYINDEX, "luz_" ++ name);
    _ = c.lua_setmetatable(L, -2);

    return @ptrCast(*T, @alignCast(@alignOf(T), ptr.?));
}

pub inline fn push(L: *c.lua_State, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Void, .Null => c.lua_pushnil(L),
        .Bool => c.lua_pushboolean(L, @boolToInt(value)),
        .Int => c.lua_pushinteger(L, @intCast(c.lua_Integer, value)),
        .ComptimeInt => c.lua_pushinteger(L, value),
        .Float => c.lua_pushnumber(L, @floatCast(c.lua_Number, value)),
        .ComptimeFloat => c.lua_pushnumber(L, value),
        .Fn => c.lua_pushcclosure(L, wrap(value), 0),
        .Pointer => |info| {
            if (info.size != .Slice) @compileError("unable to coerce from type '" ++ @typeName(T) ++ "'");
            if (info.child != u8) @compileError("unable to coerce from type '" ++ @typeName(T) ++ "'");

            _ = c.lua_pushlstring(L, value.ptr, value.len);
        },
        .Optional => if (value) |unwrapped| {
            push(L, unwrapped);
        } else {
            push(L, null);
        },
        else => @compileError("unable to coerce from type '" ++ @typeName(T) ++ "'"),
    }
}

pub inline fn checkArg(L: *c.lua_State, comptime T: type, idx: c_int) T {
    switch (@typeInfo(T)) {
        .Bool => c.lua_toboolean(L, idx) != 0,
        .Int => return std.math.cast(T, c.luaL_checkinteger(L, idx)) orelse {
            _ = c.luaL_argerror(L, idx, "out of range");
            unreachable;
        },
        .Float => return @floatCast(T, c.luaL_checknumber(L, idx)),
        .Pointer => {
            if (T != []const u8) @compileError("unable to coerce from type '" ++ @typeName(T) ++ "'");

            var len: usize = undefined;
            const ptr = c.luaL_checklstring(L, idx, &len);
            return ptr[0..len];
        },
        .Optional => |info| if (c.lua_isnoneornil(L, idx)) {
            return null;
        } else {
            return checkArg(L, info.child, idx);
        },
        else => @compileError("unable to coerce from type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn checkUserData(L: *c.lua_State, comptime T: type, idx: c_int) *T {
    const name = comptime blk: {
        for (luz.userdata) |ud| {
            if (T == ud.type) break :blk ud.name;
        }

        @compileError(@typeName(T) ++ " is not a registered userdata type");
    };

    const ptr = c.luaL_checkudata(L, idx, "luz_" ++ name);
    assert(ptr != null);

    return @ptrCast(*T, @alignCast(@alignOf(T), ptr.?));
}

/// Creates a table using a list of functions and sub-tables
pub fn newLibrary(L: *c.lua_State, lib: anytype) void {
    c.lua_createtable(L, 0, lib.len);
    inline for (lib) |field| {
        _ = c.lua_pushlstring(L, field.name, field.name.len);

        if (@hasField(@TypeOf(field), "table")) {
            newLibrary(L, field.table);
        } else {
            c.lua_pushcclosure(L, wrap(field.func), 0);
        }

        c.lua_rawset(L, -3);
    }
}

pub fn recatch(L: *c.lua_State, err: anyerror) c_int {
    const name = @errorName(err);

    c.lua_pushnil(L);
    _ = c.lua_pushlstring(L, name.ptr, name.len);

    return 2;
}

pub fn wrap(comptime func: anytype) c.lua_CFunction {
    return struct {
        fn wrapped(L_opt: ?*c.lua_State) callconv(.C) c_int {
            const L = L_opt.?;

            const result = @call(.always_inline, func, .{L});

            const T = @TypeOf(result);
            if (T == c_int) return result;

            switch (@typeInfo(T)) {
                .Void => return 0,
                .ErrorUnion => |info| {
                    const actual_result = result catch |err| {
                        const name = @errorName(err);

                        c.lua_pushnil(L);
                        _ = c.lua_pushlstring(L, name.ptr, name.len);

                        return 2;
                    };

                    if (info.payload == c_int) return actual_result;

                    push(L, actual_result);
                    return 1;
                },
                else => {
                    push(L, result);
                    return 1;
                },
            }
        }
    }.wrapped;
}
