const std = @import("std");
const root = @import("root");

const assert = std.debug.assert;
const comptimePrint = std.fmt.comptimePrint;

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
});

fn literal(comptime str: []const u8) [:0]const u8 {
    return (str ++ "\x00")[0..str.len :0];
}

fn lookup(comptime field: []const u8, comptime default: anytype) @TypeOf(default) {
    if (@hasDecl(c, field)) return @field(c, field);
    return default;
}

fn luz_compat_run(L: *State, code: []const u8, nargs: State.Size) void {
    if (L.rawgetp(State.REGISTRYINDEX, code) != .function) {
        L.pop(1);
        assert(L.loadstring(code, "=none", .either) == .ok);

        L.pushvalue(-1);
        L.rawsetp(State.REGISTRYINDEX, code);
    }

    L.insert(-@as(State.Index, nargs) - 1);
    L.call(nargs, 1);
}

pub const State = opaque {
    pub const Number = c.lua_Number;

    pub const Integer = c.lua_Integer;

    pub const Unsigned = lookup("lua_Unsigned", std.meta.Int(.unsigned, @bitSizeOf(Integer) - 1));

    pub const Index = c_int;
    pub const AbsIndex = Size;
    pub const Size = std.meta.Int(.unsigned, @bitSizeOf(Index) - 1);

    pub const CFn = c.lua_CFunction;
    pub const ReaderFn = c.lua_Reader;
    pub const WriterFn = c.lua_Writer;
    pub const AllocFn = c.lua_Alloc;
    pub const DebugInfo = c.lua_Debug;
    pub const HookFn = c.lua_Hook;

    pub const REGISTRYINDEX = c.LUA_REGISTRYINDEX;

    pub const ThreadStatus = enum(c_int) {
        ok = lookup("LUA_OK", 0),
        yield = c.LUA_YIELD,
        err_runtime = c.LUA_ERRRUN,
        err_syntax = c.LUA_ERRSYNTAX,
        err_memory = c.LUA_ERRMEM,
        err_handler = c.LUA_ERRERR,
        err_file = c.LUA_ERRFILE,
    };

    pub const Type = enum(c_int) {
        none = c.LUA_TNONE,
        nil = c.LUA_TNIL,
        boolean = c.LUA_TBOOLEAN,
        lightuserdata = c.LUA_TLIGHTUSERDATA,
        number = c.LUA_TNUMBER,
        string = c.LUA_TSTRING,
        table = c.LUA_TTABLE,
        function = c.LUA_TFUNCTION,
        userdata = c.LUA_TUSERDATA,
        thread = c.LUA_TTHREAD,
    };

    pub const ArithOp = enum(c_int) {
        add = lookup("LUA_OPADD", -1),
        sub = lookup("LUA_OPSUB", -2),
        mul = lookup("LUA_OPMUL", -3),
        div = lookup("LUA_OPDIV", -4),
        idiv = lookup("LUA_OPIDIV", -5),
        mod = lookup("LUA_OPMOD", -6),
        pow = lookup("LUA_OPPOW", -7),
        unm = lookup("LUA_OPUNM", -8),
        bnot = lookup("LUA_OPBNOT", -9),
        band = lookup("LUA_OPBAND", -10),
        bor = lookup("LUA_OPBOR", -11),
        bxor = lookup("LUA_OPBXOR", -12),
        shl = lookup("LUA_OPSHL", -13),
        shr = lookup("LUA_OPSHR", -14),
    };

    pub const CompareOp = enum(c_int) {
        eq = lookup("LUA_OPEQ", -1),
        lt = lookup("LUA_OPLT", -2),
        le = lookup("LUA_OPLE", -3),
    };

    pub const LoadMode = enum {
        binary,
        text,
        either,
    };

    fn to(ptr: *State) *c.lua_State {
        return @ptrCast(*c.lua_State, ptr);
    }

    // state manipulation

    pub fn newstate(f: AllocFn, ud: ?*anyopaque) !*State {
        const ret = c.lua_newstate(f, ud);
        if (ret == null) return error.OutOfMemory;
        return @ptrCast(*State, ret.?);
    }

    pub fn close(L: *State) void {
        return c.lua_close(to(L));
    }

    pub fn newthread(L: *State) !*State {
        const ptr = c.lua_newthread(to(L));
        if (ptr == null) return error.OutOfMemory;
        return @ptrCast(*State, ptr.?);
    }

    pub fn atpanic(L: *State, comptime panicf: anytype) CFn {
        return c.lua_atpanic(to(L), wrapAnyFn(panicf));
    } // TODO: wrap

    // basic stack manipulation

    pub fn upvalueindex(index: Index) Index {
        return c.lua_upvalueindex(index);
    }

    pub fn absindex(L: *State, index: Index) Index {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_absindex(to(L), index);
        }

        if (index < 0 and index > REGISTRYINDEX)
            return L.gettop() + 1 + index;
        return index;
    }

    pub fn gettop(L: *State) Index {
        return c.lua_gettop(to(L));
    }

    pub fn settop(L: *State, index: Index) void {
        return c.lua_settop(to(L), index);
    }

    pub fn pushvalue(L: *State, index: Index) void {
        return c.lua_pushvalue(to(L), index);
    }

    pub fn remove(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            L.rotate(index, -1);
            return L.pop(1);
        }

        return c.lua_remove(to(L), index);
    }

    pub fn insert(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return L.rotate(index, 1);
        }

        return c.lua_insert(to(L), index);
    }

    pub fn replace(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            L.copy(-1, index);
            return L.pop(1);
        }

        return c.lua_replace(to(L), index);
    }

    fn rotate_reverse(L: *State, start: Index, end: Index) void {
        var a = start;
        var b = end;

        while (a < b) : ({
            a += 1;
            b -= 1;
        }) {
            L.pushvalue(a);
            L.pushvalue(b);
            L.replace(a);
            L.replace(b);
        }
    }

    pub fn rotate(L: *State, index: Index, amount: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rotate(to(L), index, amount);
        } else {
            const idx = L.absindex(index);
            const elems = L.gettop() - idx + 1;
            var n = amount;
            if (n < 0) n += elems;

            // from compat53, verify this is correct, and rework
            if (n > 0 and n < elems) {
                L.ensurestack(2, "not enough stack slots available");
                n = elems - n;
                rotate_reverse(L, idx, idx + n - 1);
                rotate_reverse(L, idx + n, idx + elems - 1);
                rotate_reverse(L, idx, idx + elems - 1);
            }
        }
    }

    pub fn copy(L: *State, src: Index, dest: Index) void {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_copy(to(L), src, dest);
        }

        const abs_dest = L.absindex(dest);
        L.ensurestack(1, "not enough stack slots");
        L.pushvalue(src);
        return L.replace(abs_dest);
    }

    pub fn checkstack(L: *State, extra: Size) bool {
        return c.lua_checkstack(to(L), extra) == 0;
    }

    pub fn xmove(src: *State, dest: *State, n: Size) void {
        return c.lua_xmove(to(src), to(dest), n);
    }

    pub fn pop(L: *State, n: Size) void {
        return c.lua_pop(to(L), @as(Index, n));
    }

    // access functions (stack -> zig)

    pub fn isnumber(L: *State, index: Index) bool {
        return c.lua_isnumber(to(L), index) != 0;
    }

    pub fn isstring(L: *State, index: Index) bool {
        return c.lua_isstring(to(L), index) != 0;
    }

    pub fn iscfunction(L: *State, index: Index) bool {
        return c.lua_iscfunction(to(L), index) != 0;
    }

    pub fn isinteger(L: *State, index: Index) bool {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_isinteger(to(L), index) != 0;
        }

        if (!L.isnumber(index)) return false;

        return @floatToInt(Integer, L.tonumber(index)) == L.tointeger(index);
    }

    pub fn isuserdata(L: *State, index: Index) bool {
        return c.lua_isuserdata(to(L), index) != 0;
    }

    pub fn typeOf(L: *State, index: Index) Type {
        return @intToEnum(Type, c.lua_type(to(L), index));
    }

    pub fn typename(L: *State, typ: Type) [:0]const u8 {
        return std.mem.sliceTo(c.lua_typename(to(L), @enumToInt(typ)), 0);
    }

    pub fn tonumber(L: *State, index: Index) Number {
        if (c.LUA_VERSION_NUM >= 502) {
            var isnum: c_int = 0;
            const value = c.lua_tonumberx(to(L), index, &isnum);

            if (isnum == 0) return 0;
            return value;
        }

        return c.lua_tonumber(to(L), index);
    }

    pub fn tointeger(L: *State, index: Index) Integer {
        if (c.LUA_VERSION_NUM >= 502) {
            var isnum: c_int = 0;
            const value = c.lua_tointegerx(to(L), index, &isnum);

            if (isnum == 0) return 0;
            return value;
        }

        return c.lua_tointeger(to(L), index);
    }

    pub fn toboolean(L: *State, index: Index) bool {
        return c.lua_toboolean(to(L), index) != 0;
    }

    pub fn tolstring(L: *State, index: Index) ?[:0]const u8 {
        var ptr_len: usize = undefined;
        const ptr = c.lua_tolstring(to(L), index, &ptr_len);
        if (ptr == null) return null;

        return ptr[0..ptr_len :0];
    }

    pub fn tocfunction(L: *State, index: Index) CFn {
        return c.lua_tocfunction(to(L), index);
    }

    pub fn touserdata(L: *State, comptime T: type, index: Index) ?*align(@alignOf(usize)) T {
        return @ptrCast(?*align(@alignOf(usize)) T, c.lua_touserdata(to(L), index));
    }

    pub fn tothread(L: *State, index: Index) ?*State {
        return @ptrCast(?*State, c.lua_tothread(to(L), index));
    }

    pub fn topointer(L: *State, index: Index) ?*const anyopaque {
        return c.lua_topointer(to(L), index);
    }

    pub fn arith(L: *State, op: ArithOp) void {
        if (c.LUA_VERSION_NUM >= 502) {
            if (c.LUA_VERSION_NUM >= 503 or @enumToInt(op) >= 0) {
                return c.lua_arith(to(L), @enumToInt(op));
            }
        }

        const bitlib = if (c.LUA_VERSION_NUM == 502) "bit32" else "bit";

        const code = switch (op) {
            .add => "local a,b=...; return a+b",
            .sub => "local a,b=...; return a-b",
            .mul => "local a,b=...; return a*b",
            .div => "local a,b=...; return a/b",
            .idiv => "local a,b=...; return math.floor(a/b)",
            .mod => "local a,b=...; return a%b",
            .pow => "local a,b=...; return a^b",
            .unm => "local a=...; return -a",
            .bnot => "local a=...; return " ++ bitlib ++ ".bnot(a)",
            .band => "local a,b=...; return " ++ bitlib ++ ".band(a,b)",
            .bor => "local a,b=...; return " ++ bitlib ++ ".bor(a,b)",
            .bxor => "local a,b=...; return " ++ bitlib ++ ".bxor(a,b)",
            .shl => "local a,b=...; return " ++ bitlib ++ ".lshift(a,b)",
            .shr => "local a,b=...; return " ++ bitlib ++ ".rshift(a,b)",
        };

        if (op == .unm or op == .bnot) {
            return luz_compat_run(L, code, 1);
        } else {
            return luz_compat_run(L, code, 2);
        }
    }

    pub fn rawequal(L: *State, a: Index, b: Index) bool {
        return c.lua_rawequal(to(L), a, b) != 0;
    }

    pub fn compare(L: *State, a: Index, b: Index, op: CompareOp) bool {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_compare(to(L), a, b, @enumToInt(op)) != 0;
        }

        switch (op) {
            .eq => return c.lua_equal(L.to(), a, b) != 0,
            .lt => return c.lua_lessthan(L.to(), a, b) != 0,
            .le => {
                const abs_a = L.absindex(a);
                const abs_b = L.absindex(b);

                L.pushvalue(abs_a);
                L.pushvalue(abs_b);

                luz_compat_run(L, "local a,b=...; return a <= b", 2);
                const res = L.toboolean(-1);
                L.pop(1);

                return res;
            },
        }
    }

    pub fn isfunction(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TFUNCTION;
    }

    pub fn istable(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TTABLE;
    }

    pub fn isfulluserdata(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TUSERDATA;
    }

    pub fn islightuserdata(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TLIGHTUSERDATA;
    }

    pub fn isnil(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TNIL;
    }

    pub fn isboolean(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TBOOLEAN;
    }

    pub fn isthread(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TTHREAD;
    }

    pub fn isnone(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TNONE;
    }

    pub fn isnoneornil(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) <= 0;
    }

    // push functions (zig -> stack)

    pub fn pushnil(L: *State) void {
        return c.lua_pushnil(to(L));
    }

    pub fn pushnumber(L: *State, value: Number) void {
        return c.lua_pushnumber(to(L), value);
    }

    pub fn pushinteger(L: *State, value: Integer) void {
        return c.lua_pushinteger(to(L), value);
    }

    pub fn pushlstring(L: *State, value: []const u8) void {
        _ = c.lua_pushlstring(to(L), value.ptr, value.len);
    }

    pub fn pushzstring(L: *State, value: [:0]const u8) void {
        _ = c.lua_pushstring(to(L), value.ptr);
    }

    pub fn pushfstring(L: *State, comptime fmt: [:0]const u8, args: anytype) [:0]const u8 {
        const ptr = @call(.auto, c.lua_pushfstring, .{ to(L), fmt.ptr } ++ args);
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn pushclosure_unwrapped(L: *State, func: CFn, n: Size) void {
        return c.lua_pushcclosure(to(L), func, n);
    }

    pub fn pushboolean(L: *State, value: bool) void {
        return c.lua_pushboolean(to(L), @boolToInt(value));
    }

    pub fn pushlightuserdata(L: *State, ptr: anytype) void {
        assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
        return c.lua_pushlightuserdata(to(L), @constCast(@ptrCast(*const anyopaque, ptr)));
    }

    pub fn pushthread(L: *State) bool {
        return c.lua_pushthread(to(L)) != 0;
    }

    // get functions (Lua -> stack)

    pub fn getglobal(L: *State, name: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_getglobal(to(L), name.ptr));
        }

        c.lua_getglobal(to(L), name.ptr);
        return L.typeOf(-1);
    }

    pub fn gettable(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_gettable(to(L), index));
        }

        c.lua_gettable(to(L), index);
        return L.typeOf(-1);
    }

    pub fn getfield(L: *State, index: Index, name: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_getfield(to(L), index, name.ptr));
        }

        c.lua_getfield(to(L), index, name.ptr);
        return L.typeOf(-1);
    }

    pub fn geti(L: *State, index: Index, n: Integer) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_geti(to(L), index, n));
        }

        const abs = L.absindex(index);
        L.pushinteger(n);
        return L.gettable(abs);
    }

    pub fn rawget(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_rawget(to(L), index));
        }

        c.lua_rawget(to(L), index);
        return L.typeOf(-1);
    }

    pub fn rawgeti(L: *State, index: Index, n: Integer) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_rawgeti(to(L), index, n));
        }

        if (n > std.math.maxInt(c_int)) {
            L.pushinteger(n);
            return L.rawget(index);
        } else {
            c.lua_rawgeti(to(L), index, @intCast(c_int, n));
            return L.typeOf(-1);
        }
    }

    pub fn rawgetp(L: *State, index: Index, ptr: anytype) Type {
        assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_rawgetp(to(L), index, @ptrCast(*const anyopaque, ptr)));
        }

        const abs = L.absindex(index);
        L.pushlightuserdata(ptr);
        return L.rawget(abs);
    }

    pub fn createtable(L: *State, narr: usize, nrec: usize) void {
        return c.lua_createtable(to(L), @intCast(Size, narr), @intCast(Size, nrec));
    }

    pub fn newuserdata(L: *State, size: Size) *anyopaque {
        if (c.LUA_VERSION_NUM >= 504) {
            return c.lua_newuserdatauv(to(L), size, 0).?;
        }

        return c.lua_newuserdata(to(L), size).?;
    }

    pub fn getmetatable(L: *State, index: Index) bool {
        if (c.LUA_VERSION_NUM >= 504) {
            return c.lua_getmetatable(to(L), index) != 0;
        }

        return c.lua_getmetatable(to(L), index) != 0;
    }

    pub fn newtable(L: *State) void {
        return c.lua_newtable(to(L));
    }

    pub fn pushglobaltable(L: *State) void {
        if (c.LUA_VERSION_NUM >= 502) {
            _ = L.rawgeti(REGISTRYINDEX, c.LUA_RIDX_GLOBALS);
            return;
        }

        return c.lua_pushvalue(to(L), c.LUA_GLOBALSINDEX);
    }

    pub fn getuservalue(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.lua_getuservalue(to(L), index));
        }

        if (c.LUA_VERSION_NUM >= 502) {
            c.lua_getuservalue(to(L), index);
            return L.typeOf(-1);
        }

        if (!L.isfulluserdata(index))
            L.throw("full userdata expected", .{});

        const ptr = L.topointer(index).?;
        return L.rawgetp(REGISTRYINDEX, ptr);
    }

    // set functions (stack -> Lua)

    pub fn setglobal(L: *State, name: [:0]const u8) void {
        return c.lua_setglobal(to(L), name.ptr);
    }

    pub fn settable(L: *State, index: Index) void {
        return c.lua_settable(to(L), index);
    }

    pub fn setfield(L: *State, index: Index, name: [:0]const u8) void {
        return c.lua_setfield(to(L), index, name.ptr);
    }

    pub fn seti(L: *State, index: Index, n: Integer) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_seti(to(L), index, n);
        }

        const abs = L.absindex(index);
        L.pushinteger(n);
        return L.settable(abs);
    }

    pub fn rawset(L: *State, index: Index) void {
        return c.lua_rawset(to(L), index);
    }

    pub fn rawseti(L: *State, index: Index, n: usize) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rawseti(to(L), index, @intCast(Integer, n));
        }

        if (n > std.math.maxInt(c_int)) {
            L.pushinteger(@intCast(Integer, n));
            return L.rawset(index);
        }

        return c.lua_rawseti(to(L), index, @intCast(c_int, n));
    }

    pub fn rawsetp(L: *State, index: Index, ptr: anytype) void {
        assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rawsetp(to(L), index, @ptrCast(*const anyopaque, ptr));
        }

        const abs = L.absindex(index);
        L.pushlightuserdata(ptr);
        return L.rawset(abs);
    }

    pub fn setmetatable(L: *State, index: Index) void {
        _ = c.lua_setmetatable(to(L), index);
        return;
    }

    pub fn setuservalue(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 504) {
            _ = c.lua_setiuservalue(to(L), index, 1);
            return;
        }

        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_setuservalue(to(L), index);
        }

        if (!L.isfulluserdata(index))
            L.throw("full userdata expected", .{});

        const ptr = L.topointer(index).?;
        return L.rawsetp(REGISTRYINDEX, ptr);
    }

    // load and call functions

    pub fn call(L: *State, nargs: Size, nresults: ?Size) void {
        const nres: Index = nresults orelse c.LUA_MULTRET;

        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_callk(to(L), nargs, nres, 0, null);
        }

        return c.lua_call(to(L), nargs, nres);
    }

    pub fn pcall(L: *State, nargs: Size, nresults: ?Size, handler_index: Index) ThreadStatus {
        const nres: Index = nresults orelse c.LUA_MULTRET;

        if (c.LUA_VERSION_NUM >= 502) {
            return @intToEnum(ThreadStatus, c.lua_pcallk(to(L), nargs, nres, handler_index, 0, null));
        }

        return @intToEnum(ThreadStatus, c.lua_pcall(to(L), nargs, nres, handler_index));
    }

    pub fn load(L: *State, reader: anytype, chunkname: [:0]const u8, mode: LoadMode) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 502) {
            return @intToEnum(ThreadStatus, c.lua_load(
                to(L),
                reader.read,
                &reader,
                chunkname,
                switch (mode) {
                    .binary => "b",
                    .text => "t",
                    .either => null,
                },
            ));
        }

        if (reader.mode == .binary and mode == .text)
            L.throw("attempt to load a binary chunk (mode is 'text')");

        if (reader.mode == .text and mode == .binary)
            L.throw("attempt to load a text chunk (mode is 'binary')");

        return @intToEnum(ThreadStatus, c.lua_load(to(L), reader.read, &reader, chunkname));
    }

    pub fn dump(L: *State, writer: anytype, strip: bool) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 502) {
            return @intToEnum(ThreadStatus, c.lua_dump(to(L), writer.write, &writer, strip));
        }

        return @intToEnum(ThreadStatus, c.lua_dump(to(L), writer.write, &writer));
    }

    // coroutine functions

    pub fn yield(L: *State, nresults: Size) noreturn {
        if (c.LUA_VERSION_NUM >= 502) {
            _ = c.lua_yieldk(to(L), nresults, 0, null);
            unreachable;
        }

        _ = c.lua_yield(to(L), nresults);
        unreachable;
    }

    pub fn @"resume"(L: *State, nargs: Size) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 504) {
            var res: c_int = 0;
            return @intToEnum(ThreadStatus, c.lua_resume(to(L), null, nargs, &res));
        }

        if (c.LUA_VERSION_NUM >= 502) {
            return @intToEnum(ThreadStatus, c.lua_resume(to(L), null, nargs));
        }

        return @intToEnum(ThreadStatus, c.lua_resume(to(L), nargs));
    }

    pub fn status(L: *State) ThreadStatus {
        return @intToEnum(ThreadStatus, c.lua_status(to(L)));
    }

    // isyieldable unimplementable in 5.2 and 5.1
    // setwarnf unimplementable in 5.3 and 5.2 and 5.1
    // warning unimplementable in 5.3 and 5.2 and 5.1

    // TODO: gc

    // miscellaneous functions

    pub fn @"error"(L: *State) noreturn {
        _ = c.lua_error(to(L));
        unreachable;
    }

    pub fn next(L: *State, index: Index) bool {
        return c.lua_next(to(L), index) != 0;
    }

    pub fn concat(L: *State, items: Size) void {
        return c.lua_concat(to(L), items);
    }

    pub fn len(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_len(to(L), index);
        }

        switch (L.typeOf(index)) {
            .string => {
                const olen = @intCast(Integer, c.lua_objlen(to(L), index));
                return L.pushinteger(olen);
            },
            .table => if (!L.callmeta(index, "__len")) {
                const olen = @intCast(Integer, c.lua_objlen(to(L), index));
                return L.pushinteger(olen);
            },
            .userdata => if (!L.callmeta(index, "__len")) {
                L.throw("attempt to get length of a userdata value", .{});
            },
            else => L.throw("attempt to get length of a %s value", .{L.typenameOf(index).ptr}),
        }
    }

    // debug api

    pub fn getstack(L: *State, level: Size, ar: *DebugInfo) bool {
        return c.lua_getstack(to(L), level, ar) != 0;
    }

    pub fn getinfo(L: *State, what: [:0]const u8, ar: *DebugInfo) bool {
        return c.lua_getinfo(to(L), what.ptr, ar) != 0;
    }

    pub fn getlocal(L: *State, ar: *DebugInfo, n: Size) [:0]const u8 {
        const ptr = c.lua_getlocal(to(L), ar, n);
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn setlocal(L: *State, ar: *DebugInfo, n: Size) [:0]const u8 {
        const ptr = c.lua_setlocal(to(L), ar, n);
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn getupvalue(L: *State, funcindex: Index, n: Size) [:0]const u8 {
        const ptr = c.lua_getupvalue(to(L), funcindex, n);
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn setupvalue(L: *State, funcindex: Index, n: Size) [:0]const u8 {
        const ptr = c.lua_setupvalue(to(L), funcindex, n);
        return std.mem.sliceTo(ptr, 0);
    }

    // upvalueid unimplementable in 5.3 and 5.2 and 5.1
    // upvaluejoin unimplementable in 5.3 and 5.2 and 5.1

    pub fn sethook(L: *State, func: HookFn, mask: c_int, count: Size) void {
        _ = c.lua_sethook(to(L), func, mask, count);
    }

    pub fn gethook(L: *State) HookFn {
        return c.lua_gethook(to(L));
    }

    pub fn gethookmask(L: *State) c_int {
        return c.lua_gethookmask(to(L));
    }

    pub fn gethookcount(L: *State) Size {
        return @intCast(Size, c.lua_gethookcount(to(L)));
    }

    // auxiliary library

    pub fn getmetafield(L: *State, obj: Index, event: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @intToEnum(Type, c.luaL_getmetafield(to(L), obj, event.ptr));
        }

        if (c.luaL_getmetafield(to(L), obj, event.ptr) == 0) {
            return .nil;
        }

        return L.typeOf(-1);
    }

    pub fn callmeta(L: *State, obj: Index, event: [:0]const u8) bool {
        return c.luaL_callmeta(to(L), obj, event.ptr) != 0;
    }

    // argerror replaced with check mechanism
    // typeerror replaced with check mechanism
    // checklstring replaced with check mechanism
    // optlstring replaced with check mechanism
    // checknumber replaced with check mechanism
    // optnumber replaced with check mechanism
    // checkinteger replaced with check mechanism
    // optinteger replaced with check mechanism
    // checktype replaced with check mechanism
    // checkany replaced with check mechanism

    /// Grows the stack size to top + sz elements, raising an error if the stack
    /// cannot grow to that size. msg is an additional text to go into the error
    /// message.
    pub fn ensurestack(L: *State, sz: Size, msg: [:0]const u8) void {
        c.luaL_checkstack(to(L), sz, msg.ptr);
    }

    pub fn newmetatableFor(L: *State, tname: [:0]const u8) bool {
        return c.luaL_newmetatable(to(L), tname.ptr) != 0;
    }

    pub fn setmetatableFor(L: *State, tname: [:0]const u8) void {
        if (c.LUA_VERSION_NUM >= 502) {
            c.luaL_setmetatable(to(L), tname.ptr);
        }

        _ = L.getmetatableFor(tname);
        L.setmetatable(-2);
    }

    // testudata replaced with userdata mechanism
    // checkudata replaced with userdata mechanism

    pub fn where(L: *State, lvl: Size) void {
        c.luaL_where(to(L), lvl);
    }

    /// Raises an error. The error message format is given by fmt plus any extra
    /// arguments, following the same rules of lua_pushfstring. It also adds at
    /// the beginning of the message the file name and the line number where the
    /// error occurred, if this information is available.
    pub fn throw(L: *State, msg: [:0]const u8, args: anytype) noreturn {
        if (args.len == 0) {
            L.pushlstring(msg);
            L.@"error"();
        } else {
            _ = @call(.auto, c.luaL_error, .{ to(L), msg.ptr } ++ args);
            unreachable;
        }
    }

    // checkoption replaced with check mechanism

    // TODO: fileresult
    // TODO: execresult

    pub fn ref(L: *State, t: Index) c_int {
        return c.luaL_ref(to(L), t);
    }

    pub fn unref(L: *State, t: Index, refi: c_int) void {
        c.luaL_unref(to(L), t, refi);
    }

    // TODO: loadfile

    pub fn loadstring(L: *State, str: []const u8, chunkname: [:0]const u8, mode: LoadMode) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 502) {
            return @intToEnum(ThreadStatus, c.luaL_loadbufferx(
                to(L),
                str.ptr,
                str.len,
                chunkname,
                switch (mode) {
                    .binary => "b",
                    .text => "t",
                    .either => null,
                },
            ));
        }

        return @intToEnum(ThreadStatus, c.luaL_loadbuffer(to(L), str.ptr, str.len, chunkname));
    }

    pub fn lenOf(L: *State, obj: Index) Size {
        if (c.LUA_VERSION_NUM >= 502) {
            return @intCast(Size, c.luaL_len(to(L), obj));
        }

        L.len(obj);
        const n = L.tointeger(-1);
        L.pop(1);
        return @intCast(Size, n);
    }

    pub fn gsub(L: *State, s: [:0]const u8, p: [:0]const u8, r: [:0]const u8) [:0]const u8 {
        return std.mem.sliceTo(c.luaL_gsub(to(L), s.ptr, p.ptr, r.ptr), 0);
    }

    // TODO: setfuncs

    pub fn getsubtable(L: *State, t: Index, fname: [:0]const u8) bool {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.luaL_getsubtable(to(L), t, fname.ptr) != 0;
        }

        if (L.getfield(t, fname) != .table) {
            L.pop(1);
            L.newtable();
            L.pushvalue(-1);
            L.setfield(t, fname);
            return false;
        }

        return true;
    }

    pub fn traceback(L: *State, target: *State, msg: ?[:0]const u8, level: Size) void {
        if (c.LUA_VERSION_NUM >= 502) {
            c.luaL_traceback(to(L), to(target), if (msg) |m| m.ptr else null, level);
        }

        var ar: DebugInfo = undefined;
        var buffer = Buffer.init(L);

        if (msg) |m| {
            buffer.addstring(m);
            buffer.addchar('\n');
        }

        buffer.addstring("stack traceback:");
        var this_level = level;
        while (target.getstack(this_level, &ar)) : (this_level += 1) {
            _ = target.getinfo("Slnt", &ar);
            if (ar.currentline <= 0) {
                _ = L.pushfstring("\n\t%s: in ", .{&ar.short_src});
            } else {
                _ = L.pushfstring("\n\t%s:%d: in ", .{ &ar.short_src, ar.currentline });
            }
            buffer.addvalue();

            if (ar.namewhat[0] != 0) {
                _ = L.pushfstring("%s '%s'", .{ ar.namewhat, ar.name });
            } else if (ar.what[0] == 'm') {
                _ = L.pushlstring("main chunk");
            } else if (ar.what[0] != 'C') {
                _ = L.pushfstring("function <%s:%d>", .{ &ar.short_src, ar.linedefined });
            } else {
                _ = L.pushlstring("?");
            }

            buffer.addvalue();
            if (@hasField(DebugInfo, "istailcall") and ar.istailcall != 0)
                buffer.addstring("\n\t(...tail calls...)");
        }
    }

    pub fn requiref(L: *State, module: [:0]const u8, comptime openf: anytype, global: bool) void {
        if (c.LUA_VERSION_NUM >= 503) {
            c.luaL_requiref(to(L), module, wrapCFn(openf), @boolToInt(global));
        }

        const scheck = StackCheck.init(L);
        defer scheck.check(L, 1);

        assert(L.getglobal("package") == .table);
        assert(L.getfield(-1, "loaded") == .table);
        _ = L.getfield(-1, module);
        if (!L.toboolean(-1)) {
            L.pop(1);
            L.pushcfunction(wrapCFn(openf));
            L.pushlstring(module);
            L.call(1, 1);
            L.pushvalue(-1);
            L.setfield(-3, module);
        }

        if (global) {
            L.pushvalue(-1);
            L.setglobal(module);
        }

        L.insert(-3);
        L.pop(2);
    }

    pub fn typenameOf(L: *State, idx: Index) [:0]const u8 {
        return L.typename(L.typeOf(idx));
    }

    pub fn getmetatableFor(L: *State, tname: [:0]const u8) Type {
        return L.getfield(REGISTRYINDEX, tname);
    }

    // convienience functions

    pub fn push(L: *State, value: anytype) void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Void, .Null => L.pushnil(),
            .Bool => L.pushboolean(value),
            .Int, .ComptimeInt => L.pushinteger(@intCast(Integer, value)),
            .Float, .ComptimeFloat => L.pushnumber(@floatCast(Number, value)),
            .Pointer => |info| {
                if (comptime std.meta.trait.isZigString(T)) {
                    return L.pushlstring(value);
                }

                switch (info.size) {
                    .One, .Many, .C => L.pushlightuserdata(value),
                    .Slice => {
                        L.createtable(@intCast(Size, value.len), 0);

                        for (value, 0..) |item, i| {
                            L.push(item);
                            L.rawseti(-2, i + 1);
                        }
                    },
                }
            },
            .Array, .Vector => {
                L.createtable(value.len, 0);

                for (value, 0..) |item, i| {
                    L.push(item);
                    L.rawseti(-2, i + 1);
                }
            },
            .Struct => |info| if (info.is_tuple) {
                L.createtable(info.fields.len, 0);

                inline for (value, 0..) |item, i| {
                    L.push(item);
                    L.rawseti(-2, i + 1);
                }
            } else if (info.backing_integer) |int_t| {
                L.pushinteger(@intCast(Integer, @bitCast(int_t, value)));
            } else {
                L.createtable(0, info.fields.len);

                inline for (info.fields) |field| {
                    L.push(@field(value, field.name));
                    L.setfield(-2, literal(field.name));
                }
            },
            .Optional => if (value) |u_value| {
                L.push(u_value);
            } else {
                L.pushnil();
            },
            .ErrorSet => L.pushlstring(@errorName(value)),
            .Enum => L.pushinteger(@enumToInt(value)),
            .Union => {
                L.createtable(0, 1);

                switch (value) {
                    inline else => |u_value| {
                        L.push(u_value);
                        L.setfield(-2, @tagName(value));
                    },
                }
            },
            .Fn => L.pushclosure_unwrapped(wrapAnyFn(value), 0),
            .EnumLiteral => L.pushlstring(@tagName(value)),
            .Type => switch (@typeInfo(value)) {
                .Struct => |info| {
                    L.createtable(0, info.decls.len);

                    inline for (info.decls) |decl| {
                        if (decl.is_pub) {
                            L.push(@field(value, decl.name));
                            L.setfield(-2, literal(decl.name));
                        }
                    }
                },
                .Enum => |info| {
                    L.createtable(0, info.fields.len);

                    inline for (info.fields) |field| {
                        L.push(field.value);
                        L.setfield(-2, literal(field.name));
                    }
                },
                .ErrorSet => |info| if (info) |fields| {
                    L.createtable(fields.len, 0);

                    inline for (fields, 0..) |field, i| {
                        L.push(field.name);
                        L.rawseti(-2, i + 1);
                    }
                } else @compileError("cannot push anyerror"),
                else => @compileError("unable to push container '" ++ @typeName(value) ++ "'"),
            },
            else => @compileError("unable to push value '" ++ @typeName(T) ++ "'"),
        }
    }

    fn resource__tostring(L: *State) c_int {
        _ = L.getfield(upvalueindex(1), "__name");
        _ = L.pushfstring(": %p", .{L.topointer(1)});
        L.concat(2);

        return 1;
    }

    pub fn registerResource(L: *State, comptime T: type, comptime metatable: ?type) void {
        const tname = literal(@typeName(T));

        if (L.getmetatableFor(tname) != .table) {
            L.pop(1);

            if (metatable) |mt| {
                L.push(mt);
            } else {
                L.createtable(0, 1);
            }

            L.push(tname);
            L.setfield(-2, "__name");

            if (c.LUA_VERSION_NUM <= 503 and (metatable == null or metatable != null and !@hasField(metatable.?, "__tostring"))) {
                L.pushvalue(-1);
                L.pushclosure_unwrapped(wrapCFn(resource__tostring), 1);
                L.setfield(-2, "__tostring");
            }

            L.pushvalue(-1);
            L.setfield(c.LUA_REGISTRYINDEX, tname);
        }
    }

    pub fn resource(L: *State, comptime T: type) *align(@alignOf(usize)) T {
        const tname = literal(@typeName(T));

        const size = @sizeOf(T);
        const ptr = L.newuserdata(size);

        assert(L.getmetatableFor(tname) == .table);
        L.setmetatable(-2);

        return @ptrCast(*align(@alignOf(usize)) T, @alignCast(@alignOf(usize), ptr));
    }

    pub fn pusherror(L: *State, err: anyerror) void {
        L.pushnil();
        L.pushlstring(@errorName(err));
    }

    const empty_allocator = Allocator{ .ptr = @intToPtr(*anyopaque, std.math.maxInt(usize)), .vtable = undefined };

    fn check_typeerror(L: *State, comptime source: []const u8, comptime expected: []const u8, index: Index) noreturn {
        const message = source ++ ": expected " ++ expected ++ ", got %s";
        const stripped = if (source.len == 0) message[2..] else message[0..];
        _ = L.pushfstring(stripped, .{L.typenameOf(index).ptr});
        L.@"error"();
    }

    fn check_strerror(L: *State, comptime source: []const u8, comptime expected: []const u8, str: [:0]const u8) noreturn {
        const message = source ++ ": expected " ++ expected ++ ", got %s";
        const stripped = if (source.len == 0) message[2..] else message[0..];
        _ = L.pushfstring(stripped, .{str.ptr});
        L.@"error"();
    }

    fn check_numerror(L: *State, comptime source: []const u8, comptime expected: []const u8, num: Integer) noreturn {
        const message = source ++ ": expected " ++ expected ++ ", got %d";
        const stripped = if (source.len == 0) message[2..] else message[0..];
        _ = L.pushfstring(stripped, .{num});
        L.@"error"();
    }

    fn checkInternal(L: *State, comptime name: []const u8, comptime T: type, idx: Index, allocator: anytype) T {
        switch (@typeInfo(T)) {
            .Bool => {
                if (!L.isboolean(idx))
                    L.check_typeerror(name, "boolean", idx);

                return L.toboolean(idx);
            },
            .Int => {
                if (!L.isinteger(idx))
                    L.check_typeerror(name, "integer", idx);

                const err_range = comptime comptimePrint("number in range [{d}, {d}]", .{ std.math.minInt(T), std.math.maxInt(T) });

                const num = L.tointeger(idx);
                return std.math.cast(T, num) orelse
                    L.check_numerror(name, err_range, num);
            },
            .Float => {
                if (!L.isnumber(idx))
                    L.check_typeerror(name, "number", idx);

                return @floatCast(T, L.tonumber(idx));
            },
            .Array => |info| {
                if (!L.istable(idx))
                    L.check_typeerror(name, "table", idx);

                const err_len = comptime comptimePrint("length of {d}", .{info.len});

                const tlen = L.lenOf(idx);
                if (tlen != info.len)
                    L.check_numerror(name, err_len, tlen);

                var res: T = undefined;

                for (res[0..], 0..) |*slot, i| {
                    _ = L.rawgeti(idx, @intCast(c_int, i) + 1);
                    slot.* = L.checkInternal(name ++ "[]", info.child, -1, allocator);
                }

                L.pop(info.len);
                return res;
            },
            .Struct => |info| {
                if (!L.istable(idx))
                    L.check_typeerror(name, "table", idx);

                var res: T = undefined;

                inline for (info.fields) |field| {
                    _ = L.getfield(idx, literal(field.name));
                    @field(res, field.name) = L.checkInternal(name ++ "." ++ field.name, field.type, -1, allocator);
                }

                L.pop(info.fields.len);
                return res;
            },
            .Pointer => |info| {
                if (comptime std.meta.trait.isZigString(T)) {
                    if (!L.isstring(idx))
                        L.check_typeerror(name, "string", idx);

                    if (!info.is_const) {
                        if (allocator == null) @compileError("cannot allocate non-const string, use checkAlloc instead");

                        const str = L.tolstring(idx) orelse unreachable;
                        return allocator.dupe(str) catch
                            L.throw("out of memory", .{});
                    }

                    return L.tolstring(idx) orelse unreachable;
                }

                switch (info.size) {
                    .One, .Many, .C => {
                        if (!L.isuserdata(idx))
                            L.check_typeerror(name, "userdata", idx);

                        return @ptrCast(T, L.touserdata(idx) orelse unreachable);
                    },
                    .Slice => {
                        if (!L.istable(idx))
                            L.check_typeerror(name, "table", idx);

                        if (allocator == null) @compileError("cannot allocate slice, use checkAlloc instead");

                        const sentinel = if (info.sentinel) |ptr| @ptrCast(*const info.child, ptr).* else null;

                        const slen = L.lenOf(idx);
                        const ptr = allocator.allocWithOptions(info.child, slen, info.alignment, sentinel) catch
                            L.throw("out of memory", .{});

                        for (ptr[0..], 0..) |*slot, i| {
                            _ = L.rawgeti(idx, @intCast(c_int, i) + 1);
                            slot.* = L.checkInternal(name ++ "[]", info.child, -1, allocator);
                        }

                        L.pop(slen);
                        return ptr;
                    },
                }
            },
            .Optional => |info| {
                if (L.isnoneornil(idx)) return null;

                return L.checkInternal(name ++ ".?", info.child, idx, allocator);
            },
            .Enum => |info| {
                if (L.isnumber(idx)) {
                    const value = @intCast(info.tag_type, L.tointeger(idx));
                    return @intToEnum(T, value);
                } else if (L.isstring(idx)) {
                    const value = L.tolstring(idx) orelse unreachable;

                    return std.meta.stringToEnum(T, value) orelse
                        L.check_strerror(name, "member of " ++ @typeName(T), value);
                } else L.check_typeerror(name, "number or string", idx);
            },
            else => @compileError("check not implemented for " ++ @typeName(T)),
        }
    }

    pub fn check(L: *State, comptime T: type, idx: Index) T {
        return L.checkInternal("", T, idx, null);
    }

    pub fn checkAlloc(L: *State, comptime T: type, idx: Index, allocator: Allocator) T {
        return L.checkInternal("", T, idx, allocator);
    }

    pub fn checkResource(L: *State, comptime T: type, arg: Index) *align(@alignOf(usize)) T {
        const ptr = c.luaL_checkudata(to(L), arg, literal(@typeName(T))).?;
        return @ptrCast(*align(@alignOf(usize)) T, @alignCast(@alignOf(usize), ptr));
    }
};

