const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");
const lua = @import("lua");

const State = lua.State;
const allocator = luz.allocator;

pub const bindings = struct {
    pub fn cwd(L: *State) !c_int {
        const str = try std.process.getCwdAlloc(allocator);
        defer allocator.free(str);

        L.push(str);
        return 1;
    }

    pub fn env(L: *State) !c_int {
        var map = try std.process.getEnvMap(allocator);
        defer map.deinit();

        L.createtable(0, @intCast(map.count()));

        var it = map.iterator();
        while (it.next()) |entry| {
            L.push(entry.key_ptr.*);
            L.push(entry.value_ptr.*);
            L.settable(-3);
        }

        return 1;
    }

    pub fn args(L: *State) !c_int {
        if (!luz.luz_has_init) {
            L.pusherror(error.NotInitialized);
            return 2;
        }

        L.push(std.os.argv);
        return 1;
    }
};

pub const resources = .{};
