const std = @import("std");
const builtin = @import("builtin");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
const assert = std.debug.assert;

pub fn main() !void {
    var i: u32 = 0;
    while (true) : (i += 1) {
        var buf: [30]u8 = undefined;
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
            try stdout.print("{s}: command not found\n", .{command});
        }
    }
}

fn handle_input(input: []const u8) !void {
    assert(input.len != 0);
    var input_slices = std.mem.splitScalar(u8, input, ' ');
    const first_arg = input_slices.first();
    const rest_of_input = input_slices.rest();
    if (std.mem.eql(u8, first_arg, ":q")) {
        _ = rest_of_input;
        std.process.exit(0);
    }
}