pub const Buffer = struct {
    state: *State,
    check: StackCheck,
    buf: c.luaL_Buffer,

    pub fn init(L: *State) Buffer {
        var res: Buffer = undefined;
        res.state = L;
        res.buf = std.mem.zeroes(c.luaL_Buffer);

        c.luaL_buffinit(L.to(), &res.buf);

        res.check = StackCheck.init(L);
        return res;
    }

    pub fn reserve(buffer: *Buffer, max_size: usize) []u8 {
        buffer.check.check(buffer.state, 0);

        const ptr = if (c.LUA_VERSION_NUM >= 502)
            c.luaL_prepbuffsize(buffer.state.to(), &buffer.buf, max_size)
        else
            c.luaL_prepbuffer(&buffer.buf);

        const clamped_len = if (c.LUA_VERSION_NUM >= 502)
            max_size
        else
            @min(max_size, c.LUAL_BUFFERSIZE);

        buffer.check = StackCheck.init(buffer.state);
        return ptr[0..clamped_len];
    }

    pub fn commit(buffer: *Buffer, size: usize) void {
        buffer.check.check(buffer.state, 0);

        // TODO: translate-c bug: c.luaL_addsize(&buffer.buf, size);
        if (c.LUA_VERSION_NUM >= 502) {
            buffer.buf.n += size;
        } else {
            buffer.buf.p += size;
        }

        buffer.check = StackCheck.init(buffer.state);
    }

    pub fn addchar(buffer: *Buffer, char: u8) void {
        const str = buffer.reserve(1);
        str[0] = char;
        buffer.commit(1);
    }

    pub fn addstring(buffer: *Buffer, str: []const u8) void {
        buffer.check.check(buffer.state, 0);

        c.luaL_addlstring(&buffer.buf, str.ptr, str.len);

        buffer.check = StackCheck.init(buffer.state);
    }

    pub fn addvalue(buffer: *Buffer) void {
        buffer.check.check(buffer.state, 1); // one item should be on the stack

        c.luaL_addvalue(&buffer.buf);

        buffer.check = StackCheck.init(buffer.state);
    }

    pub fn final(buffer: *Buffer) void {
        buffer.check.check(buffer.state, 0);

        c.luaL_pushresult(&buffer.buf);
    }
};

