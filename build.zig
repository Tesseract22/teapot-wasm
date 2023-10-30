const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.

pub fn build(b: *std.Build) void {
    const target = std.zig.CrossTarget {.cpu_arch = .wasm32, .os_tag = .freestanding};
    const optimize = b.standardOptimizeOption(.{.preferred_optimize_mode = .ReleaseSafe});
    const wasm = b.addSharedLibrary(.{
        .name = "graphic",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/wasm.zig" },
        .target = target,
        .optimize = optimize,
    });
    wasm.addSystemIncludePath(.{.path = "src"});
    wasm.rdynamic = true;
    wasm.import_memory = true;
    b.installArtifact(wasm);

    b.getInstallStep().dependOn(&b.addInstallFile(wasm.getEmittedBin(), "../docs/teapot.wasm").step);
    
    const exe = b.addExecutable(.{
        .name = "graphic",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
