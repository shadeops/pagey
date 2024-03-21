const std = @import("std");

const raylib_build = @import("ext/raylib/src/build.zig");

fn build_flush(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.Mode) void {
    const exe = b.addExecutable(.{
        .name = "flush",
        .root_source_file = .{ .path = "src/flush.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("flush", "Flush pages");
    run_step.dependOn(&run_cmd.step);
}

fn build_pagey(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.Mode) void {
    const raylib = raylib_build.addRaylib(b, target, optimize, .{
        .raudio = false,
        .rmodels = false,
    });
    raylib.defineCMacro("GRAPHICS_API_OPENGL_43", "1");

    const exe = b.addExecutable(.{
        .name = "pagey",
        .root_source_file = .{ .path = "src/pagey.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(raylib);
    exe.addIncludePath(.{.path="ext/raylib/src"});
    exe.linkLibC();
    b.installArtifact(exe); 

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("pagey", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    build_flush(b, target, optimize);
    build_pagey(b, target, optimize);
}