pub fn wrapAnyFn(comptime func: anytype) State.CFn {
    const info = @typeInfo(@TypeOf(func)).Fn;
    if (info.params.len == 1 and info.params[0].type.? == *State) {
        return wrapCFn(func);
    }

    if (info.is_generic) return null;

    return wrapCFn(struct {
        fn wrapped(L: *State) info.return_type.? {
            var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;

            inline for (args, 0..) |*slot, i| {
                slot.* = L.check(@TypeOf(slot), i + 1);
            }

            return @call(.always_inline, func, args);
        }
    }.wrapped);
}

pub fn wrapCFn(comptime func: anytype) State.CFn {
    if (@TypeOf(func) == State.CFn) return func;

    return struct {
        fn wrapped(L_opt: ?*c.lua_State) callconv(.C) c_int {
            const L = @ptrCast(*State, L_opt.?);

            const result = @call(.always_inline, func, .{L});

            const T = @TypeOf(result);
            if (T == c_int) return result;

            switch (@typeInfo(T)) {
                .Void => return 0,
                .ErrorUnion => |info| {
                    const actual_result = result catch |err| {
                        L.pusherror(err);
                        return 2;
                    };

                    if (info.payload == c_int) return actual_result;

                    L.push(actual_result);
                    return 1;
                },
                else => {
                    L.push(result);
                    return 1;
                },
            }
        }
    }.wrapped;
}

