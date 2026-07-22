const std = @import("std");
const filter = @import("../filter.zig");

test "eslint empty is ok" {
    try filter.expectFixture(
        std.testing.allocator,
        .eslint,
        &.{},
        @embedFile("../testdata/eslint_clean_raw.txt"),
        @embedFile("../testdata/eslint_clean_filtered.txt"),
    );
}

test "eslint zero problems is ok" {
    try filter.expectFixture(
        std.testing.allocator,
        .eslint,
        &.{},
        @embedFile("../testdata/eslint_zero_problems_raw.txt"),
        @embedFile("../testdata/eslint_zero_problems_filtered.txt"),
    );
}

test "eslint with problems is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\/tmp/foo.ts
        \\  1:1  error  unused  no-unused-vars
        \\
        \\✖ 1 problem (1 error, 0 warnings)
        \\
    ;
    const got = try filter.apply(gpa, .eslint, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "✖ 1 problem") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "eslint: ok") == null);
}
