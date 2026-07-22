const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return try gpa.dupe(u8, "eslint: ok\n");
    if (std.mem.indexOf(u8, input, "✖ 0 problems") != null) {
        return try gpa.dupe(u8, "eslint: ok\n");
    }
    return null;
}
