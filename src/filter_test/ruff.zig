const std = @import("std");
const filter = @import("../filter.zig");

test "ruff all checks passed is ok" {
    try filter.expectFixture(
        std.testing.allocator,
        .ruff,
        &.{},
        @embedFile("../testdata/ruff_clean_raw.txt"),
        @embedFile("../testdata/ruff_clean_filtered.txt"),
    );
}

test "ruff format already formatted is ok" {
    try filter.expectFixture(
        std.testing.allocator,
        .ruff,
        &.{ "format", "--check" },
        @embedFile("../testdata/ruff_format_clean_raw.txt"),
        @embedFile("../testdata/ruff_format_clean_filtered.txt"),
    );
}

test "ruff with diagnostics is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\foo.py:1:8: F401 [*] `os` imported but unused
        \\Found 1 error.
        \\[*] 1 fixable with the `--fix` option.
        \\
    ;
    const got = try filter.apply(gpa, .ruff, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "F401") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "ruff: ok") == null);
}
