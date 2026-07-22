const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn argsAllowCompact(args: []const []const u8) bool {
    if (args.len == 0) return true;
    var i: usize = 0;
    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "-n")) {
            if (i + 1 >= args.len) return false;
            if (!isAllDigits(args[i + 1])) return false;
            i += 2;
            continue;
        }
        if (std.mem.startsWith(u8, a, "--max-count=")) {
            const v = a["--max-count=".len..];
            if (!isAllDigits(v)) return false;
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, a, "-n") and a.len > 2 and isAllDigits(a[2..])) {
            i += 1;
            continue;
        }
        return false;
    }
    return true;
}

fn isAllDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

fn looksLikeHex(s: []const u8) bool {
    if (s.len < 7) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

fn looksLikeOnelineLog(input: []const u8) bool {
    var lines: usize = 0;
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        lines += 1;
        const sp = std.mem.indexOfScalar(u8, t, ' ') orelse return false;
        if (!looksLikeHex(t[0..sp])) return false;
    }
    return lines > 0;
}

fn looksLikeDefaultLog(input: []const u8) bool {
    return std.mem.indexOf(u8, input, "\ncommit ") != null or std.mem.startsWith(u8, input, "commit ");
}

fn normalizeLines(gpa: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (it.next()) |line| {
        const t = std.mem.trimEnd(u8, line, " \t\r");
        if (t.len == 0) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, t);
        first = false;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}

/// Compact to hash+subject lines when input looks like default or oneline log.
pub fn compact(gpa: Allocator, input: []const u8) ![]u8 {
    if (looksLikeOnelineLog(input) and !looksLikeDefaultLog(input)) {
        return try normalizeLines(gpa, input);
    }
    if (!looksLikeDefaultLog(input)) {
        return try gpa.dupe(u8, input);
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = std.mem.splitScalar(u8, input, '\n');
    var hash: ?[]const u8 = null;
    var first = true;
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, line, "commit ")) {
            hash = std.mem.trim(u8, line["commit ".len..], " \t");
            continue;
        }
        if (hash == null) continue;
        if (std.mem.startsWith(u8, line, "Author:") or std.mem.startsWith(u8, line, "Date:") or
            std.mem.startsWith(u8, line, "Merge:") or std.mem.startsWith(u8, line, "AuthorDate:") or
            std.mem.startsWith(u8, line, "Commit:"))
        {
            continue;
        }
        if (line.len == 0) continue;
        const subject = std.mem.trim(u8, line, " \t");
        if (subject.len == 0) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, hash.?);
        try out.append(gpa, ' ');
        try out.appendSlice(gpa, subject);
        first = false;
        hash = null;
    }
    if (!first) try out.append(gpa, '\n');
    return try out.toOwnedSlice(gpa);
}
