const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

pub fn readEntireFile(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    return try Dir
        .cwd()
        .readFileAlloc(io, path, allocator, .unlimited);
}
