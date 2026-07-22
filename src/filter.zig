const std = @import("std");
const Allocator = std.mem.Allocator;

const git_status = @import("filter/git_status.zig");
const git_log = @import("filter/git_log.zig");
const cargo_test = @import("filter/cargo_test.zig");
const pytest = @import("filter/pytest.zig");
const bun_test = @import("filter/bun_test.zig");
const eslint = @import("filter/eslint.zig");
const prettier = @import("filter/prettier.zig");
const django_test = @import("filter/django_test.zig");
const ruff = @import("filter/ruff.zig");
const mypy = @import("filter/mypy.zig");
const grep = @import("filter/grep.zig");

pub const Kind = enum {
    git_status,
    git_log,
    git_diff,
    cargo_test,
    pytest,
    bun_test,
    eslint,
    prettier,
    django_test,
    ruff,
    mypy,
    grep,
};

pub const Ctx = struct {
    kind: Kind,
    args: []const []const u8,
};

pub fn callback(ptr: ?*const anyopaque, gpa: Allocator, stdout: []const u8) anyerror![]u8 {
    const ctx: *const Ctx = @ptrCast(@alignCast(ptr orelse return error.MissingFilterCtx));
    return apply(gpa, ctx.kind, ctx.args, stdout);
}

/// bun writes pass/fail/summary to stderr; merge streams before filtering on success.
pub fn shouldMergeStreams(ptr: ?*const anyopaque) bool {
    const ctx: *const Ctx = @ptrCast(@alignCast(ptr orelse return false));
    return ctx.kind == .bun_test;
}

pub fn apply(gpa: Allocator, kind: Kind, args: []const []const u8, stdout: []const u8) ![]u8 {
    const stripped = try stripAnsi(gpa, stdout);
    errdefer gpa.free(stripped);

    const compacted: ?[]u8 = switch (kind) {
        .git_status => if (args.len == 0) try git_status.compact(gpa, stripped) else null,
        .git_log => if (git_log.argsAllowCompact(args)) try git_log.compact(gpa, stripped) else null,
        .git_diff => null,
        .cargo_test => try cargo_test.compact(gpa, stripped),
        .pytest => try pytest.compact(gpa, stripped),
        .bun_test => try bun_test.compact(gpa, stripped),
        .eslint => try eslint.compact(gpa, stripped),
        .prettier => try prettier.compact(gpa, stripped),
        .django_test => try django_test.compact(gpa, stripped),
        .ruff => try ruff.compact(gpa, stripped),
        .mypy => try mypy.compact(gpa, stripped),
        .grep => if (grep.argsAllowCompact(args)) try grep.compact(gpa, stripped) else null,
    };

    if (compacted) |c| {
        gpa.free(stripped);
        return c;
    }
    return stripped;
}

pub fn stripAnsi(gpa: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            i += 2;
            while (i < input.len) : (i += 1) {
                const c = input[i];
                if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    i += 1;
                    break;
                }
            }
            continue;
        }
        try out.append(gpa, input[i]);
        i += 1;
    }
    return try out.toOwnedSlice(gpa);
}

pub fn expectFixture(gpa: Allocator, kind: Kind, args: []const []const u8, input: []const u8, expected: []const u8) !void {
    const got = try apply(gpa, kind, args, input);
    defer gpa.free(got);
    try std.testing.expectEqualStrings(expected, got);
}
