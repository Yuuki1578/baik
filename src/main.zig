const std = @import("std");
const baik = @import("baik");
const repl = @import("repl.zig");
const Lexer = @import("frontend/Lexer.zig");
const Parser = @import("frontend/Parser.zig");
const Init = std.process.Init;
const print = std.debug.print;

pub fn main(init: Init) void {
    const io = init.io;
    const gpa = init.gpa;

    repl.repl(io, gpa) catch |err| {
        print("{any}\n", .{err});
        return;
    };
}
