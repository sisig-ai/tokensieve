const std = @import("std");
const filter = @import("../filter.zig");

test "git status compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .git_status,
        &.{},
        @embedFile("../testdata/git_status_raw.txt"),
        @embedFile("../testdata/git_status_filtered.txt"),
    );
}

test "git status with args is ansi-only" {
    const gpa = std.testing.allocator;
    const got = try filter.apply(gpa, .git_status, &.{"-sb"}, @embedFile("../testdata/git_status_raw.txt"));
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "(use \"git add") != null);
}
