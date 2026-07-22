const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (std.mem.indexOf(u8, input, "All matched files use Prettier") == null) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        const t = std.mem.trim(u8, line, " \t");
        if (std.mem.eql(u8, t, "Checking formatting...")) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
