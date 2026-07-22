const std = @import("std");
const filter = @import("../filter.zig");

test "cargo test compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .cargo_test,
        &.{},
        @embedFile("../testdata/cargo_test_raw.txt"),
        @embedFile("../testdata/cargo_test_filtered.txt"),
    );
}
