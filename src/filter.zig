const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Kind = enum {
    git_status,
    git_log,
    git_diff,
    cargo_test,
    pytest,
    bun_test,
    eslint,
    prettier,
    django_test,
    ruff,
    mypy,
    grep,
};

pub const Ctx = struct {
    kind: Kind,
    args: []const []const u8,
};

pub fn callback(ptr: ?*const anyopaque, gpa: Allocator, stdout: []const u8) anyerror![]u8 {
    const ctx: *const Ctx = @ptrCast(@alignCast(ptr orelse return error.MissingFilterCtx));
    return apply(gpa, ctx.kind, ctx.args, stdout);
}

/// bun writes pass/fail/summary to stderr; merge streams before filtering on success.
pub fn shouldMergeStreams(ptr: ?*const anyopaque) bool {
    const ctx: *const Ctx = @ptrCast(@alignCast(ptr orelse return false));
    return ctx.kind == .bun_test;
}

pub fn apply(gpa: Allocator, kind: Kind, args: []const []const u8, stdout: []const u8) ![]u8 {
    const stripped = try stripAnsi(gpa, stdout);
    errdefer gpa.free(stripped);

    const compacted: ?[]u8 = switch (kind) {
        .git_status => if (args.len == 0) try compactGitStatus(gpa, stripped) else null,
        .git_log => if (gitLogArgsAllowCompact(args)) try compactGitLog(gpa, stripped) else null,
        .git_diff => null,
        .cargo_test => try compactCargoTest(gpa, stripped),
        .pytest => try compactPytest(gpa, stripped),
        .bun_test => try compactBunTest(gpa, stripped),
        .eslint => try compactEslint(gpa, stripped),
        .prettier => try compactPrettier(gpa, stripped),
        .django_test => try compactDjangoTest(gpa, stripped),
        .ruff => try compactRuff(gpa, stripped),
        .mypy => try compactMypy(gpa, stripped),
        .grep => if (grepArgsAllowCompact(args)) try compactGrep(gpa, stripped) else null,
    };

    if (compacted) |c| {
        gpa.free(stripped);
        return c;
    }
    return stripped;
}

pub fn stripAnsi(gpa: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            i += 2;
            while (i < input.len) : (i += 1) {
                const c = input[i];
                if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    i += 1;
                    break;
                }
            }
            continue;
        }
        try out.append(gpa, input[i]);
        i += 1;
    }
    return try out.toOwnedSlice(gpa);
}

fn gitLogArgsAllowCompact(args: []const []const u8) bool {
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

fn isGitHint(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t");
    return std.mem.startsWith(u8, t, "(use \"git");
}

/// Drop empty lines and git hint prose; keep branch/state/file lines.
fn compactGitStatus(gpa: Allocator, input: []const u8) ![]u8 {
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

/// Compact to hash+subject lines when input looks like default or oneline log.
fn compactGitLog(gpa: Allocator, input: []const u8) ![]u8 {
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
        // subject is first non-empty body line (often indented with 4 spaces)
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
fn compactCargoTest(gpa: Allocator, input: []const u8) !?[]u8 {
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

fn pytestAllPassShape(input: []const u8) bool {
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r=");
        if (std.mem.indexOf(u8, line, " failed") != null or std.mem.indexOf(u8, line, " error") != null) {
            if (std.mem.indexOf(u8, line, "passed") != null or std.mem.indexOf(u8, line, "failed") != null) {
                // summary with failures
                if (std.mem.indexOf(u8, line, " failed") != null) return false;
            }
        }
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, raw, " \t"), "FAILED ")) return false;
    }
    // need a passed summary
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
    // e.g. tests/test_foo.py .....                                            [100%]
    if (std.mem.indexOf(u8, t, ".py ") == null) return false;
    return std.mem.indexOf(u8, t, "[") != null and std.mem.indexOf(u8, t, "%]") != null;
}

