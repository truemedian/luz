const std = @import("std");
pub const lua = @import("lua.zig");

const fs = @import("fs.zig");

const library = .{
    .{ .name = "fs", .table = fs.library },
};

pub const userdata = .{
    .{ .name = "File", .type = fs.File },
};

export fn luaopen_luz(L: *lua.lua_State) c_int {
    if (@hasDecl(lua, "luaL_checkversion_")) {
        lua.luaL_checkversion_(L, lua.LUA_VERSION_NUM, lua.LUAL_NUMSIZES);
    }

    lua.newLibrary(L, library);

    inline for (userdata) |ud| {
        lua.registerUserData(L, ud.type, ud.name);
    }

    return 1;
}
