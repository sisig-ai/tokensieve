const std = @import("std");
const Allocator = std.mem.Allocator;

fn isGitHint(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t");
    return std.mem.startsWith(u8, t, "(use \"git");
}

/// Drop empty lines and git hint prose; keep branch/state/file lines.
pub fn compact(gpa: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |line| {
        const t = std.mem.trimEnd(u8, line, " \t\r");
        if (t.len == 0) continue;
        if (isGitHint(t)) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, t);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
