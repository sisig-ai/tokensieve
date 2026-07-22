const std = @import("std");
const Allocator = std.mem.Allocator;

fn isBunPassLine(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "(pass)");
}

fn isBunFailLine(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "(fail)");
}

fn isBunFileHeader(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    if (t.len < 2 or t[t.len - 1] != ':') return false;
    const name = t[0 .. t.len - 1];
    return std.mem.endsWith(u8, name, ".test.ts") or
        std.mem.endsWith(u8, name, ".test.js") or
        std.mem.endsWith(u8, name, ".test.tsx") or
        std.mem.endsWith(u8, name, ".test.jsx");
}

fn bunSummaryHasZeroFail(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    if (std.mem.eql(u8, t, "0 fail")) return true;
    if (std.mem.endsWith(u8, t, " fail")) {
        const n = std.mem.trim(u8, t[0 .. t.len - " fail".len], " \t");
        return std.mem.eql(u8, n, "0");
    }
    return false;
}

fn bunSummaryHasPass(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    return std.mem.endsWith(u8, t, " pass") and t.len > " pass".len;
}

fn bunAllPassShape(input: []const u8) bool {
    var saw_pass = false;
    var saw_zero_fail = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (isBunFailLine(line)) return false;
        if (bunSummaryHasPass(line)) saw_pass = true;
        if (bunSummaryHasZeroFail(line)) saw_zero_fail = true;
    }
    return saw_pass and saw_zero_fail;
}

/// Drop (pass) lines and bare file headers when all-pass; keep version + summary.
pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!bunAllPassShape(input)) return null;

    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (isBunPassLine(line) or isBunFileHeader(line)) continue;
        try kept.append(gpa, line);
    }
    if (kept.items.len == 0) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (kept.items, 0..) |line, i| {
        if (i > 0) {
            if (i == 1 and std.mem.startsWith(u8, kept.items[0], "bun test ")) {
                try out.append(gpa, '\n');
            }
            try out.append(gpa, '\n');
        }
        try out.appendSlice(gpa, line);
    }
    try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
