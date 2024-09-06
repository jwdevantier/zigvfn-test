const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("libvfn", .{});

    const ccan = b.addStaticLibrary(.{
        .name = "ccan",
        .target = target,
        .optimize = optimize,
    });

    const ccan_config_h = b.addConfigHeader(.{
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
        .HAVE_BUILTIN_CPU_SUPPORTS = !target.result.cpu.arch.isAARCH64(), // Not available on ARM
        .HAVE_BUILTIN_EXPECT = true,
        .HAVE_BUILTIN_TYPES_COMPATIBLE_P = true,
        .HAVE_CLOCK_GETTIME = true,
        .HAVE_COMPOUND_LITERALS = true,
        .HAVE_ERR_H = true,
        .HAVE_ISBLANK = true,
        .HAVE_STATEMENT_EXPR = true,
        .HAVE_STRUCT_TIMESPEC = true,
        .HAVE_SYS_UNISTD_H = true,
        .HAVE_TYPEOF = true,
        .HAVE_WARN_UNUSED_RESULT = true,
    });

    ccan.addConfigHeader(ccan_config_h);
    ccan.addIncludePath(upstream.path("ccan"));

    ccan.installConfigHeader(ccan_config_h);
    ccan.installHeadersDirectory(upstream.path("ccan"), "", .{});

    ccan.linkLibC();

    ccan.addCSourceFiles(.{
        .root = upstream.path("ccan"),
        .files = &.{
            "ccan/err/err.c",
            "ccan/list/list.c",
            "ccan/opt/helpers.c",
            "ccan/opt/opt.c",
            "ccan/opt/parse.c",
            "ccan/opt/usage.c",
            "ccan/str/str.c",
            "ccan/tap/tap.c",
            "ccan/time/time.c",
        },
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=gnu11",
            "-Werror",
        },
    });

    const gentable_crc64 = b.addExecutable(.{
        .name = "gentable-crc64",
        .target = b.host,
        .optimize = .Debug,
    });

    gentable_crc64.addConfigHeader(ccan_config_h);
    gentable_crc64.addIncludePath(upstream.path("ccan"));

    gentable_crc64.linkLibC();

    gentable_crc64.addCSourceFile(.{
        .file = upstream.path("lib/gentable-crc64.c"),
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=gnu11",
            "-Werror",
        },
    });

    const run_gentable_crc64 = b.addRunArtifact(gentable_crc64);
    const crc64table_h = run_gentable_crc64.captureStdOut();

    // Override the default name for the captured output.
    // This is a bit of a hack since there's no public API for specifying the output filename.
    run_gentable_crc64.captured_stdout.?.basename = "crc64table.h";

    const libvfn = b.addSharedLibrary(.{
        .name = "vfn",
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 5, .minor = 1, .patch = 0 },
    });

    // The meson project is directly including the generated 'config-host.h', not its directory.
    // I don't think this is supported by Zig.
    // But since it's just two simple macros, it's easier to just pass '-DNVME_AQ_QSIZE=32'.
    libvfn.defineCMacro("NVME_AQ_QSIZE", "32");

    // Commented out code preserved for posterity.
    //const libvfn_config_host_h = b.addConfigHeader(.{
    //    .include_path = "config-host.h",
    //}, .{
    //    .HAVE_VFIO_DEVICE_BIND_IOMMUFD = null,
    //    .NVME_AQ_QSIZE = 32,
    //});

    //libvfn.addConfigHeader(libvfn_config_host_h);
    libvfn.addIncludePath(upstream.path("src"));
    libvfn.addIncludePath(upstream.path("include"));
    libvfn.addIncludePath(b.path("vendor"));
    libvfn.addIncludePath(crc64table_h.dirname());

    libvfn.installHeadersDirectory(upstream.path("include"), "", .{});
    libvfn.installHeadersDirectory(b.path("vendor"), "", .{});

    libvfn.linkLibC();
    libvfn.linkSystemLibrary("pthread");
    libvfn.linkLibrary(ccan);

    const libvfn_c_flags: []const []const u8 = &.{
        "-Wall",
        "-Wextra",
        "-std=gnu11",
        "-Werror",
        "-Wconversion",
        "-Wdouble-promotion",
        "-Wundef",
        "-Wno-trigraphs",
        "-Wdeclaration-after-statement",
        "-Wvla",
        "-Wno-sign-conversion",
        "-fno-strict-overflow",
    };
    libvfn.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "trace.c",
            "support/io.c",
            "support/log.c",
            "support/mem.c",
            "support/ticks.c",
            "support/timer.c",
            "util/skiplist.c",
            "pci/util.c",
            "iommu/context.c",
            "iommu/dma.c",
            "iommu/vfio.c",
            //"iommu/iommufd.c", // Only include if HAVE_VFIO_DEVICE_BIND_IOMMUFD is truthy.
            "vfio/device.c",
            "vfio/pci.c",
            "nvme/core.c",
            "nvme/queue.c",
            "nvme/util.c",
            "nvme/rq.c",
        },
        .flags = libvfn_c_flags,
    });
    if (target.result.cpu.arch == .x86_64) {
        libvfn.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{
                "support/arch/x86_64/rdtsc.c",
            },
            .flags = libvfn_c_flags,
        });
    }
    libvfn.addCSourceFiles(.{
        .root = b.path("vendor"),
        .files = &.{
            "vfn/trace/events.c",
        },
        .flags = libvfn_c_flags,
    });

    b.installArtifact(libvfn);

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(libvfn);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the exe!!");
    run_step.dependOn(&run_exe.step);
}
