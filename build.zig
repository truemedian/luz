const std = @import("std");

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) void {
    const strip = b.option(bool, "strip", "strip debug symbols") orelse false;
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const tests = b.step("test", "Test for all Lua versions");

    const lua_mod = b.addModule("lua", .{
        .source_file = .{ .path = "lib/binding.zig" },
    });

    inline for (.{ "5.1", "5.2", "5.3", "5.4" }) |ver| {
        const shared = b.addSharedLibrary(.{
            .name = "luz",
            .root_source_file = .{ .path = "src/main.zig" },
            .optimize = optimize,
            .target = target,
        });

        shared.addModule("lua", lua_mod);

        shared.strip = strip;
        shared.linkSystemLibrary("lua-" ++ ver);
        shared.linkLibC();

        const install = b.addInstallArtifact(shared);
        install.dest_dir = .{ .custom = "lib/lua/" ++ ver ++ "/" };
        install.dest_sub_path = "luz.so";

        const step = b.step("install-" ++ ver, "Build Luz for Lua " ++ ver);
        step.dependOn(&install.step);

        b.getInstallStep().dependOn(step);

        const zig_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .optimize = optimize,
            .target = target,
        });
        zig_tests.linkSystemLibrary("lua-" ++ ver);
        zig_tests.linkLibC();

        zig_tests.addModule("lua", lua_mod);

        const run_tests = b.addSystemCommand(&.{
            "busted",           "--cpath=" ++ comptime root() ++ "/zig-out/lib/lua/" ++ ver ++ "/?.so",
            "--lua=lua" ++ ver, "--sort",
        });

        run_tests.step.dependOn(&install.step);

        const run_zig_tests = b.addRunArtifact(zig_tests);

        const tests_step = b.step("test-" ++ ver, "Test using Lua " ++ ver);
        tests_step.dependOn(&run_zig_tests.step);
        tests_step.dependOn(&run_tests.step);

        tests.dependOn(tests_step);
    }
}
