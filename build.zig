const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "jjazy",
        .root_module = exe_mod,

        // debugger does not understand whatever zig generates
        // very well yet :/
        // .use_llvm = switch (optimize) {
        //     .Debug => false,
        //     else => null,
        // },
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const test_files = [_][]const u8{
        "src/utils.zig",
    };
    for (test_files) |file| {
        const unit_tests = b.addTest(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });
        const run_exe_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
