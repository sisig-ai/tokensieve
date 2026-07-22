const std = @import("std");
const Allocator = std.mem.Allocator;

fn mypyCleanShape(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return true;
    if (std.mem.indexOf(u8, input, "Success: no issues found") != null) return true;
    return false;
}

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!mypyCleanShape(input)) return null;
    return try gpa.dupe(u8, "mypy: ok\n");
}
