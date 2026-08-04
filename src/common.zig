const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

/// Determine an allocation size for a data that stored on heap,
/// based on it's context length with a multiple of 1024.
pub fn determinePreallocSize(comptime T: anytype, slices: []const T) u64 {
    return switch (slices.len) {
        1...1024 => 1024,
        1025...2048 => 2048,
        2049...3172 => 3172,
        else => 4096, // upper limit
    };
}

pub fn readEntireFile(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    return try Dir
        .cwd()
        .readFileAlloc(io, path, allocator, .unlimited);
}

test {
    std.testing.refAllDecls(@This());
}
