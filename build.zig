const std = @import("std");

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

    // zig uses a recent copy of clang, so we support all this stuff
    const config_h = b.addConfigHeader(.{
        // various ccan files use '#include "config.h"'
        // don't know if I can scope this better.
        .include_path = "config.h",
    }, .{
        .HAVE_ATTRIBUTE_COLD = true,
        .HAVE_ATTRIBUTE_CONST = true,
        .HAVE_ATTRIBUTE_DEPRECATED = true,
        .HAVE_ATTRIBUTE_NONNULL = true,
        .HAVE_ATTRIBUTE_NORETURN = true,
        .HAVE_ATTRIBUTE_PRINTF = true,
        .HAVE_ATTRIBUTE_PURE = true,
        .HAVE_ATTRIBUTE_RETURNS_NONNULL = true,
        .HAVE_ATTRIBUTE_SENTINEL = true,
        .HAVE_ATTRIBUTE_UNUSED = true,
        .HAVE_ATTRIBUTE_USED = true,
        .HAVE_BUILTIN_CHOOSE_EXPR = true,
        .HAVE_BUILTIN_CONSTANT_P = true,
        .HAVE_BUILTIN_CPU_SUPPORTS = true,
        .HAVE_BUILTIN_EXPECT = true,
        .HAVE_BUILTIN_TYPES_COMPATIBLE_P = true,
        .HAVE_STRUCT_TIMESPEC = true,
        .HAVE_CLOCK_GETTIME = true,
        .HAVE_COMPOUND_LITERALS = true,
        .HAVE_ERR_H = true,
        .HAVE_ISBLANK = true,
        .HAVE_STATEMENT_EXPR = true,
        .HAVE_SYS_UNISTD_H = true,
        .HAVE_TYPEOF = true,
        .HAVE_WARN_UNUSED_RESULT = true,
    });

    lib.addConfigHeader(config_h);

    buildTraceFiles(b, upstream, lib, &cflags);

    return lib;
}

