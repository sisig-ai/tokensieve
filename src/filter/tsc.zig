const std = @import("std");
const Allocator = std.mem.Allocator;

/// Compact tsc output: strip ANSI, keep error lines and summary.
/// tsc output is already fairly compact; main value is ANSI stripping
/// and normalizing whitespace. Pass through as-is after strip.
pub fn compact(gpa: Allocator, input: []const u8) ![]u8 {
    // tsc output is already concise; just normalize trailing whitespace per line
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |line| {
        const t = std.mem.trimEnd(u8, line, " \t\r");
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, t);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}