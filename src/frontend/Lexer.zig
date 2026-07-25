//! Lexer for baik, turning a 'maybe' valid baik
//! source string into an individual tokens to later
//! feed on `Parser`.
const std = @import("std");
const baik = @import("baik");
const ascii = std.ascii;
const fmt = std.fmt;
const print = std.debug.print;
const log = std.log;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const TokenList = std.ArrayList(Token);
const KeywordMap = std.StringHashMap(TokenKind);

fn isAlphanumeric(ch: u8) bool {
    return ascii.isAlphanumeric(ch) or ch == '_';
}

fn isAllBase(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

pub var keywords_table: std.StringHashMap(TokenKind) = undefined;
pub var error_count: u64 = 0;

const Self = @This();

allocator: Allocator,
tokens: TokenList,
source: []const u8,
begin: u64,
current: u64,
line: u64,

fn report(self: Self, comptime msg: []const u8, any: anytype) void {
    log.err("[line {}]: " ++ msg, .{self.line} ++ any);
    error_count += 1;
}

fn initKeywordsList(allocator: Allocator) !void {
    keywords_table = .init(allocator);

    try keywords_table.put("dan", .Dan);
    try keywords_table.put("tipe", .Tipe);
    try keywords_table.put("lain", .Lain);
    try keywords_table.put("salah", .Salah);
    try keywords_table.put("fungsi", .Fungsi);
    try keywords_table.put("untuk", .Untuk);
    try keywords_table.put("jika", .Jika);
    try keywords_table.put("hampa", .Hampa);
    try keywords_table.put("atau", .Atau);
    try keywords_table.put("cetak", .Cetak);
    try keywords_table.put("kembali", .Kembali);
    try keywords_table.put("indux", .Induk);
    try keywords_table.put("ini", .Ini);
    try keywords_table.put("benar", .Benar);
    try keywords_table.put("var", .Var);
    try keywords_table.put("selama", .Selama);
}

pub fn init(allocator: Allocator, source: []const u8) !Self {
    const prealloc_size = baik.determinePreallocSize(u8, source);
    try initKeywordsList(allocator);
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
    keywords_table.deinit();
}

fn isDone(self: Self) bool {
    return self.current >= self.source.len;
}

fn append(self: *Self, kind: TokenKind, data: ?Literal) !void {
    try self.tokens.append(self.allocator, .{
        .kind = kind,
        .lexeme = self.source[self.begin..self.current],
        .line = self.line,
        .data = data,
    });
}

fn peekExact(self: Self, probe: u64) u8 {
    const probe_exact = self.current + probe;
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
        try self.append(.Slash, null);
    }
}

