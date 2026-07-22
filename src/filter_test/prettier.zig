const std = @import("std");
const filter = @import("../filter.zig");

test "prettier compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .prettier,
        &.{},
        @embedFile("../testdata/prettier_raw.txt"),
        @embedFile("../testdata/prettier_filtered.txt"),
    );
}
