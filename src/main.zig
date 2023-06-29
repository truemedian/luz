const std = @import("std");
pub const lua = @import("lua");

pub var luz_has_init: bool = false;
pub const allocator = std.heap.c_allocator;

pub const libraries = struct {
    pub const base64 = @import("lib/base64.zig");
    pub const os = @import("lib/os.zig");
    pub const process = @import("lib/process.zig");
    pub const rand = @import("lib/rand.zig");
    pub const Thread = @import("lib/Thread.zig");
    pub const time = @import("lib/time.zig");
};

export fn luz_setup(
    c_argc: c_int,
    c_argv: [*][*:0]c_char,
    handle_segfault: c_int,
    handle_sigpipe: c_int,
) void {
    std.os.argv = @as([*][*:0]u8, @ptrCast(c_argv))[0..@intCast(c_argc)];

    if (handle_segfault != 0) {
        std.debug.maybeEnableSegfaultHandler();
    }

    if (handle_sigpipe != 0) {
        std.os.maybeIgnoreSigpipe();
    }

    luz_has_init = true;
}

fn luzopen_luz(L: *lua.State) c_int {
    const libraries_list = @typeInfo(libraries).Struct.decls;

    inline for (libraries_list) |decl| {
        inline for (@field(libraries, decl.name).resources) |resource| {
            L.registerResource(resource.type, resource.metatable);
        }
    }

    L.createtable(0, libraries_list.len);
    inline for (libraries_list) |decl| {
        L.push(@field(libraries, decl.name).bindings);
        L.setfield(-2, decl.name ++ "\x00");
    }

    return 1;
}

pub const entrypoint = lua.exportAs(luzopen_luz, "luz");
comptime {
    _ = entrypoint;
}
