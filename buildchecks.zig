const std = @import("std");

pub fn hasAttribute(b: *std.Build, attr: []const u8) bool {
    const code = std.fmt.allocPrint(b.allocator,
        \\static __attribute__(({s})) void func() {{}}
        \\int main() {{ return 0; }}
    , .{attr}) catch unreachable;
    return b.cc.compiles(code);
}

pub fn hasSentinelAttribute(b: *std.Build) bool {
    const code =
        \\#include <stddef.h>
        \\static __attribute__((sentinel)) void func(int x, ...) {}
        \\int main() { return 0; }
    ;
    return b.cc.compiles(code);
}

pub fn hasBuiltin(b: *std.Build, builtin: []const u8) bool {
    const code = std.fmt.allocPrint(b.allocator,
        \\int main() {{ return {s}(1,2) ? 0 : 1; }}
    , .{builtin}) catch unreachable;
    return b.cc.compiles(code);
}

pub fn hasType(b: *std.Build, type_name: []const u8, prefix: []const u8) bool {
    const code = std.fmt.allocPrint(b.allocator,
        \\{s}
        \\int main() {{ {s} t; return sizeof(t); }}
    , .{ prefix, type_name }) catch unreachable;
    return b.cc.compiles(code);
}

pub fn hasFunction(b: *std.Build, func: []const u8, prefix: []const u8) bool {
    const code = std.fmt.allocPrint(b.allocator,
        \\{s}
        \\int main() {{ return (void*){s} != 0; }}
    , .{ prefix, func }) catch unreachable;
    return b.cc.compiles(code);
}

pub fn hasCompoundLiterals(b: *std.Build) bool {
    const code =
        \\int main() { int *foo = (int[]){1, 2, 3, 4}; return 0; }
    ;
    return b.cc.compiles(code);
}

pub fn hasHeader(b: *std.Build, header: []const u8) bool {
    const code = std.fmt.allocPrint(b.allocator,
        \\#include <{s}>
        \\int main() {{ return 0; }}
    , .{header}) catch unreachable;
    return b.cc.compiles(code);
}

pub fn hasStatementExpr(b: *std.Build) bool {
    const code =
        \\int main() { return ({ int x = 1; x; }); }
    ;
    return b.cc.compiles(code);
}

pub fn hasTypeof(b: *std.Build) bool {
    const code =
        \\int main() { int x; __typeof__(x) y; return 0; }
    ;
    return b.cc.compiles(code);
}