const Allocator = std.mem.Allocator;
pub fn luaAlloc(ud: ?*anyopaque, ptr: ?*anyopaque, oldsize: usize, newsize: usize) callconv(.C) ?*anyopaque {
    assert(ud != null);

    const allocator = @ptrCast(*Allocator, @alignCast(@alignOf(Allocator), ud.?));
    const alignment = @alignOf(c.max_align_t);

    const ptr_aligned = @ptrCast(?[*]align(alignment) u8, @alignCast(alignment, ptr));

    if (ptr_aligned) |prev_ptr| {
        const prev_slice = prev_ptr[0..oldsize];

        if (newsize == 0) {
            allocator.free(prev_slice);
            return null;
        }

        if (newsize <= oldsize) {
            assert(allocator.resize(prev_slice, newsize));

            return prev_slice.ptr;
        }

        const new_slice = allocator.realloc(prev_slice, newsize) catch return null;
        return new_slice.ptr;
    }

    if (newsize == 0) return null;

    const new_ptr = allocator.alignedAlloc(u8, alignment, newsize) catch return null;
    return new_ptr.ptr;
}

/// Wraps a std.io.Reader to be used as a Lua reader function.
///
/// Should be used as follows:
/// ```zig
/// var lua_reader = try luaReader(reader);
/// L.load(lua_reader, "test.lua");
/// ```
pub fn LuaReader(comptime Reader: anytype) type {
    return struct {
        const Self = @This();

        pub fn read(L_opt: ?*c.lua_State, ud: ?*anyopaque, size: ?*usize) callconv(.C) [*c]const u8 {
            assert(ud != null);
            assert(size != null);

            const L = @ptrCast(*State, L_opt.?);
            const wrapper = @ptrCast(*Self, @alignCast(@alignOf(Self), ud.?));

            if (wrapper.has_byte) {
                wrapper.has_byte = false;

                size.?.* = 1;
                return wrapper.buf[0..1];
            }

            size.?.* = wrapper.reader.read(wrapper.buf[0..]) catch |err| {
                L.throw(@errorName(err), .{});
            };

            return &wrapper.buf;
        }

        reader: Reader,
        buf: [c.BUFSIZ]u8 = undefined,

        has_byte: bool = false,
        mode: State.LoadMode,
    };
}

