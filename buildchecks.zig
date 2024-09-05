const std = @import("std");
const Build = std.Build;
const ResolvedTarget = std.Build.ResolvedTarget;

fn hasFeature(b: *Build, target: ResolvedTarget, code: []const u8) bool {
    const check_step = b.addExecutable(.{
        .name = "check",
        .root_source_file = b.addWriteFiles().add("dummy.zig", ""),
        .target = target,
        .optimize = .Debug,
    });
    const c_file = b.addWriteFiles().add("check.c", code);
    check_step.addCSourceFile(.{ .file = c_file, .flags = &.{} });
    check_step.linkLibC();
    _ = check_step.getEmittedBin();
    return true;
}

pub fn hasAttribute(b: *Build, target: ResolvedTarget, attr: []const u8) bool {
    const code = b.fmt(
        \\static __attribute__(({s})) void func() {{}}
        \\int main() {{ return 0; }}
    , .{attr});
    return hasFeature(b, target, code);
}

pub fn hasSentinelAttribute(b: *Build, target: ResolvedTarget) bool {
    const code =
        \\#include <stddef.h>
        \\static __attribute__((sentinel)) void func(int x, ...) {}
        \\int main() { return 0; }
    ;
    return hasFeature(b, target, code);
}

pub fn hasBuiltin(b: *Build, target: ResolvedTarget, builtin: []const u8) bool {
    const code = b.fmt(
        \\int main() {{ return {s}(1,2) ? 0 : 1; }}
    , .{builtin});
    return hasFeature(b, target, code);
}

pub fn hasType(b: *Build, target: ResolvedTarget, type_name: []const u8, prefix: []const u8) bool {
    const code = b.fmt(
        \\{s}
        \\int main() {{ {s} t; return sizeof(t); }}
    , .{ prefix, type_name });
    return hasFeature(b, target, code);
}

pub fn hasFunction(b: *Build, target: ResolvedTarget, func: []const u8, prefix: []const u8) bool {
    const code = b.fmt(
        \\{s}
        \\int main() {{ return (void*){s} != 0; }}
    , .{ prefix, func });
    return hasFeature(b, target, code);
}

pub fn hasCompoundLiterals(b: *Build, target: ResolvedTarget) bool {
    const code =
        \\int main() { int *foo = (int[]){1, 2, 3, 4}; return 0; }
    ;
    return hasFeature(b, target, code);
}

pub fn hasHeader(b: *Build, target: ResolvedTarget, header: []const u8) bool {
    const code = b.fmt(
        \\#include <{s}>
        \\int main() {{ return 0; }}
    , .{header});
    return hasFeature(b, target, code);
}

pub fn hasStatementExpr(b: *Build, target: ResolvedTarget) bool {
    const code =
        \\int main() { return ({ int x = 1; x; }); }
    ;
    return hasFeature(b, target, code);
}

pub fn hasTypeof(b: *Build, target: ResolvedTarget) bool {
    const code =
        \\int main() { int x; __typeof__(x) y; return 0; }
    ;
    return hasFeature(b, target, code);
}
