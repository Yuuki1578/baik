//! Lexer for baik, turning a 'maybe' valid baik
//! source string into an individual tokens to later
//! feed on `Parser`.
const std = @import("std");
const common = @import("../common.zig");
const ascii = std.ascii;
const fmt = std.fmt;
const print = std.debug.print;
const log = std.log;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const TokenList = std.ArrayList(Token);
const KeywordMap = std.StaticStringMap(TokenKind);

allocator: Allocator,
tokens: TokenList,
source: []const u8,
begin: u64,
current: u64,
line: u64,

pub var keywords_table: KeywordMap = undefined;
pub var error_count: u64 = 0;

fn isAlphanumeric(ch: u8) bool {
    return ascii.isAlphanumeric(ch) or ch == '_';
}

fn isAllBase(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

const Self = @This();

fn report(self: Self, comptime msg: []const u8, any: anytype) void {
    log.err("[line {}]: " ++ msg, .{self.line} ++ any);
    error_count += 1;
}

fn initKeywordList() void {
    keywords_table = .initComptime(.{
        .{ "dan", .dan },
        .{ "tipe", .tipe },
        .{ "lain", .lain },
        .{ "salah", .salah },
        .{ "fungsi", .fungsi },
        .{ "untuk", .untuk },
        .{ "jika", .jika },
        .{ "hampa", .hampa },
        .{ "atau", .atau },
        .{ "cetak", .cetak },
        .{ "kembali", .kembali },
        .{ "indux", .induk },
        .{ "ini", .ini },
        .{ "benar", .benar },
        .{ "variabel", .variabel },
        .{ "selama", .selama },
        .{ "mulai", .mulai },
        .{ "akhir", .akhir },
    });
}

pub fn init(allocator: Allocator, source: []const u8) !Self {
    const prealloc_size = common.determinePreallocSize(u8, source);
    initKeywordList();
    return .{
        .allocator = allocator,
        .tokens = try .initCapacity(allocator, prealloc_size),
        .source = source,
        .begin = 0,
        .current = 0,
        .line = 1,
    };
}

pub fn deinit(self: *Self) void {
    self.tokens.deinit(self.allocator);
}

fn isDone(self: Self) bool {
    return self.current >= self.source.len;
}

fn fromBeginToCurrent(self: Self) []const u8 {
    return self.source[self.begin..self.current];
}

fn append(self: *Self, kind: TokenKind, data: ?Literal) !void {
    try self.tokens.append(self.allocator, .{
        .kind = kind,
        .lexeme = self.fromBeginToCurrent(),
        .line = self.line,
        .data = data,
    });
}

fn peekExact(self: Self, probe_ahead: u64) u8 {
    const probe_exact = self.current + probe_ahead;
    if (!self.isDone() and probe_exact < self.source.len) {
        return self.source[probe_exact];
    }
    return 0;
}

fn peekNext(self: Self) u8 {
    return self.peekExact(1);
}

fn peek(self: Self) u8 {
    return self.peekExact(0);
}

fn next(self: *Self) u8 {
    const peeked = self.peek();
    if (peeked != 0) {
        self.current += 1;
    }
    return peeked;
}

fn matchesWith(self: *Self, ch: u8) bool {
    if (self.peek() == ch) {
        self.current += 1;
        return true;
    }

    return false;
}

fn appendIf2Matches(
    self: *Self,
    case1: u8,
    case2: u8,
    ok1: TokenKind,
    ok2: TokenKind,
    alt: TokenKind,
) !void {
    if (self.matchesWith(case1)) {
        try self.append(ok1, null);
    } else if (self.matchesWith(case2)) {
        try self.append(ok2, null);
    } else {
        try self.append(alt, null);
    }
}

fn appendIfMatches(self: *Self, ch: u8, ok: TokenKind, alt: TokenKind) !void {
    if (self.matchesWith(ch)) {
        try self.append(ok, null);
    } else {
        try self.append(alt, null);
    }
}

fn comments(self: *Self) !void {
    if (self.matchesWith('/')) {
        while (!self.isDone()) {
            if (self.next() == '\n')
                return;
        }
    }

    if (self.matchesWith('*')) {
        while (!self.isDone()) {
            const peeked = self.peek();
            if (peeked == '*' and self.peekNext() == '/') {
                _ = self.next();
                _ = self.next();
                return;
            } else if (peeked == '\n') {
                self.line += 1;
            }
            _ = self.next();
        }
        self.report("Unterminated comment, missing {s}", .{"\"*/\""});
    } else {
        try self.append(.slash, null);
    }
}

fn strings(self: *Self) !void {
    while (!self.isDone()) {
        switch (self.peek()) {
            '`' => {
                _ = self.next();
                var lexeme = self.fromBeginToCurrent();
                if (lexeme.len < 3) {
                    lexeme = "";
                } else {
                    lexeme = lexeme[1 .. lexeme.len - 1];
                }

                try self.append(.string, .{ .string = lexeme });
                return;
            },

            '\n' => self.line += 1,
            else => {},
        }
        _ = self.next();
    }
    self.report("Unterminated string literal, missing '{c}'", .{'`'});
}

fn digits(self: *Self, context: u8) !void {
    if (context == '0' and
        (self.peek() == 'b' or self.peek() == 'o' or self.peek() == 'x'))
    {
        _ = self.next();
        while (!self.isDone()) {
            const peeked = self.peek();

            if (peeked == '_') {
                _ = self.next();
            } else if (!isAllBase(peeked)) {
                break;
            }
            _ = self.next();
        }

        const lexeme = self.fromBeginToCurrent();
        const num = fmt.parseInt(i64, lexeme, 0) catch |err| blk: {
            self.report("Failed parsing integer, {any}", .{err});
            break :blk 0;
        };

        try self.append(.int, .{ .int = num });
    } else {
        var has_dot_before = false;

        while (!self.isDone()) {
            const peeked = self.peek();
            if (peeked == '_') {
                _ = self.next();
            } else if (peeked == '.') {
                if (has_dot_before) break;
                _ = self.next();
                has_dot_before = true;
            } else if (!ascii.isDigit(peeked)) {
                break;
            }
            _ = self.next();
        }

        const lexeme = self.fromBeginToCurrent();
        var data: Literal = undefined;
        var kind: TokenKind = undefined;

        if (has_dot_before) {
            kind = .float;
            data = .{
                .float = fmt.parseFloat(f64, lexeme) catch |err| blk: {
                    self.report("Failed parsing float, {any}", .{err});
                    break :blk 0.0;
                },
            };
        } else {
            kind = .int;
            data = .{
                .int = fmt.parseInt(i64, lexeme, 10) catch |err| blk: {
                    self.report("Failed parsing integer, {any}", .{err});
                    break :blk 0;
                },
            };
        }

        try self.append(kind, data);
    }
}

fn identsOrKeywords(self: *Self) !void {
    while (!self.isDone()) {
        if (!isAlphanumeric(self.peek()))
            break;

        _ = self.next();
    }

    const kind = keywords_table.get(self.fromBeginToCurrent()) orelse .identifier;
    if (kind == .benar) {
        try self.append(kind, .{ .boolean = true });
    } else if (kind == .salah) {
        try self.append(kind, .{ .boolean = false });
    } else if (kind == .hampa) {
        try self.append(kind, .hampa);
    } else {
        try self.append(kind, null);
    }
}

fn scanOnce(self: *Self) !void {
    const ch = self.next();
    switch (ch) {
        0 => return,
        ' ', '\t', '\r' => {},
        '\n' => self.line += 1,

        '(' => try self.append(.left_paren, null),
        ')' => try self.append(.right_paren, null),
        '{' => try self.append(.left_brace, null),
        '}' => try self.append(.right_brace, null),
        ',' => try self.append(.comma, null),
        '.' => try self.append(.dot, null),
        '-' => try self.append(.minus, null),
        '+' => try self.append(.plus, null),
        '*' => try self.append(.star, null),
        '%' => try self.append(.percent, null),
        ';' => try self.append(.semicolon, null),
        '|' => try self.append(.bar, null),
        '&' => try self.append(.ampersand, null),
        '~' => try self.append(.tilde, null),
        '^' => try self.append(.caret, null),

        '=' => try self.appendIfMatches('=', .equal_equal, .equal),
        '!' => try self.appendIfMatches('=', .bang_equal, .bang),
        '<' => try self.appendIf2Matches('=', '<', .less_equal, .less_less, .less),
        '>' => try self.appendIf2Matches('=', '>', .greater_equal, .greater_greater, .greater),

        '/' => try self.comments(),
        '`' => try self.strings(),

        '0'...'9' => try self.digits(ch),
        'A'...'Z', 'a'...'z', '_' => try self.identsOrKeywords(),
        else => self.report("Unexpected character '{c}'", .{ch}),
    }
}

pub fn scan(self: *Self) !void {
    while (!self.isDone()) {
        try self.scanOnce();
        self.begin = self.current;
    }

    try self.append(.eof, null);
}

pub const TokenKind = enum {
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,
    percent,
    bar,
    ampersand,
    tilde,
    caret,

    bang,
    bang_equal,
    equal,
    equal_equal,

    greater,
    greater_greater,
    greater_equal,
    less,
    less_less,
    less_equal,

    identifier,
    string,
    int,
    float,

    dan,
    tipe,
    lain,
    salah,
    fungsi,
    untuk,
    jika,
    hampa,
    atau,
    cetak,
    kembali,
    induk,
    ini,
    benar,
    variabel,
    selama,
    mulai,
    akhir,

    eof,
};

pub const Literal = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    boolean: bool,
    hampa,

    pub const OperationError = error{
        TypeMissMatch,
    };

    pub fn bitAnd(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv & rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitOr(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv | rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitXor(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv ^ rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitShiftLeft(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv <<| @as(u64, @abs(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitShiftRight(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| {
                    const shifter: u6 = @intCast(@abs(rv));
                    return .{ .int = lv >> shifter };
                },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn boolAnd(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| return .{ .boolean = lv and rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn boolOr(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| return .{ .boolean = lv or rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| return .{ .boolean = lv == rv },
                else => return error.TypeMissMatch,
            },
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv == rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) == rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv == rv },
                .int => |rv| return .{ .boolean = lv == @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            .string => |lv| switch (rhs) {
                .string => |rv| return .{ .boolean = mem.eql(u8, lv, rv) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpNotEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| return .{ .boolean = lv != rv },
                else => return error.TypeMissMatch,
            },
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv != rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) != rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv != rv },
                .int => |rv| return .{ .boolean = lv != @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            .string => |lv| switch (rhs) {
                .string => |rv| return .{ .boolean = !mem.eql(u8, lv, rv) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpLess(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv < rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) < rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv < rv },
                .int => |rv| return .{ .boolean = lv < @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpLessEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv <= rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) <= rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv <= rv },
                .int => |rv| return .{ .boolean = lv <= @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpGreater(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv > rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) > rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv > rv },
                .int => |rv| return .{ .boolean = lv > @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpGreaterEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .boolean = lv >= rv },
                .float => |rv| return .{ .boolean = @as(f64, @floatFromInt(lv)) >= rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .boolean = lv >= rv },
                .int => |rv| return .{ .boolean = lv >= @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn add(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv + rv },
                .float => |rv| return .{ .float = @as(f64, @floatFromInt(lv)) + rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .float = lv + rv },
                .int => |rv| return .{ .float = lv + @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn subtract(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv -% rv },
                .float => |rv| return .{ .float = @as(f64, @floatFromInt(lv)) - rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .float = lv - rv },
                .int => |rv| return .{ .float = lv - @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn multiply(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| return .{ .int = lv *% rv },
                .float => |rv| return .{ .float = @as(f64, @floatFromInt(lv)) * rv },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| return .{ .float = lv * rv },
                .int => |rv| return .{ .float = lv * @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn divide(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| if (rv != 0) return .{ .int = @divTrunc(lv, rv) } else return .{ .int = 0 },
                .float => |rv| if (rv != 0.0) return .{ .float = @as(f64, @floatFromInt(lv)) / rv } else return .{ .float = 0.0 },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| if (rv != 0.0) return .{ .float = lv / rv } else return .{ .float = 0.0 },
                .int => |rv| if (rv != 0) return .{ .float = lv / @as(f64, @floatFromInt(rv)) } else return .{ .int = 0 },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn remainder(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| if (rv != 0) return .{ .int = @rem(lv, rv) } else return .{ .int = 0 },
                .float => |rv| if (rv != 0.0) return .{ .float = @rem(@as(f64, @floatFromInt(lv)), rv) } else return .{ .float = 0.0 },
                else => return error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| if (rv != 0) return .{ .float = @rem(lv, rv) } else return .{ .float = 0.0 },
                .int => |rv| if (rv != 0) return .{ .float = @rem(lv, @as(f64, @floatFromInt(rv))) } else return .{ .float = 0.0 },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    line: u64,
    data: ?Literal,

    pub const empty: @This() = .{
        .kind = .eof,
        .lexeme = "",
        .line = 1,
        .data = null,
    };
};

test Self {
    const alloc = std.testing.allocator;
    var lexer: Self = try .init(alloc,
        \\/* Entry point */
        \\fungsi utama() mulai
        \\    cetak `Halo, dunia!`;
        \\akhir
    );
    defer lexer.deinit();
    try lexer.scan();

    const tokens: []const Token = lexer.tokens.items;
    for (tokens) |token| {
        print("{any}\n", .{token});
    }

    try std.testing.expect(
        tokens[tokens.len - 2].kind == .akhir,
    );
}
