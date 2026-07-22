const std = @import("std");
const filter = @import("../filter.zig");

test "bun test compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .bun_test,
        &.{},
        @embedFile("../testdata/bun_test_raw.txt"),
        @embedFile("../testdata/bun_test_filtered.txt"),
    );
}
