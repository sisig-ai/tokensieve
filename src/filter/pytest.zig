const std = @import("std");
const Allocator = std.mem.Allocator;

fn pytestAllPassShape(input: []const u8) bool {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r=");
        if (std.mem.indexOf(u8, line, " failed") != null or std.mem.indexOf(u8, line, " error") != null) {
            if (std.mem.indexOf(u8, line, "passed") != null or std.mem.indexOf(u8, line, "failed") != null) {
                if (std.mem.indexOf(u8, line, " failed") != null) return false;
            }
        }
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, raw, " \t"), "FAILED ")) return false;
    }
    var it2 = std.mem.splitScalar(u8, input, '\n');
    while (it2.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.indexOf(u8, t, "passed") != null and std.mem.indexOf(u8, t, " in ") != null) {
            return std.mem.indexOf(u8, t, " failed") == null and std.mem.indexOf(u8, t, " error") == null;
        }
    }
    return false;
}

fn isPytestPassedLine(line: []const u8) bool {
    const t = std.mem.trimEnd(u8, line, " \t\r");
    return std.mem.indexOf(u8, t, " PASSED") != null;
}

fn isPytestProgressLine(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    if (t.len == 0) return false;
    if (std.mem.indexOf(u8, t, ".py ") == null) return false;
    return std.mem.indexOf(u8, t, "[") != null and std.mem.indexOf(u8, t, "%]") != null;
}

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!pytestAllPassShape(input)) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (isPytestPassedLine(line)) continue;
        if (isPytestProgressLine(line)) continue;
        const t = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "===") and std.mem.indexOf(u8, t, "test session starts") != null) continue;
        if (std.mem.startsWith(u8, t, "platform ")) continue;
        if (std.mem.startsWith(u8, t, "cachedir:")) continue;
        if (std.mem.startsWith(u8, t, "rootdir:")) continue;
        if (std.mem.startsWith(u8, t, "plugins:")) continue;
        if (std.mem.startsWith(u8, t, "collected ")) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
