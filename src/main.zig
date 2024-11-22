const std = @import("std");
const builtin = @import("builtin");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Builtin = enum {
    exit,
    echo,
    type,
    pwd,
};

pub fn main() !void {
    var i: u32 = 0;
    while (true) : (i += 1) {
        var buf: [1024]u8 = undefined;
        try stdout.print("$ ", .{});
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var command = line;
            if (builtin.os.tag == .windows) {
                command = @constCast(std.mem.trimRight(u8, command, '\r'));
            }
            if (command.len != 0) {
                try handle_input(command);
            } else {
                try stdout.print("\n", .{});
            }
        }
    }
}

fn handler(T: Builtin, args: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const path_var = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(path_var);
    switch (T) {
        Builtin.exit => std.process.exit(std.fmt.parseInt(u8, args, 10) catch 0),
        Builtin.echo => try stdout.print("{s}\n", .{args}),
        Builtin.type => try handle_type(args),
        Builtin.pwd => try stdout.print("{s}\n", .{path_var}),
    }
}

fn handle_type(args: []const u8) !void {
    const args_type = std.meta.stringToEnum(Builtin, args);
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa);
    const arena_allocator = arena.allocator();
    defer arena.deinit();

    if (args_type) |@"type"| {
        try stdout.print("{s} is a shell builtin\n", .{@tagName(@"type")});
        return;
    }
    if (try lookup_command(args, arena_allocator)) |path| {
        try stdout.print("{s} is {s}\n", .{ args, path });
    } else {
        try stdout.print("{s}: not found\n", .{args});
    }
}

fn lookup_command(cmd: []const u8, allocator: Allocator) !?[]const u8 {
    const path_var = try std.process.getEnvVarOwned(allocator, "PATH");
    var path_iter = std.mem.splitScalar(u8, path_var, std.fs.path.delimiter);

    while (path_iter.next()) |current_dir_path| {
        const dir = std.fs.openDirAbsolute(current_dir_path, .{}) catch continue;
        const file_status = dir.statFile(cmd) catch continue;
        if (file_status.mode == 0) {
            continue;
        }
        return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ current_dir_path, std.fs.path.sep, cmd });
    }
    return null;
}

fn handle_input(input: []const u8) !void {
    assert(input.len != 0);
    var input_slices = std.mem.splitScalar(u8, input, ' ');
    const first_arg = input_slices.first();
    const rest_of_input = input_slices.rest();
    const shell_builtin = std.meta.stringToEnum(Builtin, first_arg);

    if (shell_builtin) |bi| {
        try handler(bi, rest_of_input);
    } else {
        try handle_default(first_arg, rest_of_input);
    }
}

fn handle_default(cmd: []const u8, args: []const u8) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa);
    const arena_allocator = arena.allocator();
    defer arena.deinit();

    const path = try lookup_command(cmd, arena_allocator) orelse {
        try stdout.print("{s}: command not found\n", .{cmd});
        return;
    };

    var argv = std.ArrayList([]const u8).init(arena_allocator);
    try argv.append(path);
    var args_iter = std.mem.splitScalar(u8, args, ' ');
    while (args_iter.next()) |item| {
        try argv.append(item);
    }

    var child_process = std.process.Child.init(argv.items, arena_allocator);
    _ = try child_process.spawnAndWait();
}
