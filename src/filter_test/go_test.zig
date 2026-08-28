const std = @import("std");
const filter = @import("../filter.zig");

test "go_test compact keeps only failures and summary" {
    const gpa = std.testing.allocator;
    const raw = @embedFile("../testdata/go_test_raw.txt");
    const expected = @embedFile("../testdata/go_test_filtered.txt");
    try filter.expectFixture(gpa, .go_test, &.{}, raw, expected);
}