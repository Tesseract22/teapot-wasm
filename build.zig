const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.

pub fn build(b: *std.Build) !void {
    const target = std.zig.CrossTarget {.cpu_arch = .wasm32, .os_tag = .freestanding};
    const optimize = b.standardOptimizeOption(.{.preferred_optimize_mode = .ReleaseSafe});

    const canvas_module = b.createModule(.{.source_file = .{.path = "src/canvas.zig"}});
    try b.modules.put(b.dupe("Canvas"), canvas_module);

    var demo_dir = try std.fs.cwd().openIterableDir("src/demo/", .{.access_sub_paths = false});
    defer demo_dir.close();
    var demo_iter  = demo_dir.iterate();
    var path_buf = [_]u8 {0} ** 1024;

    while (try demo_iter.next()) |entry| {
        if (entry.kind != .file) continue;
        const path = try std.fmt.bufPrint(&path_buf, "src/demo/{s}", .{entry.name});
        var name = blk: {
            var it = std.mem.splitScalar(u8, entry.name, '.');
            break :blk it.next() orelse unreachable;
        };
        const wasm = b.addSharedLibrary(.{
            .name = name,
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = .{.path = path },
            .target = target,
            .optimize = optimize,
        });
        wasm.rdynamic = true;
        wasm.import_memory = true;
        wasm.addModule("Canvas", canvas_module);
        b.installArtifact(wasm);
        const docs_path = try std.fmt.bufPrint(&path_buf, "../docs/{s}.wasm", .{name});
        b.getInstallStep().dependOn(&b.addInstallFile(wasm.getEmittedBin(), docs_path).step);

    }

    
    
    
    // const exe = b.addExecutable(.{
    //     .name = "graphic",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = .{ .path = "src/demo/main.zig" },
    //     .target = b.standardTargetOptions(.{}),
    //     .optimize = b.standardOptimizeOption(.{}),
    // });
    // exe.addModule("Canvas", canvas_module);
    // b.installArtifact(exe);

    // const run_cmd = b.addRunArtifact(exe);

    // // By making the run step depend on the install step, it will be run from the
    // // installation directory rather than directly from within the cache directory.
    // // This is not necessary, however, if the application depends on other installed
    // // files, this ensures they will be present and in the expected location.
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
}
