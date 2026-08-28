const std = @import("std");
const Allocator = std.mem.Allocator;

/// Compact go test output: keep only FAIL lines and the final summary.
/// Drop RUN, PASS, and individual log lines to reduce token count.
pub fn compact(gpa: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |line| {
        const t = std.mem.trimEnd(u8, line, " \t\r");
        if (t.len == 0) continue;
        // Keep --- FAIL: lines and tab-separated FAIL/ok summary lines
        const is_fail_line = std.mem.startsWith(u8, t, "--- FAIL:");
        const is_summary = std.mem.indexOfScalar(u8, t, '\t') != null and
            (std.mem.startsWith(u8, t, "FAIL\t") or std.mem.startsWith(u8, t, "ok\t"));
        if (!is_fail_line and !is_summary) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, t);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}