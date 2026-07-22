const std = @import("std");
const filter = @import("../filter.zig");

test "django test compact success" {
    try filter.expectFixture(
        std.testing.allocator,
        .django_test,
        &.{},
        @embedFile("../testdata/django_test_raw.txt"),
        @embedFile("../testdata/django_test_filtered.txt"),
    );
}
