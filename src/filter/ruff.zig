const std = @import("std");
const Allocator = std.mem.Allocator;

fn ruffCleanShape(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return true;
    if (std.mem.indexOf(u8, input, "All checks passed!") != null) return true;
    if (std.mem.indexOf(u8, input, " already formatted") != null) {
        return std.mem.indexOf(u8, input, "Would reformat") == null;
    }
    return false;
}

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!ruffCleanShape(input)) return null;
    return try gpa.dupe(u8, "ruff: ok\n");
}