fn strings(self: *Self) !void {
    while (!self.isDone()) {
        switch (self.peek()) {
            '`' => {
                _ = self.next();
                var lexeme = self.source[self.begin..self.current];
                if (lexeme.len < 3) {
                    lexeme = "";
                } else {
                    lexeme = lexeme[1 .. lexeme.len - 1];
                }

                try self.append(.String, .{ .String = lexeme });
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

        const lexeme = self.source[self.begin..self.current];
        const num = fmt.parseInt(i64, lexeme, 0) catch |err| blk: {
            self.report("Failed parsing integer, {any}", .{err});
            break :blk 0;
        };

        try self.append(.Int, .{ .Int = num });
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

        const lexeme = self.source[self.begin..self.current];
        var data: Literal = undefined;
        var kind: TokenKind = undefined;

        if (has_dot_before) {
            kind = .Float;
            data = .{
                .Float = fmt.parseFloat(f64, lexeme) catch |err| blk: {
                    self.report("Failed parsing float, {any}", .{err});
                    break :blk 0.0;
                },
            };
        } else {
            kind = .Int;
            data = .{
                .Int = fmt.parseInt(i64, lexeme, 10) catch |err| blk: {
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

    const kind = keywords_table.get(self.source[self.begin..self.current]) orelse .Identifier;
    if (kind == .Benar) {
        try self.append(kind, .{ .Bool = true });
    } else if (kind == .Salah) {
        try self.append(kind, .{ .Bool = false });
    } else if (kind == .Hampa) {
        try self.append(kind, .Nil);
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

        '(' => try self.append(.LeftParen, null),
        ')' => try self.append(.RightParen, null),
        '{' => try self.append(.LeftBrace, null),
        '}' => try self.append(.RightBrace, null),
        ',' => try self.append(.Comma, null),
        '.' => try self.append(.Dot, null),
        '-' => try self.append(.Minus, null),
        '+' => try self.append(.Plus, null),
        '*' => try self.append(.Star, null),
        '%' => try self.append(.Percent, null),
        ';' => try self.append(.Semicolon, null),
        '|' => try self.append(.Bar, null),
        '&' => try self.append(.Ampersand, null),
        '~' => try self.append(.Tilde, null),
        '^' => try self.append(.Caret, null),

        '=' => try self.appendIfMatches('=', .EqualEqual, .Equal),
        '!' => try self.appendIfMatches('=', .BangEqual, .Bang),
        '<' => try self.appendIf2Matches('=', '<', .LessEqual, .LessLess, .Less),
        '>' => try self.appendIf2Matches('=', '>', .GreaterEqual, .GreaterGreater, .Greater),

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

    try self.append(.Eof, null);
}

pub const TokenKind = enum {
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    Percent,
    Bar,
    Ampersand,
    Tilde,
    Caret,

    Bang,
    BangEqual,
    Equal,
    EqualEqual,

    Greater,
    GreaterGreater,
    GreaterEqual,
    Less,
    LessLess,
    LessEqual,

    Identifier,
    String,
    Int,
    Float,

    Dan,
    Tipe,
    Lain,
    Salah,
    Fungsi,
    Untuk,
    Jika,
    Hampa,
    Atau,
    Cetak,
    Kembali,
    Induk,
    Ini,
    Benar,
    Var,
    Selama,

    Eof,
};

pub const Literal = union(enum) {
    String: []const u8,
    Int: i64,
    Float: f64,
    Bool: bool,
    Nil,

    pub const OperationError = error{
        TypeMissMatch,
    };

    pub fn bitAnd(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv & rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitOr(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv | rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitXor(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv ^ rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitShiftLeft(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv <<| @as(u64, @abs(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn bitShiftRight(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| {
                    const shifter: u6 = @intCast(@abs(rv));
                    return .{ .Int = lv >> shifter };
                },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn boolAnd(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Bool => |lv| switch (rhs) {
                .Bool => |rv| return .{ .Bool = lv and rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn boolOr(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Bool => |lv| switch (rhs) {
                .Bool => |rv| return .{ .Bool = lv or rv },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Bool => |lv| switch (rhs) {
                .Bool => |rv| return .{ .Bool = lv == rv },
                else => return error.TypeMissMatch,
            },
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv == rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) == rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv == rv },
                .Int => |rv| return .{ .Bool = lv == @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            .String => |lv| switch (rhs) {
                .String => |rv| return .{ .Bool = mem.eql(u8, lv, rv) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpNotEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Bool => |lv| switch (rhs) {
                .Bool => |rv| return .{ .Bool = lv != rv },
                else => return error.TypeMissMatch,
            },
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv != rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) != rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv != rv },
                .Int => |rv| return .{ .Bool = lv != @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            .String => |lv| switch (rhs) {
                .String => |rv| return .{ .Bool = !mem.eql(u8, lv, rv) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpLess(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv < rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) < rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv < rv },
                .Int => |rv| return .{ .Bool = lv < @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpLessEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv <= rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) <= rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv <= rv },
                .Int => |rv| return .{ .Bool = lv <= @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpGreater(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv > rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) > rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv > rv },
                .Int => |rv| return .{ .Bool = lv > @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn cmpGreaterEqual(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Bool = lv >= rv },
                .Float => |rv| return .{ .Bool = @as(f64, @floatFromInt(lv)) >= rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Bool = lv >= rv },
                .Int => |rv| return .{ .Bool = lv >= @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn add(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv + rv },
                .Float => |rv| return .{ .Float = @as(f64, @floatFromInt(lv)) + rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Float = lv + rv },
                .Int => |rv| return .{ .Float = lv + @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn subtract(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv - rv },
                .Float => |rv| return .{ .Float = @as(f64, @floatFromInt(lv)) - rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Float = lv - rv },
                .Int => |rv| return .{ .Float = lv - @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn multiply(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| return .{ .Int = lv * rv },
                .Float => |rv| return .{ .Float = @as(f64, @floatFromInt(lv)) * rv },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| return .{ .Float = lv * rv },
                .Int => |rv| return .{ .Float = lv * @as(f64, @floatFromInt(rv)) },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn divide(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| if (rv != 0) return .{ .Int = @divExact(lv, rv) } else return .{ .Int = 0 },
                .Float => |rv| if (rv != 0.0) return .{ .Float = @as(f64, @floatFromInt(lv)) / rv } else return .{ .Float = 0.0 },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| if (rv != 0.0) return .{ .Float = lv / rv } else return .{ .Float = 0.0 },
                .Int => |rv| if (rv != 0) return .{ .Float = lv / @as(f64, @floatFromInt(rv)) } else return .{ .Int = 0 },
                else => return error.TypeMissMatch,
            },
            else => return error.TypeMissMatch,
        }
    }

    pub fn remainder(lhs: Literal, rhs: Literal) OperationError!Literal {
        switch (lhs) {
            .Int => |lv| switch (rhs) {
                .Int => |rv| if (rv != 0) return .{ .Int = @rem(lv, rv) } else return .{ .Int = 0 },
                .Float => |rv| if (rv != 0.0) return .{ .Float = @rem(@as(f64, @floatFromInt(lv)), rv) } else return .{ .Float = 0.0 },
                else => return error.TypeMissMatch,
            },
            .Float => |lv| switch (rhs) {
                .Float => |rv| if (rv != 0) return .{ .Float = @rem(lv, rv) } else return .{ .Float = 0.0 },
                .Int => |rv| if (rv != 0) return .{ .Float = @rem(lv, @as(f64, @floatFromInt(rv))) } else return .{ .Float = 0.0 },
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
        .kind = .Eof,
        .lexeme = "",
        .line = 1,
        .data = null,
    };
};
