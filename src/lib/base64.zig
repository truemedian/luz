const std = @import("std");
const builtin = @import("builtin");

const luz = @import("../main.zig");
const lua = @import("lua");

const State = lua.State;
const allocator = luz.allocator;

const base64 = std.base64;

pub const bindings = struct {
    pub const standard = struct {
        pub fn encode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = base64.standard.Encoder.calcSize(str.len);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            const encoded = base64.standard.Encoder.encode(buf, str);
            L.push(encoded);

            return 1;
        }

        pub fn decode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = try base64.standard.Decoder.calcSizeForSlice(str);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            try base64.standard.Decoder.decode(buf, str);
            L.push(buf);

            return 1;
        }
    };

    pub const standard_no_pad = struct {
        pub fn encode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = base64.standard_no_pad.Encoder.calcSize(str.len);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            const encoded = base64.standard_no_pad.Encoder.encode(buf, str);
            L.push(encoded);

            return 1;
        }

        pub fn decode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = try base64.standard_no_pad.Decoder.calcSizeForSlice(str);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            try base64.standard_no_pad.Decoder.decode(buf, str);
            L.push(buf);

            return 1;
        }
    };

    pub const url_safe = struct {
        pub fn encode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = base64.url_safe.Encoder.calcSize(str.len);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            const encoded = base64.url_safe.Encoder.encode(buf, str);
            L.push(encoded);

            return 1;
        }

        pub fn decode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = try base64.url_safe.Decoder.calcSizeForSlice(str);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            try base64.url_safe.Decoder.decode(buf, str);
            L.push(buf);

            return 1;
        }
    };

    pub const url_safe_no_pad = struct {
        pub fn encode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = base64.url_safe_no_pad.Encoder.calcSize(str.len);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            const encoded = base64.url_safe_no_pad.Encoder.encode(buf, str);
            L.push(encoded);

            return 1;
        }

        pub fn decode(L: *State) !c_int {
            const str = L.check([]const u8, 1);
            const len = try base64.url_safe_no_pad.Decoder.calcSizeForSlice(str);

            const buf = try allocator.alloc(u8, len);
            defer allocator.free(buf);

            try base64.url_safe_no_pad.Decoder.decode(buf, str);
            L.push(buf);

            return 1;
        }
    };
};

pub const resources = .{};
