//! This will act like a tiny calculator,
//! just for fun experimental haha.
const std = @import("std");
const Lexer = @import("frontend/Lexer.zig");
const Parser = @import("frontend/Parser.zig");
const Allocator = std.mem.Allocator;
const File = std.Io.File;

pub fn repl(io: std.Io, allocator: Allocator) !void {
    const stdin = File.stdin();
    const stdout = File.stdout();
    var buffer: std.ArrayList(u8) = try .initCapacity(allocator, 1024);
    defer buffer.deinit(allocator);

    while (true) {
        try stdout.writeStreamingAll(io, ">> ");

        var stackbuf: [64]u8 = @splat(0);
        const readed = stdin.readStreaming(io, &.{&stackbuf}) catch break;
        try buffer.appendSlice(allocator, stackbuf[0 .. readed - 1]);

        if (stackbuf[readed - 1] == '\n') {
            defer buffer.clearAndFree(allocator);

            var lexer: Lexer = try .init(allocator, buffer.items);
            defer lexer.deinit();
            try lexer.scan();

            var parser: Parser = try .fromLexer(lexer);
            defer parser.deinit();
            const expr_tree = parser.parseExpr() catch |err| {
                std.log.err("{s}", .{@errorName(err)});
                continue;
            };

            const expr = expr_tree.eval() catch |err| {
                std.log.err("{s}", .{@errorName(err)});
                continue;
            };

            switch (expr) {
                .int, .boolean, .float, .hampa => std.debug.print("{any}\n", .{expr}),
                .string => std.debug.print(".{{ .String = `{s}` }}\n", .{expr.string}),
            }
        }
    }
}
