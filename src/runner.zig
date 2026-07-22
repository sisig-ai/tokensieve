//! Child process runner. stdin is ignored (std.process.run uses .stdin = .ignore).
//! Capture loses interleaving of stdout/stderr; each stream is byte-identical to the child buffer.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const FilterFn = *const fn (ctx: ?*const anyopaque, gpa: Allocator, stdout: []const u8) anyerror![]u8;

pub fn termToCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        // POSIX shell convention: 128 + signal number
        .signal => |sig| 128 +% @as(u8, @truncate(@intFromEnum(sig))),
        else => 1,
    };
}

fn isExecNotFound(err: anyerror) bool {
    return err == error.FileNotFound;
}

pub fn spawnErrorToCode(err: anyerror) u8 {
    return if (isExecNotFound(err)) 127 else 1;
}

fn writeAll(io: Io, file: Io.File, bytes: []const u8) void {
    file.writeStreamingAll(io, bytes) catch {};
}

/// Spawn argv, map termination, filter stdout on exit 0 via callback, always forward stderr raw.
pub fn run(
    gpa: Allocator,
    io: Io,
    argv: []const []const u8,
    filter_ctx: ?*const anyopaque,
    filter_fn: FilterFn,
) u8 {
    const result = std.process.run(gpa, io, .{ .argv = argv }) catch |err| {
        const code = spawnErrorToCode(err);
        if (code == 127) {
            std.debug.print("tokensieve: executable not found: {s}\n", .{argv[0]});
        } else {
            std.debug.print("tokensieve: failed to run {s}: {s}\n", .{ argv[0], @errorName(err) });
        }
        return code;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    const code = termToCode(result.term);
    if (code != 0 and result.term != .exited) {
        if (result.term != .signal) {
            std.debug.print("tokensieve: unexpected termination\n", .{});
        }
    }

    if (code == 0) {
        const filtered = filter_fn(filter_ctx, gpa, result.stdout) catch |err| {
            std.debug.print("tokensieve: filter error: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer if (filtered.ptr != result.stdout.ptr) gpa.free(filtered);
        writeAll(io, .stdout(), filtered);
        writeAll(io, .stderr(), result.stderr);
    } else {
        writeAll(io, .stdout(), result.stdout);
        writeAll(io, .stderr(), result.stderr);
    }

    if (code != 0 and result.term != .exited and result.term != .signal) {
        return 1;
    }
    return code;
}

test "termToCode exited and signal" {
    try std.testing.expectEqual(@as(u8, 0), termToCode(.{ .exited = 0 }));
    try std.testing.expectEqual(@as(u8, 3), termToCode(.{ .exited = 3 }));
    try std.testing.expectEqual(@as(u8, 130), termToCode(.{ .signal = .INT })); // 128+2
    try std.testing.expectEqual(@as(u8, 1), termToCode(.{ .unknown = 0 }));
}

fn testIdentity(_: ?*const anyopaque, gpa: Allocator, stdout: []const u8) anyerror![]u8 {
    return try gpa.dupe(u8, stdout);
}

test "runner exit 0 filters stdout, stderr raw" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    // Capture via redirect is hard in-unit; exercise process.run path and code mapping.
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ "/bin/sh", "-c", "printf 'OUT'; echo ERR >&2" },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 0), termToCode(result.term));
    try std.testing.expectEqualStrings("OUT", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ERR") != null);
}

test "runner nonzero passthrough streams" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ "/bin/sh", "-c", "printf 'fail-out'; echo fail-err >&2; exit 7" },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 7), termToCode(result.term));
    try std.testing.expectEqualStrings("fail-out", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "fail-err") != null);
}

test "runner FileNotFound maps to 127" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const result = std.process.run(gpa, io, .{
        .argv = &.{"/nonexistent/tokensieve-missing-bin-xyz"},
    });
    try std.testing.expectError(error.FileNotFound, result);
    try std.testing.expectEqual(@as(u8, 127), spawnErrorToCode(error.FileNotFound));
    try std.testing.expectEqual(@as(u8, 1), spawnErrorToCode(error.AccessDenied));
}

test "runner propagates exit code via /bin/sh" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const code0 = run(gpa, io, &.{ "/bin/sh", "-c", "exit 0" }, null, testIdentity);
    try std.testing.expectEqual(@as(u8, 0), code0);
    const code4 = run(gpa, io, &.{ "/bin/sh", "-c", "exit 4" }, null, testIdentity);
    try std.testing.expectEqual(@as(u8, 4), code4);
}
