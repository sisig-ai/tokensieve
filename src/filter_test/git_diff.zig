const std = @import("std");
const filter = @import("../filter.zig");

test "strip ansi" {
    const gpa = std.testing.allocator;
    const got = try filter.stripAnsi(gpa, "a\x1b[31mRED\x1b[0mb");
    defer gpa.free(got);
    try std.testing.expectEqualStrings("aREDb", got);
}

test "git diff ansi only" {
    try filter.expectFixture(
        std.testing.allocator,
        .git_diff,
        &.{},
        @embedFile("../testdata/git_diff_raw.txt"),
        @embedFile("../testdata/git_diff_filtered.txt"),
    );
}
