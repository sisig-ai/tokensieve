const std = @import("std");
const filter = @import("../filter.zig");
const git_log = @import("../filter/git_log.zig");

test "git log compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .git_log,
        &.{},
        @embedFile("../testdata/git_log_raw.txt"),
        @embedFile("../testdata/git_log_filtered.txt"),
    );
}

test "git log -n allows compact" {
    try filter.expectFixture(
        std.testing.allocator,
        .git_log,
        &.{ "-n", "5" },
        @embedFile("../testdata/git_log_raw.txt"),
        @embedFile("../testdata/git_log_filtered.txt"),
    );
}

test "git log -p no structural compact" {
    const gpa = std.testing.allocator;
    const got = try filter.apply(gpa, .git_log, &.{"-p"}, @embedFile("../testdata/git_log_patch_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "diff --git") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "Author:") != null);
}

test "gitLogArgsAllowCompact gating" {
    try std.testing.expect(git_log.argsAllowCompact(&.{}));
    try std.testing.expect(git_log.argsAllowCompact(&.{ "-n", "5" }));
    try std.testing.expect(git_log.argsAllowCompact(&.{"--max-count=3"}));
    try std.testing.expect(git_log.argsAllowCompact(&.{"-n10"}));
    try std.testing.expect(!git_log.argsAllowCompact(&.{"-p"}));
    try std.testing.expect(!git_log.argsAllowCompact(&.{"--stat"}));
    try std.testing.expect(!git_log.argsAllowCompact(&.{"--oneline"}));
}
