const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const include_paths_install = [_][]const u8{
    "include/vfn/iommu",
    "include/vfn/nvme",
    "include/vfn/pci",
    "include/vfn/support",
    "include/vfn/support/arch/arm64",
    "include/vfn/support/arch/x86_64",
    "include/vfn/trace",
    "include/vfn/vfio",
    "include/vfn",
};

const include_paths = include_paths_install ++ [_][]const u8{
    "src/",
    "ccan/",
};

pub fn build(b: *std.Build) void {
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;

    const zigvfn = b.addModule("zigvfn", .{
        .root_source_file = b.path("src/vfn.zig"),
    });

    const config = b.addOptions();
    // TODO add declared build options
    zigvfn.addOptions("config", config);

    const upstream = b.dependency("libvfn", .{});

    const lib = buildLibVfn(b, target, optimize, upstream, shared);

    b.installArtifact(lib);

    for (include_paths) |ipath| {
        zigvfn.addIncludePath(upstream.path(ipath));
    }

    // TODO: how would I generate the trace files?

    zigvfn.linkLibrary(lib);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zigvfn", zigvfn);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zigvfn tests");
    test_step.dependOn(&run_tests.step);
}

fn buildLibVfn(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, shared: bool) *Step.Compile {
    const lib_opts = .{
        .name = "vfn",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 5, .minor = 1, .patch = 0 },
    };

    switch (target.result.os.tag) {
        .linux => {},
        else => {
            std.debug.panic("libvfn, used by ziglua, is only supported for Linux", .{});
        },
    }

    const lib = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

    for (include_paths) |ipath| {
        lib.addIncludePath(upstream.path(ipath));
    }

    const flags = [_][]const u8{
        "-Wall",
        "-Wextra",
        "-std=gnu11",
        "-Werror",
        "-D_GNU_SOURCE",
        "-DLIBVFN_VERSION=\"5.1.0\"",
    };

    const sources = [_][]const u8{
        "src/pci/util.c",
        "src/iommu/context.c",
        "src/iommu/vfio.c",
        "src/iommu/iommufd.c",
        "src/iommu/dma.c",
        "src/trace.c",
        "src/support/ticks_test.c",
        "src/support/ticks.c",
        "src/support/timer.c",
        "src/support/io.c",
        "src/support/mem.c",
        "src/support/arch/x86_64/rdtsc.c",
        "src/support/log.c",
        "src/nvme/rq_test.c",
        "src/nvme/core.c",
        "src/nvme/rq.c",
        "src/nvme/util.c",
        "src/nvme/queue.c",
        "src/util/skiplist_test.c",
        "src/util/skiplist.c",
        "src/vfio/device.c",
        "src/vfio/pci.c",
        "ccan/ccan/tap/tap.c",
        "ccan/ccan/err/err.c",
        "ccan/ccan/opt/usage.c",
        "ccan/ccan/opt/helpers.c",
        "ccan/ccan/opt/parse.c",
        "ccan/ccan/opt/opt.c",
        "ccan/ccan/str/str.c",
        "ccan/ccan/str/debug.c",
        "ccan/ccan/list/list.c",
        "ccan/ccan/time/time.c",
    };

    lib.addCSourceFiles(.{
        .root = .{
            .dependency = .{
                .dependency = upstream,
                .sub_path = "",
            },
        },
        .files = &sources,
        .flags = &flags,
    });

    lib.linkLibC();

    for (include_paths_install) |ipath| {
        lib.installHeadersDirectory(upstream.path(ipath), ipath["include/".len..], .{});
    }

    return lib;
}

pub fn buildOld(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zigvfn",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/vfn.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/vfn.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
