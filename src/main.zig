const std = @import("std");
const baik = @import("baik");
const repl = @import("repl.zig");
const Lexer = @import("frontend/Lexer.zig");
const Parser = @import("frontend/Parser.zig");
const Init = std.process.Init;

const print = std.debug.print;

pub fn main(init: Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    try repl.repl(io, gpa);
    // const buffer = try baik.readEntireFile(gpa, io, "sample.bk");
    // defer gpa.free(buffer);

    // var lexer = try Lexer.init(gpa, buffer);
    // defer lexer.deinit();
    // try lexer.scan();

    // var parser: Parser = try .init(gpa, lexer.tokens.items);
    // defer parser.deinit();
    // const expr = parser.parseExpr() catch |err| {
    //     print("{any}\n", .{err});
    //     return;
    // };

    // const value = try expr.eval();
    // if (value == .String) {
    //     print("Value: .{{ .String = `{s}` }}\n", .{value.String});
    // } else {
    //     print("Value: {any}\n", .{value});
    // }
}
