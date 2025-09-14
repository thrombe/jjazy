const std = @import("std");

const Env = enum { prod, debug };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption(Env, "env", b.option(Env, "env", "prod / debug env") orelse .debug);

    const unicode_data = b.dependency("unicode_data", .{});
    const unicode_generate = b.addRunArtifact(b.addExecutable(.{
        .name = "unicode-generate",
        .root_source_file = b.path("src/unicode.zig"),
        .target = target,
        .optimize = optimize,
    }));
    unicode_generate.producer.?.root_module.addAnonymousImport("DerivedEastAsianWidth.txt", .{
        .root_source_file = unicode_data.path("DerivedEastAsianWidth.txt"),
    });
    unicode_generate.producer.?.root_module.addAnonymousImport("DerivedGeneralCategory.txt", .{
        .root_source_file = unicode_data.path("DerivedGeneralCategory.txt"),
    });

    if (true) {
        unicode_generate.addFileArg(b.path("./tmp/generate_test.bin"));
        unicode_generate.step.dependOn(b.getInstallStep());
        const generate_test_step = b.step("generate-test", "generate test");
        generate_test_step.dependOn(&unicode_generate.step);
        return;
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("options", options.createModule());
    exe_mod.addAnonymousImport("unicode-data.bin", .{
        .root_source_file = unicode_generate.addOutputFileArg("unicode-data.bin"),
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
    exe.linkLibC();

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
        "src/main.zig",
        "src/term.zig",
        "src/utils.zig",
    };
    for (test_files) |file| {
        const unit_tests = b.addTest(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });
        unit_tests.linkLibC();
        unit_tests.root_module.addImport("options", options.createModule());
        const run_exe_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