fn buildTraceFiles(b: *Build, upstream: *Build.Dependency, lib: *Step.Compile, cflags: []const []const u8) void {
    // Trace Files
    //
    // TODO: Generate from config file
    // In the meson project, it defaults to using ./config/trace-events-all as input
    // and calls:
    // perl scripts/trace.pl --mode source ./config/trace-events-all >> ./src/trace/events.c
    // perl scripts/trace.pl --mode header ./config/trace-events-all >> ./include/vfn/trace/events.h

    _ = upstream;

    var writer = b.addWriteFiles();

    const events_c = writer.add("src/trace/events.c",
        \\#include <stdbool.h>
        \\
        \\#include "vfn/trace/events.h"
        \\#include "trace.h"
        \\
        \\bool TRACE_NVME_CQ_GET_CQE_ACTIVE;
        \\bool TRACE_NVME_CQ_GOT_CQE_ACTIVE;
        \\bool TRACE_NVME_CQ_SPIN_ACTIVE;
        \\bool TRACE_NVME_CQ_UPDATE_HEAD_ACTIVE;
        \\bool TRACE_NVME_SQ_POST_ACTIVE;
        \\bool TRACE_NVME_SQ_UPDATE_TAIL_ACTIVE;
        \\bool TRACE_NVME_SKIP_MMIO_ACTIVE;
        \\bool TRACE_IOMMUFD_IOAS_MAP_DMA_ACTIVE;
        \\bool TRACE_IOMMUFD_IOAS_UNMAP_DMA_ACTIVE;
        \\bool TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_ACTIVE;
        \\bool TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_ACTIVE;
        \\bool TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_ACTIVE;
        \\
        \\struct trace_event trace_events[] = {
        \\    {"nvme_cq_get_cqe", &TRACE_NVME_CQ_GET_CQE_ACTIVE},
        \\    {"nvme_cq_got_cqe", &TRACE_NVME_CQ_GOT_CQE_ACTIVE},
        \\    {"nvme_cq_spin", &TRACE_NVME_CQ_SPIN_ACTIVE},
        \\    {"nvme_cq_update_head", &TRACE_NVME_CQ_UPDATE_HEAD_ACTIVE},
        \\    {"nvme_sq_post", &TRACE_NVME_SQ_POST_ACTIVE},
        \\    {"nvme_sq_update_tail", &TRACE_NVME_SQ_UPDATE_TAIL_ACTIVE},
        \\    {"nvme_skip_mmio", &TRACE_NVME_SKIP_MMIO_ACTIVE},
        \\    {"iommufd_ioas_map_dma", &TRACE_IOMMUFD_IOAS_MAP_DMA_ACTIVE},
        \\    {"iommufd_ioas_unmap_dma", &TRACE_IOMMUFD_IOAS_UNMAP_DMA_ACTIVE},
        \\    {"vfio_iommu_type1_map_dma", &TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_ACTIVE},
        \\    {"vfio_iommu_type1_unmap_dma", &TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_ACTIVE},
        \\    {"vfio_iommu_type1_recycle_ephemeral_iovas", &TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_ACTIVE},
        \\};
        \\
        \\int TRACE_NUM_EVENTS = 12;
    );

    _ = writer.add("vfn/trace/events.h",
        \\#define TRACE_NVME_CQ_GET_CQE "nvme_cq_get_cqe"
        \\#define TRACE_NVME_CQ_GOT_CQE "nvme_cq_got_cqe"
        \\#define TRACE_NVME_CQ_SPIN "nvme_cq_spin"
        \\#define TRACE_NVME_CQ_UPDATE_HEAD "nvme_cq_update_head"
        \\#define TRACE_NVME_SQ_POST "nvme_sq_post"
        \\#define TRACE_NVME_SQ_UPDATE_TAIL "nvme_sq_update_tail"
        \\#define TRACE_NVME_SKIP_MMIO "nvme_skip_mmio"
        \\#define TRACE_IOMMUFD_IOAS_MAP_DMA "iommufd_ioas_map_dma"
        \\#define TRACE_IOMMUFD_IOAS_UNMAP_DMA "iommufd_ioas_unmap_dma"
        \\#define TRACE_VFIO_IOMMU_TYPE1_MAP_DMA "vfio_iommu_type1_map_dma"
        \\#define TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA "vfio_iommu_type1_unmap_dma"
        \\#define TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS "vfio_iommu_type1_recycle_ephemeral_iovas"
        \\
        \\#define TRACE_NVME_CQ_GET_CQE_DISABLED 1
        \\#define TRACE_NVME_CQ_GOT_CQE_DISABLED 0
        \\#define TRACE_NVME_CQ_SPIN_DISABLED 0
        \\#define TRACE_NVME_CQ_UPDATE_HEAD_DISABLED 0
        \\#define TRACE_NVME_SQ_POST_DISABLED 0
        \\#define TRACE_NVME_SQ_UPDATE_TAIL_DISABLED 0
        \\#define TRACE_NVME_SKIP_MMIO_DISABLED 0
        \\#define TRACE_IOMMUFD_IOAS_MAP_DMA_DISABLED 0
        \\#define TRACE_IOMMUFD_IOAS_UNMAP_DMA_DISABLED 0
        \\#define TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_DISABLED 0
        \\#define TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_DISABLED 0
        \\#define TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_DISABLED 0
        \\
        \\extern bool TRACE_NVME_CQ_GET_CQE_ACTIVE;
        \\extern bool TRACE_NVME_CQ_GOT_CQE_ACTIVE;
        \\extern bool TRACE_NVME_CQ_SPIN_ACTIVE;
        \\extern bool TRACE_NVME_CQ_UPDATE_HEAD_ACTIVE;
        \\extern bool TRACE_NVME_SQ_POST_ACTIVE;
        \\extern bool TRACE_NVME_SQ_UPDATE_TAIL_ACTIVE;
        \\extern bool TRACE_NVME_SKIP_MMIO_ACTIVE;
        \\extern bool TRACE_IOMMUFD_IOAS_MAP_DMA_ACTIVE;
        \\extern bool TRACE_IOMMUFD_IOAS_UNMAP_DMA_ACTIVE;
        \\extern bool TRACE_VFIO_IOMMU_TYPE1_MAP_DMA_ACTIVE;
        \\extern bool TRACE_VFIO_IOMMU_TYPE1_UNMAP_DMA_ACTIVE;
        \\extern bool TRACE_VFIO_IOMMU_TYPE1_RECYCLE_EPHEMERAL_IOVAS_ACTIVE;
    );

    // Add the generated C file to the library
    lib.addCSourceFile(.{ .file = events_c, .flags = cflags });

    // make generated events.h file available for inclusion
    lib.addIncludePath(writer.getDirectory());
    lib.addSystemIncludePath(writer.getDirectory());
}
