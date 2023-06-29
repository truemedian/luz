const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");
const lua = @import("lua");

const State = lua.State;
const allocator = luz.allocator;

const time = std.time;

pub const bindings = struct {
    // Divisions of a nanosecond.
    pub const ns_per_us = time.ns_per_us;
    pub const ns_per_ms = time.ns_per_ms;
    pub const ns_per_s = time.ns_per_s;
    pub const ns_per_min = time.ns_per_min;
    pub const ns_per_hour = time.ns_per_hour;
    pub const ns_per_day = time.ns_per_day;
    pub const ns_per_week = time.ns_per_week;

    // Divisions of a microsecond.
    pub const us_per_ms = time.us_per_ms;
    pub const us_per_s = time.us_per_s;
    pub const us_per_min = time.us_per_min;
    pub const us_per_hour = time.us_per_hour;
    pub const us_per_day = time.us_per_day;
    pub const us_per_week = time.us_per_week;

    // Divisions of a millisecond.
    pub const ms_per_s = time.ms_per_s;
    pub const ms_per_min = time.ms_per_min;
    pub const ms_per_hour = time.ms_per_hour;
    pub const ms_per_day = time.ms_per_day;
    pub const ms_per_week = time.ms_per_week;

    // Divisions of a second.
    pub const s_per_min = time.s_per_min;
    pub const s_per_hour = time.s_per_hour;
    pub const s_per_day = time.s_per_day;
    pub const s_per_week = time.s_per_week;

    pub fn sleep(L: *State) void {
        const ms = L.check(f64, 1);
        if (ms < 0.0) return L.throw("sleep duration must be positive", .{});

        const sleeptime: u64 = @intFromFloat(ms * time.ns_per_ms);

        time.sleep(sleeptime);
    }

    pub fn timestamp(L: *State) c_int {
        const ns = time.nanoTimestamp();
        const seconds = @divTrunc(ns, time.ns_per_s);
        const nanoseconds = @rem(ns, time.ns_per_s);

        L.push(seconds);
        L.push(nanoseconds);
        return 2;
    }

    pub const Instant = struct {
        pub fn now(L: *State) !c_int {
            const this = L.resource(time.Instant);
            this.* = try time.Instant.now();

            return 1;
        }
    };

    pub const Timer = struct {
        pub fn start(L: *State) !c_int {
            const this = L.resource(time.Timer);
            this.* = try time.Timer.start();

            return 1;
        }
    };
};

pub const resources = .{
    .{ .type = time.Instant, .metatable = Instant.metatable },
    .{ .type = time.Timer, .metatable = Timer.metatable },
};

pub const Instant = struct {
    pub const bindings = struct {
        pub fn since(L: *State) i64 {
            const this = L.checkResource(time.Instant, 1);
            const other = L.checkResource(time.Instant, 2);

            if (this.order(other.*) == .lt) {
                const ns = std.math.lossyCast(i64, other.since(this.*));

                return -ns;
            } else {
                const ns = std.math.lossyCast(i64, this.since(other.*));

                return ns;
            }
        }
    };

    pub const metatable = struct {
        pub const __index = Instant.bindings;

        pub fn __sub(L: *State) !i64 {
            return Instant.bindings.since(L);
        }

        pub fn __eq(L: *State) !bool {
            const this = L.checkResource(time.Instant, 1);
            const other = L.checkResource(time.Instant, 2);

            return this.order(other.*) == .eq;
        }

        pub fn __lt(L: *State) !bool {
            const this = L.checkResource(time.Instant, 1);
            const other = L.checkResource(time.Instant, 2);

            return this.order(other.*) == .lt;
        }

        pub fn __le(L: *State) !bool {
            const this = L.checkResource(time.Instant, 1);
            const other = L.checkResource(time.Instant, 2);

            return !(this.order(other.*) == .gt);
        }
    };
};

pub const Timer = struct {
    pub const bindings = struct {
        pub fn read(L: *State) u64 {
            const timer = L.checkResource(time.Timer, 1);
            return timer.read();
        }

        pub fn reset(L: *State) void {
            const timer = L.checkResource(time.Timer, 1);
            return timer.reset();
        }

        pub fn lap(L: *State) u64 {
            const timer = L.checkResource(time.Timer, 1);
            return timer.lap();
        }
    };

    pub const metatable = struct {
        pub const __index = Timer.bindings;
    };
};
