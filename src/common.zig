const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

pub fn preallocSize(unit: usize) usize {
    return switch (unit) {
        0 * 1 + 1...1024 * 1 => 1024,
        1024 * 1 + 1...1024 * 2 => 1024 * 2,
        1024 * 2 + 1...1024 * 4 => 1024 * 4,
        1024 * 4 + 1...1024 * 8 => 1024 * 8,
        else => 1024 * 10,
    };
}

pub fn readEntireFile(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    return try Dir
        .cwd()
        .readFileAlloc(io, path, allocator, .unlimited);
}
