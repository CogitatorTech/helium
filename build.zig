const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Library Setup ---
    const lib_source = b.path("src/lib.zig");

    // This creates the "helium" module, makes it available to other packages,
    // and returns a reference to it.
    const lib_module = b.addModule("helium", .{
        .root_source_file = lib_source,
        .target = target,
        .optimize = optimize,
    });

    // Then, we use the same module for the library artifact.
    const lib = b.addLibrary(.{
        .name = "helium",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    // --- Docs Setup ---
    const docs_step = b.step("docs", "Generate API documentation");
    const doc_install_path = "docs/api";

    // This command remains the same, but the directory creation can be improved.
    const gen_docs_cmd = b.addSystemCommand(&[_][]const u8{
        b.graph.zig_exe, // Use the same zig that is running the build
        "build-lib",
        "src/lib.zig",
        "-femit-docs=" ++ doc_install_path,
    });

    // Using `b.addSystemCommand` for `mkdir` is not portable (e.g., to Windows).
    // For this case it is acceptable, but for broader compatibility,
    // a RunStep with `std.fs.makeDir` would be better.
    const mkdir_cmd = b.addSystemCommand(&[_][]const u8{
        "mkdir", "-p", doc_install_path,
    });
    gen_docs_cmd.step.dependOn(&mkdir_cmd.step);

    docs_step.dependOn(&gen_docs_cmd.step);

    // --- Test Setup ---
    // The test runner also consumes a module now.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // --- Example Setup ---
    const examples_path = "examples";
    // This block gracefully handles the case where the examples directory doesn't exist.
    examples_blk: {
        var examples_dir = fs.cwd().openDir(examples_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound or err == error.NotDir) break :examples_blk;
            @panic("Can't open 'examples' directory");
        };
        defer examples_dir.close();

        var dir_iter = examples_dir.iterate();
        while (dir_iter.next() catch @panic("Failed to iterate examples")) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

            const exe_name = fs.path.stem(entry.name);
            const exe_path = b.fmt("{s}/{s}", .{ examples_path, entry.name });

            // Create a module for the executable.
            const exe_module = b.createModule(.{
                .root_source_file = b.path(exe_path),
                .target = target,
                .optimize = optimize,
            });
            // Add the main library as a dependency to the executable's module.
            exe_module.addImport("helium", lib_module);

            // Create the executable artifact from the module.
            const exe = b.addExecutable(.{
                .name = exe_name,
                .root_module = exe_module,
            });
            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            const run_step_name = b.fmt("run-{s}", .{exe_name});
            const run_step_desc = b.fmt("Run the {s} example", .{exe_name});
            const run_step = b.step(run_step_name, run_step_desc);
            run_step.dependOn(&run_cmd.step);
        }
    }
}

