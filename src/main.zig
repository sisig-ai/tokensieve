const std = @import("std");
const runner = @import("runner.zig");
const filter = @import("filter.zig");

const version = "0.1.0";

const usage =
    \\usage: tokensieve <command>
    \\
    \\commands:
    \\  git status [-- args...]
    \\  git log [-- args...]
    \\  git diff [-- args...]
    \\  cargo test [-- args...]
    \\  pytest [-- args...]
    \\  bun test [-- args...]
    \\  eslint [-- args...]
    \\  prettier [-- args...]
    \\  django test [-- args...]
    \\  --help
    \\  --version
    \\
;

pub fn main(init: std.process.Init) u8 {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = init.minimal.args.toSlice(arena) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    if (args.len < 2) {
        std.debug.print("{s}", .{usage});
        return 2;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "help")) {
        std.debug.print("{s}", .{usage});
        return 0;
    }
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-V") or std.mem.eql(u8, cmd, "version")) {
        std.debug.print("tokensieve {s}\n", .{version});
        return 0;
    }

    if (std.mem.eql(u8, cmd, "git")) {
        return dispatchGit(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "cargo")) {
        return dispatchCargo(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "pytest")) {
        return dispatchPytest(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "bun")) {
        return dispatchBun(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "eslint")) {
        return dispatchEslint(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "prettier")) {
        return dispatchPrettier(gpa, io, arena, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "django")) {
        return dispatchDjango(gpa, io, arena, args[2..]);
    }

    std.debug.print("tokensieve: unknown command: {s}\n{s}", .{ cmd, usage });
    return 2;
}

fn dispatchGit(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    if (rest.len == 0) {
        std.debug.print("tokensieve: missing git subcommand\n{s}", .{usage});
        return 2;
    }
    const sub = rest[0];
    const trailing = rest[1..];
    const kind: filter.Kind = if (std.mem.eql(u8, sub, "status"))
        .git_status
    else if (std.mem.eql(u8, sub, "log"))
        .git_log
    else if (std.mem.eql(u8, sub, "diff"))
        .git_diff
    else {
        std.debug.print("tokensieve: unknown git subcommand: {s}\n", .{sub});
        return 2;
    };

    const child_argv = buildArgv(arena, &.{"git", sub}, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = kind, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchCargo(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    if (rest.len == 0 or !std.mem.eql(u8, rest[0], "test")) {
        std.debug.print("tokensieve: expected `cargo test`\n{s}", .{usage});
        return 2;
    }
    const trailing = rest[1..];
    const child_argv = buildArgv(arena, &.{ "cargo", "test" }, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .cargo_test, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchPytest(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    const child_argv = buildArgv(arena, &.{"pytest"}, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .pytest, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchBun(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    if (rest.len == 0 or !std.mem.eql(u8, rest[0], "test")) {
        std.debug.print("tokensieve: expected `bun test`\n{s}", .{usage});
        return 2;
    }
    const trailing = rest[1..];
    const child_argv = buildArgv(arena, &.{ "bun", "test" }, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .bun_test, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchEslint(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    const child_argv = buildArgv(arena, &.{"eslint"}, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .eslint, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchPrettier(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    const child_argv = buildArgv(arena, &.{"prettier"}, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, rest) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .prettier, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn dispatchDjango(gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator, rest: []const [:0]const u8) u8 {
    if (rest.len == 0 or !std.mem.eql(u8, rest[0], "test")) {
        std.debug.print("tokensieve: expected `django test`\n{s}", .{usage});
        return 2;
    }
    const trailing = rest[1..];
    const child_argv = buildArgv(arena, &.{ "python", "manage.py", "test" }, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const trailing_slices = toSlices(arena, trailing) catch {
        std.debug.print("tokensieve: out of memory\n", .{});
        return 1;
    };
    const ctx = filter.Ctx{ .kind = .django_test, .args = trailing_slices };
    return runner.run(gpa, io, child_argv, &ctx, filter.callback);
}

fn toSlices(arena: std.mem.Allocator, args: []const [:0]const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, args.len);
    for (args, 0..) |a, i| out[i] = a;
    return out;
}

fn buildArgv(arena: std.mem.Allocator, prefix: []const []const u8, trailing: []const [:0]const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, prefix.len + trailing.len);
    for (prefix, 0..) |p, i| out[i] = p;
    for (trailing, 0..) |t, i| out[prefix.len + i] = t;
    return out;
}

test {
    _ = runner;
    _ = filter;
}
