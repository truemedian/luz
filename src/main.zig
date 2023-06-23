const std = @import("std");
const lua = @import("lua");

pub const State = lua.State;

pub var luz_has_init: bool = false;
pub const allocator = std.heap.c_allocator;

pub const libraries = struct {
    pub const os = @import("lib/os.zig");
    pub const process = @import("lib/process.zig");
    pub const time = @import("lib/time.zig");
};

pub const bindings = struct {
    pub const os = libraries.os.bindings;
    pub const process = libraries.process.bindings;
    pub const time = libraries.time.bindings;
};

pub const resources = struct {
    pub const os = libraries.os.resources;
    pub const process = libraries.process.resources;
    pub const time = libraries.time.resources;
};


export fn luz_setup(
    c_argc: c_int,
    c_argv: [*][*:0]c_char,
    c_envp: [*:null]?[*:0]c_char,
    handle_segfault: c_int,
    handle_sigpipe: c_int,
) void {
    var env_count: usize = 0;
    while (c_envp[env_count] != null) : (env_count += 1) {}

    std.os.argv = @ptrCast([*][*:0]u8, c_argv)[0..@intCast(usize, c_argc)];
    std.os.environ = @ptrCast([*][*:0]u8, c_envp)[0..env_count];

    if (handle_segfault != 0) {
        std.debug.maybeEnableSegfaultHandler();
    }

    if (handle_sigpipe != 0) {
        std.os.maybeIgnoreSigpipe();
    }

    luz_has_init = true;
}

fn luzopen_luz(L: *lua.State) c_int {
    inline for (comptime std.meta.declarations(resources)) |decl| {
        inline for (@field(resources, decl.name)) |resource| {
            L.registerResource(resource.type, resource.metatable);
        }
    }

    L.push(bindings);
    return 1;
}

comptime {
    lua.exportAs(luzopen_luz, "luz");
}
