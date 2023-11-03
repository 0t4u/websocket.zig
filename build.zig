const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Zlib dependency
    const dep_zlib = b.dependency("zlib", .{});

    // Zlib headers path
    // https://github.com/ziglang/zig/issues/14719
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const zlib_install_path = dep_zlib.module("zlib").builder.install_path;
    const zlib_headers_rel = "/include/zlib";
    const zlib_headers = allocator.alloc(u8, zlib_install_path.len + zlib_headers_rel.len) catch {
        @panic("out of memory");
    };
    defer _ = allocator.free(zlib_headers);
    std.mem.copy(u8, zlib_headers[0..], zlib_install_path);
    std.mem.copy(u8, zlib_headers[zlib_install_path.len..], zlib_headers_rel);
    std.debug.print("zlib headers found at: {s}\n", .{zlib_headers});

    // Declare module to expose to package manager to make it available to downstream
    const mod = b.addModule("ws", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{.{ .name = "zlib", .module = dep_zlib.module("zlib") }},
    });

    const lib = b.addStaticLibrary(.{
        .name = "ws",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        // .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Link zlib
    lib.linkLibrary(b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    }).artifact("zlib"));
    lib.addModule("zlib", dep_zlib.module("zlib"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Link zlib
    main_tests.addIncludePath(.{ .path = zlib_headers });
    main_tests.linkLibrary(b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    }).artifact("zlib"));
    main_tests.addModule("zlib", dep_zlib.module("zlib"));

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // Build examples.
    const bin = b.addExecutable(.{
        .name = "autobahn_client",
        .root_source_file = .{ .path = "examples/autobahn_client.zig" },
        .target = target,
        .optimize = optimize,
    });
    bin.addIncludePath(.{ .path = zlib_headers });
    bin.linkLibrary(lib);
    bin.addModule("ws", mod);
    b.installArtifact(bin);
}
