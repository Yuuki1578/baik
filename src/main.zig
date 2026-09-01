const std = @import("std");
const baik = @import("baik");
const repl = @import("repl.zig");
const log = std.log;
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Init = std.process.Init;

pub fn main(init: Init) u8 {
    var ret: u8 = 0;
    const io = init.io;
    const alloc = init.gpa;

    repl.repl(io, alloc) catch |err| {
        log.err("{any}\n", .{err});
        ret = 1;
    };

    return ret;
}
