//! This will act like a tiny calculator,
//! just for fun experimental haha.
const std = @import("std");
const log = std.log;
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Allocator = std.mem.Allocator;
const File = std.Io.File;

pub fn repl(io: std.Io, a: Allocator) !void {
    const stdin = File.stdin();
    const stdout = File.stdout();
    var buffer: std.ArrayList(u8) = try .initCapacity(a, 1024);
    defer buffer.deinit(a);

    while (true) {
        try stdout.writeStreamingAll(io, ">> ");

        var stackbuf: [64]u8 = @splat(0);
        const readed = stdin.readStreaming(io, &.{&stackbuf}) catch break;
        try buffer.appendSlice(a, stackbuf[0 .. readed - 1]);

        if (stackbuf[readed - 1] == '\n') {
            defer buffer.clearRetainingCapacity();

            var lexer: Lexer = try .init(a, buffer.items);
            defer lexer.deinit();
            lexer.scan() catch continue;

            var parser: Parser = try .fromLexer(lexer);
            defer parser.deinit();
            const expr_tree = parser.parseExpr() catch |err| {
                log.err("{s}", .{@errorName(err)});
                continue;
            };

            const expr = expr_tree.eval(a) catch |err| {
                log.err("{s}", .{@errorName(err)});
                continue;
            };

            switch (expr) {
                .int, .boolean, .float, .hampa => log.info("{any}", .{expr}),
                .string => |s| {
                    const string = s.toAllocSlice(a) orelse "";
                    log.info(
                        \\.{{ .string = "{s}" }}
                    , .{string});

                    if (string.len != 0)
                        a.free(string);
                },
            }
        }
    }
}
