const std = @import("std");
const filter = @import("../filter.zig");
const grep = @import("../filter/grep.zig");

test "grep compact truncates and caps" {
    try filter.expectFixture(
        std.testing.allocator,
        .grep,
        &.{ "pattern", "src" },
        @embedFile("../testdata/grep_raw.txt"),
        @embedFile("../testdata/grep_filtered.txt"),
    );
}

test "grep short output keeps lines" {
    try filter.expectFixture(
        std.testing.allocator,
        .grep,
        &.{},
        @embedFile("../testdata/grep_short_raw.txt"),
        @embedFile("../testdata/grep_short_filtered.txt"),
    );
}

test "grep --json is ansi-only" {
    const gpa = std.testing.allocator;
    const got = try filter.apply(gpa, .grep, &.{"--json"}, @embedFile("../testdata/grep_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "… +") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "path/file_155.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\x1b[") == null);
}

test "grepArgsAllowCompact gating" {
    try std.testing.expect(grep.argsAllowCompact(&.{}));
    try std.testing.expect(grep.argsAllowCompact(&.{ "foo", "bar" }));
    try std.testing.expect(!grep.argsAllowCompact(&.{"--json"}));
    try std.testing.expect(!grep.argsAllowCompact(&.{"--json=true"}));
}
