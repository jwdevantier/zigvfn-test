const std = @import("std");
const buildchecks = @import("buildchecks.zig");

const Build = std.Build;
const Step = std.Build.Step;

const include_paths_install = [_][]const u8{
    "include/vfn",
    "include/vfn/iommu",
    "include/vfn/nvme",
    "include/vfn/pci",
    "include/vfn/support",
    "include/vfn/support/arch/arm64",
    "include/vfn/support/arch/x86_64",
    "include/vfn/trace",
    "include/vfn/vfio",
};

const include_paths = include_paths_install ++ [_][]const u8{
    "src",
    "ccan",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Check if the target OS is Linux
    if (target.result.os.tag != .linux) {
        std.debug.panic("libvfn only supports Linux", .{});
    }

    // Check if the target architecture is supported
    switch (target.result.cpu.arch) {
        .x86_64, .aarch64 => {},
        else => std.debug.panic("libvfn only supports x86_64 and aarch64 architectures", .{}),
    }

    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;
    const enable_debug = b.option(bool, "enable-debug", "Enable debug build") orelse false;
    const enable_profiling = b.option(bool, "enable-profiling", "Enable profiling") orelse false;

    const zigvfn = b.addModule("zigvfn", .{
        .root_source_file = b.path("src/vfn.zig"),
    });

    const config = b.addOptions();
    // TODO: add declared build options
    zigvfn.addOptions("config", config);

    const upstream = b.dependency("libvfn", .{});

    const lib = buildLibVfn(b, target, optimize, upstream, shared, enable_debug, enable_profiling);

    b.installArtifact(lib);

    for (include_paths) |ipath| {
        zigvfn.addIncludePath(upstream.path(ipath));
    }

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

fn buildLibVfn(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    upstream: *Build.Dependency,
    shared: bool,
    enable_debug: bool,
    enable_profiling: bool,
) *Step.Compile {
    const lib = if (shared)
        b.addSharedLibrary(.{
            .name = "vfn",
            .target = target,
            .optimize = optimize,
            .version = .{ .major = 5, .minor = 1, .patch = 0 },
        })
    else
        b.addStaticLibrary(.{
            .name = "vfn",
            .target = target,
            .optimize = optimize,
        });

    const cflags = [_][]const u8{
        "-Wall",
        "-Wextra",
        "-Werror",
        "-std=gnu11",
        "-D_GNU_SOURCE",
        "-Wconversion",
        "-Wdouble-promotion",
        "-Wundef",
        "-Wno-trigraphs",
        "-Wdeclaration-after-statement",
        "-Wvla",
        "-Wno-sign-conversion",
        "-fno-strict-overflow",
    };

    if (enable_debug) {
        lib.defineCMacro("DEBUG", null);
    }

    if (enable_profiling) {
        lib.addCSourceFile(.{ .file = upstream.path("src/profiling.c"), .flags = &(cflags ++ [_][]const u8{"-pg"}) });
    }

    const core_sources = [_][]const u8{
        "src/trace.c",
        "src/support/io.c",
        "src/support/log.c",
        "src/support/mem.c",
        "src/support/ticks.c",
        "src/support/timer.c",
        "src/util/skiplist.c",
        "src/pci/util.c",
        "src/iommu/context.c",
        "src/iommu/dma.c",
        "src/iommu/vfio.c",
        "src/vfio/device.c",
        "src/vfio/pci.c",
        "src/nvme/core.c",
        "src/nvme/queue.c",
        "src/nvme/util.c",
        "src/nvme/rq.c",
    };

    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &core_sources,
        .flags = &cflags,
    });

    // Add architecture-specific sources
    switch (target.result.cpu.arch) {
        .x86_64 => {
            const arch_sources = [_][]const u8{"src/support/arch/x86_64/rdtsc.c"};
            lib.addCSourceFiles(.{
                .root = .{ .dependency = .{
                    .dependency = upstream,
                    .sub_path = "",
                } },
                .files = &arch_sources,
                .flags = &cflags,
            });
        },
        .aarch64 => {
            // Add aarch64-specific sources if any
        },
        else => unreachable,
    }

    // Add iommufd.c if HAVE_VFIO_DEVICE_BIND_IOMMUFD is defined
    // TODO: Implement proper detection or option for this
    if (b.option(bool, "have-iommufd", "Include iommufd support") orelse false) {
        const iommufd_sources = [_][]const u8{"src/iommu/iommufd.c"};
        lib.addCSourceFiles(.{
            .root = .{ .dependency = .{
                .dependency = upstream,
                .sub_path = "",
            } },
            .files = &iommufd_sources,
            .flags = &cflags,
        });
    }

    lib.addSystemIncludePath(upstream.path("include/"));
    for (include_paths) |ipath| {
        const path = upstream.path(ipath);
        lib.addIncludePath(path);
        lib.addSystemIncludePath(path);
    }

    // Link with threads (unconditionally, as we're guaranteed to be on Linux)
    lib.linkLibC();
    lib.linkSystemLibrary("pthread");

    for (include_paths_install) |ipath| {
        lib.installHeadersDirectory(upstream.path(ipath), ipath["include/".len..], .{});
    }

    const config_h = b.addConfigHeader(.{
        .include_path = "ccan/config.h",
    }, .{
        .HAVE_ATTRIBUTE_COLD = buildchecks.hasAttribute(b, "cold"),
        .HAVE_ATTRIBUTE_CONST = buildchecks.hasAttribute(b, "const"),
        .HAVE_ATTRIBUTE_DEPRECATED = buildchecks.hasAttribute(b, "deprecated"),
        .HAVE_ATTRIBUTE_NONNULL = buildchecks.hasAttribute(b, "nonnull"),
        .HAVE_ATTRIBUTE_NORETURN = buildchecks.hasAttribute(b, "noreturn"),
        .HAVE_ATTRIBUTE_PRINTF = buildchecks.hasAttribute(b, "format"),
        .HAVE_ATTRIBUTE_PURE = buildchecks.hasAttribute(b, "pure"),
        .HAVE_ATTRIBUTE_RETURNS_NONNULL = buildchecks.hasAttribute(b, "returns_nonnull"),
        .HAVE_ATTRIBUTE_SENTINEL = buildchecks.hasSentinelAttribute(b),
        .HAVE_ATTRIBUTE_UNUSED = buildchecks.hasAttribute(b, "unused"),
        .HAVE_ATTRIBUTE_USED = buildchecks.hasAttribute(b, "used"),
        .HAVE_BUILTIN_CHOOSE_EXPR = buildchecks.hasBuiltin(b, "__builtin_choose_expr"),
        .HAVE_BUILTIN_CONSTANT_P = buildchecks.hasBuiltin(b, "__builtin_constant_p"),
        .HAVE_BUILTIN_CPU_SUPPORTS = buildchecks.hasBuiltin(b, "__builtin_cpu_supports"),
        .HAVE_BUILTIN_EXPECT = buildchecks.hasBuiltin(b, "__builtin_expect"),
        .HAVE_BUILTIN_TYPES_COMPATIBLE_P = buildchecks.hasBuiltin(b, "__builtin_types_compatible_p"),
        .HAVE_STRUCT_TIMESPEC = buildchecks.hasType(b, "struct timespec", "#include <time.h>"),
        .HAVE_CLOCK_GETTIME = buildchecks.hasFunction(b, "clock_gettime", "#include <time.h>"),
        .HAVE_COMPOUND_LITERALS = buildchecks.hasCompoundLiterals(b),
        .HAVE_ERR_H = buildchecks.hasHeader(b, "err.h"),
        .HAVE_ISBLANK = buildchecks.hasFunction(b, "isblank", "#include <ctype.h>"),
        .HAVE_STATEMENT_EXPR = buildchecks.hasStatementExpr(b),
        .HAVE_SYS_UNISTD_H = buildchecks.hasHeader(b, "sys/unistd.h"),
        .HAVE_TYPEOF = buildchecks.hasTypeof(b),
        .HAVE_WARN_UNUSED_RESULT = buildchecks.hasAttribute(b, "warn_unused_result"),
    });

    lib.addConfigHeader(config_h);

    return lib;
}