fn compactPytest(gpa: Allocator, input: []const u8) !?[]u8 {
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
    // e.g. "0 fail" or " 0 fail"
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
fn compactBunTest(gpa: Allocator, input: []const u8) !?[]u8 {
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
            // blank after version line
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

fn compactEslint(gpa: Allocator, input: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return try gpa.dupe(u8, "eslint: ok\n");
    if (std.mem.indexOf(u8, input, "✖ 0 problems") != null) {
        return try gpa.dupe(u8, "eslint: ok\n");
    }
    return null;
}

fn compactPrettier(gpa: Allocator, input: []const u8) !?[]u8 {
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

fn ruffCleanShape(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return true;
    if (std.mem.indexOf(u8, input, "All checks passed!") != null) return true;
    // ruff format --check success: "N file(s) already formatted"
    if (std.mem.indexOf(u8, input, " already formatted") != null) {
        // reject "Would reformat"
        return std.mem.indexOf(u8, input, "Would reformat") == null;
    }
    return false;
}

fn compactRuff(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!ruffCleanShape(input)) return null;
    return try gpa.dupe(u8, "ruff: ok\n");
}

fn mypyCleanShape(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return true;
    // Success: no issues found in 1 source file
    // Success: no issues found in 12 source files
    if (std.mem.indexOf(u8, input, "Success: no issues found") != null) return true;
    return false;
}

fn compactMypy(gpa: Allocator, input: []const u8) !?[]u8 {
    if (!mypyCleanShape(input)) return null;
    return try gpa.dupe(u8, "mypy: ok\n");
}

const GREP_MAX_LINE_LEN: usize = 120;
const GREP_MAX_LINES: usize = 150;

fn grepArgsAllowCompact(args: []const []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--json")) return false;
        if (std.mem.startsWith(u8, a, "--json=")) return false;
    }
    return true;
}

/// Truncate each line to GREP_MAX_LINE_LEN and hard-cap GREP_MAX_LINES (+N more).
fn compactGrep(gpa: Allocator, input: []const u8) !?[]u8 {
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

fn compactDjangoTest(gpa: Allocator, input: []const u8) !?[]u8 {
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

fn expectFixture(gpa: Allocator, kind: Kind, args: []const []const u8, input: []const u8, expected: []const u8) !void {
    const got = try apply(gpa, kind, args, input);
    defer gpa.free(got);
    try std.testing.expectEqualStrings(expected, got);
}

test "strip ansi" {
    const gpa = std.testing.allocator;
    const got = try stripAnsi(gpa, "a\x1b[31mRED\x1b[0mb");
    defer gpa.free(got);
    try std.testing.expectEqualStrings("aREDb", got);
}

test "git status compact success" {
    try expectFixture(
        std.testing.allocator,
        .git_status,
        &.{},
        @embedFile("testdata/git_status_raw.txt"),
        @embedFile("testdata/git_status_filtered.txt"),
    );
}

test "git status with args is ansi-only" {
    const gpa = std.testing.allocator;
    const got = try apply(gpa, .git_status, &.{"-sb"}, @embedFile("testdata/git_status_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "(use \"git add") != null);
}

test "git log compact success" {
    try expectFixture(
        std.testing.allocator,
        .git_log,
        &.{},
        @embedFile("testdata/git_log_raw.txt"),
        @embedFile("testdata/git_log_filtered.txt"),
    );
}

test "git log -n allows compact" {
    try expectFixture(
        std.testing.allocator,
        .git_log,
        &.{ "-n", "5" },
        @embedFile("testdata/git_log_raw.txt"),
        @embedFile("testdata/git_log_filtered.txt"),
    );
}

test "git log -p no structural compact" {
    const gpa = std.testing.allocator;
    const got = try apply(gpa, .git_log, &.{"-p"}, @embedFile("testdata/git_log_patch_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "diff --git") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "Author:") != null);
}

test "git diff ansi only" {
    try expectFixture(
        std.testing.allocator,
        .git_diff,
        &.{},
        @embedFile("testdata/git_diff_raw.txt"),
        @embedFile("testdata/git_diff_filtered.txt"),
    );
}

test "cargo test compact success" {
    try expectFixture(
        std.testing.allocator,
        .cargo_test,
        &.{},
        @embedFile("testdata/cargo_test_raw.txt"),
        @embedFile("testdata/cargo_test_filtered.txt"),
    );
}

test "pytest compact success" {
    try expectFixture(
        std.testing.allocator,
        .pytest,
        &.{},
        @embedFile("testdata/pytest_raw.txt"),
        @embedFile("testdata/pytest_filtered.txt"),
    );
}

test "bun test compact success" {
    try expectFixture(
        std.testing.allocator,
        .bun_test,
        &.{},
        @embedFile("testdata/bun_test_raw.txt"),
        @embedFile("testdata/bun_test_filtered.txt"),
    );
}

test "eslint empty is ok" {
    try expectFixture(
        std.testing.allocator,
        .eslint,
        &.{},
        @embedFile("testdata/eslint_clean_raw.txt"),
        @embedFile("testdata/eslint_clean_filtered.txt"),
    );
}

test "eslint zero problems is ok" {
    try expectFixture(
        std.testing.allocator,
        .eslint,
        &.{},
        @embedFile("testdata/eslint_zero_problems_raw.txt"),
        @embedFile("testdata/eslint_zero_problems_filtered.txt"),
    );
}

test "eslint with problems is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\/tmp/foo.ts
        \\  1:1  error  unused  no-unused-vars
        \\
        \\✖ 1 problem (1 error, 0 warnings)
        \\
    ;
    const got = try apply(gpa, .eslint, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "✖ 1 problem") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "eslint: ok") == null);
}

test "prettier compact success" {
    try expectFixture(
        std.testing.allocator,
        .prettier,
        &.{},
        @embedFile("testdata/prettier_raw.txt"),
        @embedFile("testdata/prettier_filtered.txt"),
    );
}

test "django test compact success" {
    try expectFixture(
        std.testing.allocator,
        .django_test,
        &.{},
        @embedFile("testdata/django_test_raw.txt"),
        @embedFile("testdata/django_test_filtered.txt"),
    );
}

test "ruff all checks passed is ok" {
    try expectFixture(
        std.testing.allocator,
        .ruff,
        &.{},
        @embedFile("testdata/ruff_clean_raw.txt"),
        @embedFile("testdata/ruff_clean_filtered.txt"),
    );
}

test "ruff format already formatted is ok" {
    try expectFixture(
        std.testing.allocator,
        .ruff,
        &.{ "format", "--check" },
        @embedFile("testdata/ruff_format_clean_raw.txt"),
        @embedFile("testdata/ruff_format_clean_filtered.txt"),
    );
}

test "ruff with diagnostics is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\foo.py:1:8: F401 [*] `os` imported but unused
        \\Found 1 error.
        \\[*] 1 fixable with the `--fix` option.
        \\
    ;
    const got = try apply(gpa, .ruff, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "F401") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "ruff: ok") == null);
}

