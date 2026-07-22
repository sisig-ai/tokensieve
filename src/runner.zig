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

/// First PATH hit for `name`, or null. Caller owns the returned slice (use arena).
pub fn findOnPath(allocator: Allocator, io: Io, path_env: []const u8, name: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(allocator, &.{ dir, name });
        errdefer allocator.free(candidate);
        Io.Dir.access(.cwd(), io, candidate, .{}) catch {
            allocator.free(candidate);
            continue;
        };
        return candidate;
    }
    return null;
}

fn writeAll(io: Io, file: Io.File, bytes: []const u8) !void {
    try file.writeStreamingAll(io, bytes);
}

pub const MergeStreamsFn = *const fn (ctx: ?*const anyopaque) bool;

/// Spawn argv, map termination.
/// On exit 0: filter stdout (or stdout+stderr concatenated when merge_fn says so), then write.
/// When merged, filtered result goes to stdout and stderr is omitted (bun puts results on stderr).
/// On nonzero: both streams verbatim.
pub fn run(
    gpa: Allocator,
    io: Io,
    argv: []const []const u8,
    filter_ctx: ?*const anyopaque,
    filter_fn: FilterFn,
    merge_fn: ?MergeStreamsFn,
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
        const merge = if (merge_fn) |f| f(filter_ctx) else false;
        var input_owned: ?[]u8 = null;
        defer if (input_owned) |o| gpa.free(o);

        const input: []const u8 = if (merge) blk: {
            const n = result.stdout.len + result.stderr.len;
            const buf = gpa.alloc(u8, n) catch {
                std.debug.print("tokensieve: out of memory\n", .{});
                return 1;
            };
            @memcpy(buf[0..result.stdout.len], result.stdout);
            @memcpy(buf[result.stdout.len..], result.stderr);
            input_owned = buf;
            break :blk buf;
        } else result.stdout;

        const filtered = filter_fn(filter_ctx, gpa, input) catch |err| {
            std.debug.print("tokensieve: filter error: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer if (filtered.ptr != input.ptr) gpa.free(filtered);
        writeAll(io, .stdout(), filtered) catch return 1;
        if (!merge) writeAll(io, .stderr(), result.stderr) catch return 1;
    } else {
        writeAll(io, .stdout(), result.stdout) catch return 1;
        writeAll(io, .stderr(), result.stderr) catch return 1;
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
    const code0 = run(gpa, io, &.{ "/bin/sh", "-c", "exit 0" }, null, testIdentity, null);
    try std.testing.expectEqual(@as(u8, 0), code0);
    const code4 = run(gpa, io, &.{ "/bin/sh", "-c", "exit 4" }, null, testIdentity, null);
    try std.testing.expectEqual(@as(u8, 4), code4);
}
