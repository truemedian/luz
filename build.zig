const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const shared = b.addSharedLibrary("luz", "src/main.zig", .unversioned);
    shared.setBuildMode(b.standardReleaseOptions());
    shared.setTarget(b.standardTargetOptions(.{}));

    shared.linkSystemLibrary("lua5.1");
    shared.linkLibC();

    shared.install();
}