pub fn luaReader(reader: anytype) @TypeOf(reader).Error!LuaReader(@TypeOf(reader)) {
    const byte = try reader.readByte();

    const mode = switch (byte) {
        c.LUA_SIGNATURE[0] => .binary,
        else => .text,
    };

    var wrapper = LuaReader(@TypeOf(reader)){ .reader = reader, .mode = mode };
    wrapper.buf[0] = byte;
    wrapper.has_byte = true;

    return;
}

/// Wraps a std.io.Writer to be used as a Lua writer function.
///
/// Should be used as follows:
/// ```zig
/// var lua_writer = LuaWriter(@TypeOf(writer)){ .writer = writer };
/// L.dump(lua_writer.write, &lua_writer);
/// ```
pub fn LuaWriter(comptime Writer: anytype) type {
    return struct {
        const Self = @This();

        pub fn write(L_opt: ?*c.lua_State, p: ?[*]const u8, sz: usize, ud: ?*anyopaque) callconv(.C) c_int {
            assert(ud != null);
            assert(p != null);

            const L = @ptrCast(*State, L_opt.?);
            const wrapper = @ptrCast(*Self, @alignCast(@alignOf(Self), ud.?));

            wrapper.writer.writeAll(p.?[0..sz]) catch |err| {
                L.throw(@errorName(err), .{});
            };

            return 0;
        }

        writer: Writer,
    };
}

pub fn luaWriter(writer: anytype) LuaWriter(@TypeOf(writer)) {
    return LuaWriter(@TypeOf(writer)){ .writer = writer };
}

pub fn exportAs(comptime func: anytype, comptime name: []const u8) void {
    _ = struct {
        fn luaopen(L: ?*c.lua_State) callconv(.C) c_int {
            const fnc = comptime wrapCFn(func) orelse unreachable;

            return @call(.always_inline, fnc, .{L});
        }

        comptime {
            @export(luaopen, .{ .name = "luaopen_" ++ name });
        }
    };
}

pub const StackCheck = struct {
    top: if (std.debug.runtime_safety) State.Index else void,

    pub fn init(L: *State) StackCheck {
        return .{ .top = if (std.debug.runtime_safety) L.gettop() else {} };
    }

    pub fn check(self: StackCheck, L: *State, pushed: u8) void {
        if (!std.debug.runtime_safety) return;

        const new_top = L.gettop();
        assert(new_top == self.top + pushed);
    }
};

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(State);

    std.testing.refAllDecls(LuaReader(std.fs.File.Reader));
    std.testing.refAllDecls(LuaWriter(std.fs.File.Writer));
}
