const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");

const State = luz.State;
const allocator = luz.allocator;

pub const bindings = struct {
    pub fn cwd(L: *State) !c_int {
        const str = try std.process.getCwdAlloc(allocator);
        defer allocator.free(str);

        L.push(str);
        return 1;
    }

    pub fn env(L: *State) !c_int {
        if (!luz.luz_has_init) {
            L.pusherror(error.NotInitialized);
            return 2;
        }

        var map = try std.process.getEnvMap(allocator);
        defer map.deinit();

        L.createtable(0, map.count());

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

        const list = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, list);

        L.createtable(@intCast(State.Size, list.len), 0);
        for (list, 0..) |item, i| {
            L.push(item);
            L.rawseti(-2, i + 1);
        }

        return 1;
    }
};

pub const resources = .{};
