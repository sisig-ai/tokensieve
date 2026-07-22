const std = @import("std");
const Allocator = std.mem.Allocator;

fn isDjangoOkLine(line: []const u8) bool {
    return std.mem.endsWith(u8, line, " ... ok");
}

fn isDjangoDbLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "Creating test database") or
        std.mem.startsWith(u8, line, "Destroying test database");
}

fn isDjangoOkSummary(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    return std.mem.eql(u8, t, "OK") or std.mem.startsWith(u8, t, "OK (");
}

fn djangoAllPassShape(input: []const u8) bool {
    var saw_ok = false;
    var saw_ran = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (std.mem.endsWith(u8, line, " ... FAIL")) return false;
        if (std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "FAILED (")) return false;
        if (isDjangoOkSummary(line)) saw_ok = true;
        if (std.mem.startsWith(u8, line, "Ran ") and std.mem.indexOf(u8, line, " test") != null) saw_ran = true;
    }
    return saw_ok and saw_ran;
}

pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!djangoAllPassShape(input)) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (isDjangoOkLine(line) or isDjangoDbLine(line)) continue;
        if (!first) try out.append(gpa, '\n');
        if (isDjangoOkSummary(line)) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
