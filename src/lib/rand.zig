const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");

const State = luz.lua.State;
const allocator = luz.allocator;

const rand = std.rand;

fn BindRandom(comptime T: type) type {
    return struct {
        pub const __index = struct {
            pub fn bytes(L: *State) !c_int {
                const impl = L.checkResource(T, 1);

                const size = L.check(u31, 2);

                var index: u32 = 0;
                var b = luz.lua.Buffer.init(L);

                const r: rand.Random = impl.random();

                while (index < size) {
                    const ptr = b.reserve(size);

                    r.bytes(ptr);

                    b.commit(ptr.len);
                    index += @intCast(u32, ptr.len);
                }

                b.final();
                return 1;
            }

            pub fn int(L: *State) !State.Integer {
                const impl = L.checkResource(T, 1);
                const r: rand.Random = impl.random();

                return r.int(State.Integer);
            }

            pub fn uintLessThanBiased(L: *State) !State.Unsigned {
                const impl = L.checkResource(T, 1);
                const less_than = L.check(State.Unsigned, 2);

                const r: rand.Random = impl.random();

                return r.uintLessThanBiased(State.Unsigned, less_than);
            }

            pub fn uintLessThan(L: *State) !State.Unsigned {
                const impl = L.checkResource(T, 1);
                const less_than = L.check(State.Unsigned, 2);

                const r: rand.Random = impl.random();

                return r.uintLessThan(State.Unsigned, less_than);
            }

            pub fn uintAtMostBiased(L: *State) !State.Unsigned {
                const impl = L.checkResource(T, 1);
                const at_most = L.check(State.Unsigned, 2);

                const r: rand.Random = impl.random();

                return r.uintAtMostBiased(State.Unsigned, at_most);
            }

            pub fn uintAtMost(L: *State) !State.Unsigned {
                const impl = L.checkResource(T, 1);
                const at_most = L.check(State.Unsigned, 2);

                const r: rand.Random = impl.random();

                return r.uintAtMost(State.Unsigned, at_most);
            }

            pub fn intRangeLessThanBiased(L: *State) !State.Integer {
                const impl = L.checkResource(T, 1);
                const at_least = L.check(State.Integer, 2);
                const less_than = L.check(State.Integer, 3);

                const r: rand.Random = impl.random();

                return r.intRangeLessThanBiased(State.Integer, at_least, less_than);
            }

            pub fn intRangeLessThan(L: *State) !State.Integer {
                const impl = L.checkResource(T, 1);
                const at_least = L.check(State.Integer, 2);
                const less_than = L.check(State.Integer, 3);

                const r: rand.Random = impl.random();

                return r.intRangeLessThan(State.Integer, at_least, less_than);
            }

            pub fn intRangeAtMostBiased(L: *State) !State.Integer {
                const impl = L.checkResource(T, 1);
                const at_least = L.check(State.Integer, 2);
                const at_most = L.check(State.Integer, 3);

                const r: rand.Random = impl.random();

                return r.intRangeAtMostBiased(State.Integer, at_least, at_most);
            }

            pub fn intRangeAtMost(L: *State) !State.Integer {
                const impl = L.checkResource(T, 1);
                const at_least = L.check(State.Integer, 2);
                const at_most = L.check(State.Integer, 3);

                const r: rand.Random = impl.random();

                return r.intRangeAtMost(State.Integer, at_least, at_most);
            }

            pub fn float(L: *State) !State.Number {
                const impl = L.checkResource(T, 1);
                const r: rand.Random = impl.random();

                return r.float(State.Number);
            }

            pub fn floatExp(L: *State) !State.Number {
                const impl = L.checkResource(T, 1);
                const r: rand.Random = impl.random();

                return r.floatExp(State.Number);
            }

            pub fn floatNorm(L: *State) !State.Number {
                const impl = L.checkResource(T, 1);
                const r: rand.Random = impl.random();

                return r.floatNorm(State.Number);
            }
        };
    };
}

pub const bindings = struct {
    pub fn Ascon(L: *State) c_int {
        const secret = L.check([rand.Ascon.secret_seed_length]u8, 1);

        L.resource(rand.Ascon).* = rand.Ascon.init(secret);
        return 1;
    }

    pub fn ChaCha(L: *State) c_int {
        const secret = L.check([rand.ChaCha.secret_seed_length]u8, 1);

        L.resource(rand.ChaCha).* = rand.ChaCha.init(secret);
        return 1;
    }

    pub fn Isaac64(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.Isaac64).* = rand.Isaac64.init(seed);
        return 1;
    }

    pub fn Pcg(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.Pcg).* = rand.Pcg.init(seed);
        return 1;
    }

    pub fn Xoroshiro128(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.Xoroshiro128).* = rand.Xoroshiro128.init(seed);
        return 1;
    }

    pub fn Xoshiro256(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.Xoshiro256).* = rand.Xoshiro256.init(seed);
        return 1;
    }

    pub fn Sfc64(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.Sfc64).* = rand.Sfc64.init(seed);
        return 1;
    }

    pub fn RomuTrio(L: *State) c_int {
        const seed = L.check(u64, 1);

        L.resource(rand.RomuTrio).* = rand.RomuTrio.init(seed);
        return 1;
    }
};

pub const resources = .{
    .{ .type = rand.Ascon, .metatable = BindRandom(rand.Ascon) },
    .{ .type = rand.ChaCha, .metatable = BindRandom(rand.ChaCha) },

    .{ .type = rand.Isaac64, .metatable = BindRandom(rand.Isaac64) },
    .{ .type = rand.Pcg, .metatable = BindRandom(rand.Pcg) },
    .{ .type = rand.Xoroshiro128, .metatable = BindRandom(rand.Xoroshiro128) },
    .{ .type = rand.Xoshiro256, .metatable = BindRandom(rand.Xoshiro256) },
    .{ .type = rand.Sfc64, .metatable = BindRandom(rand.Sfc64) },
    .{ .type = rand.RomuTrio, .metatable = BindRandom(rand.RomuTrio) },
};
