const std = @import("std");
const filter = @import("../filter.zig");

test "tsc compact normalizes whitespace" {
    const gpa = std.testing.allocator;
    const raw = @embedFile("../testdata/tsc_raw.txt");
    const expected = @embedFile("../testdata/tsc_filtered.txt");
    try filter.expectFixture(gpa, .tsc, &.{}, raw, expected);
}