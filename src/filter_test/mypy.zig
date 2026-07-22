const std = @import("std");
const filter = @import("../filter.zig");

test "mypy success is ok" {
    try filter.expectFixture(
        std.testing.allocator,
        .mypy,
        &.{},
        @embedFile("../testdata/mypy_clean_raw.txt"),
        @embedFile("../testdata/mypy_clean_filtered.txt"),
    );
}

test "mypy with errors is ansi-only" {
    const gpa = std.testing.allocator;
    const raw =
        \\foo.py:1: error: Incompatible types in assignment (expression has type "str", variable has type "int")  [assignment]
        \\Found 1 error in 1 file (checked 1 source file)
        \\
    ;
    const got = try filter.apply(gpa, .mypy, &.{}, raw);
    defer gpa.free(got);
    try std.testing.expect(std.mem.indexOf(u8, got, "Incompatible types") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "mypy: ok") == null);
}
