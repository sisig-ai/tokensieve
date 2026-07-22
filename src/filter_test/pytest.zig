const std = @import("std");
const filter = @import("../filter.zig");

test "pytest compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .pytest,
        &.{},
        @embedFile("../testdata/pytest_raw.txt"),
        @embedFile("../testdata/pytest_filtered.txt"),
    );
}
