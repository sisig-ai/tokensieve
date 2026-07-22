const std = @import("std");
const Allocator = std.mem.Allocator;

fn isCargoOkLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "test ") and std.mem.endsWith(u8, line, " ... ok");
}

fn isCargoRunningLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "running ") and std.mem.indexOf(u8, line, " test") != null;
}

fn cargoAllPassShape(input: []const u8) bool {
    var saw_ok_result = false;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, line, "test result:")) {
            if (std.mem.indexOf(u8, line, "test result: ok.") == null) return false;
            if (std.mem.indexOf(u8, line, "0 failed") == null) return false;
            saw_ok_result = true;
        }
        if (std.mem.startsWith(u8, line, "test ") and std.mem.endsWith(u8, line, " ... FAILED")) return false;
    }
    return saw_ok_result;
}

/// Drop per-test ok lines when suite all-pass; keep summary. Else null (ANSI-only).
pub fn compact(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!cargoAllPassShape(input)) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (isCargoOkLine(line) or isCargoRunningLine(line)) continue;
        const trimmed = std.mem.trimStart(u8, line, " ");
        if (std.mem.startsWith(u8, trimmed, "Compiling ") or
            std.mem.startsWith(u8, trimmed, "Finished ") or
            std.mem.startsWith(u8, trimmed, "Downloading ") or
            std.mem.startsWith(u8, trimmed, "Downloaded "))
        {
            continue;
        }
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
