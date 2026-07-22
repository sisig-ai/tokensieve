const std = @import("std");
const Allocator = std.mem.Allocator;

const GREP_MAX_LINE_LEN: usize = 120;
const GREP_MAX_LINES: usize = 150;

pub fn argsAllowCompact(args: []const []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--json")) return false;
        if (std.mem.startsWith(u8, a, "--json=")) return false;
    }
    return true;
}

/// Truncate each line to GREP_MAX_LINE_LEN and hard-cap GREP_MAX_LINES (+N more).
pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var kept: usize = 0;
    var total_nonempty: usize = 0;
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        total_nonempty += 1;
        if (kept >= GREP_MAX_LINES) continue;
        if (!first) try out.append(gpa, '\n');
        if (line.len > GREP_MAX_LINE_LEN) {
            try out.appendSlice(gpa, line[0..GREP_MAX_LINE_LEN]);
            try out.appendSlice(gpa, "…");
        } else {
            try out.appendSlice(gpa, line);
        }
        first = false;
        kept += 1;
    }
    if (kept == 0) return try gpa.dupe(u8, input);
    if (total_nonempty > GREP_MAX_LINES) {
        try out.append(gpa, '\n');
        var buf: [64]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "… +{d} more lines", .{total_nonempty - GREP_MAX_LINES});
        try out.appendSlice(gpa, msg);
    }
    try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
