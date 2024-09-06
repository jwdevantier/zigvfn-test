const std = @import("std");
const c = @cImport({
    @cInclude("vfn/nvme.h");
});

pub fn main() !void {
    const buf: []const u8 = "Hello, World!";
    const result = c.nvme_crc64(12345, buf.ptr, buf.len);
    std.debug.print("We built and interacted with libvfn! {x}\n", .{result});
}