test "mypy success is ok" {
    try expectFixture(
        std.testing.allocator,
        .mypy,
        &.{},
        @embedFile("testdata/mypy_clean_raw.txt"),
        @embedFile("testdata/mypy_clean_filtered.txt"),
    );
}

test "mypy with errors is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\foo.py:1: error: Incompatible types in assignment (expression has type "str", variable has type "int")  [assignment]
        \\Found 1 error in 1 file (checked 1 source file)
        \\
    ;
    const got = try apply(gpa, .mypy, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "Incompatible types") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "mypy: ok") == null);
}

test "grep compact truncates and caps" {
    try expectFixture(
        std.testing.allocator,
        .grep,
        &.{ "pattern", "src" },
        @embedFile("testdata/grep_raw.txt"),
        @embedFile("testdata/grep_filtered.txt"),
    );
}

test "grep short output keeps lines" {
    try expectFixture(
        std.testing.allocator,
        .grep,
        &.{},
        @embedFile("testdata/grep_short_raw.txt"),
        @embedFile("testdata/grep_short_filtered.txt"),
    );
}

test "grep --json is ansi-only" {
    const gpa = std.testing.allocator;
    const got = try apply(gpa, .grep, &.{"--json"}, @embedFile("testdata/grep_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "… +") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "path/file_155.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\x1b[") == null);
}

test "grepArgsAllowCompact gating" {
    try std.testing.expect(grepArgsAllowCompact(&.{}));
    try std.testing.expect(grepArgsAllowCompact(&.{ "foo", "bar" }));
    try std.testing.expect(!grepArgsAllowCompact(&.{"--json"}));
    try std.testing.expect(!grepArgsAllowCompact(&.{"--json=true"}));
}

test "gitLogArgsAllowCompact gating" {
    try std.testing.expect(gitLogArgsAllowCompact(&.{}));
    try std.testing.expect(gitLogArgsAllowCompact(&.{ "-n", "5" }));
    try std.testing.expect(gitLogArgsAllowCompact(&.{"--max-count=3"}));
    try std.testing.expect(gitLogArgsAllowCompact(&.{"-n10"}));
    try std.testing.expect(!gitLogArgsAllowCompact(&.{"-p"}));
    try std.testing.expect(!gitLogArgsAllowCompact(&.{"--stat"}));
    try std.testing.expect(!gitLogArgsAllowCompact(&.{"--oneline"}));
}
