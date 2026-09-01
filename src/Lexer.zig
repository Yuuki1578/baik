//! Lexer for baik, turning a 'maybe' valid baik
//! source string into an individual tokens to later
//! feed on `Parser`.
const std = @import("std");
const common = @import("common.zig");
const literal = @import("literal.zig");
const ascii = std.ascii;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
pub const Literal = literal.Literal;
const Allocator = std.mem.Allocator;
const TokenList = std.ArrayList(Token);
const KeywordMap = std.StaticStringMap(TokenKind);

allocator: Allocator,
tokens: TokenList,
source: []const u8,
begin: usize,
current: usize,
line: usize,

const Self = @This();

const kw_table: KeywordMap = .initComptime(.{
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
});

pub var error_count: usize = 0;

fn isAlphanumeric(ch: u8) bool {
    return ascii.isAlphanumeric(ch) or ch == '_';
}

fn isAsciiBase16(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

fn report(self: Self, comptime msg: []const u8, any: anytype) void {
    log.err("[line {}]: " ++ msg, .{self.line} ++ any);
    error_count += 1;
}

pub fn init(a: Allocator, source: []const u8) !Self {
    const prealloc_size = common.preallocSize(source.len);
    return .{
        .allocator = a,
        .tokens = try .initCapacity(a, prealloc_size),
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

fn getLexeme(self: Self) []const u8 {
    return self.source[self.begin..self.current];
}

fn append(self: *Self, kind: TokenKind, data: ?Literal) !void {
    const token: Token = .{
        .kind = kind,
        .lexeme = self.getLexeme(),
        .line = self.line,
        .data = data,
    };

    if (self.tokens.capacity == self.tokens.items.len)
        try self.tokens.ensureTotalCapacity(self.allocator, self.tokens.capacity * 2);

    self.tokens.appendAssumeCapacity(token);
}

/// Return the character from `current + probe_ahead`. If the addition result
/// is less than `tokens.len`, return the character on that position, if not
/// return `0`.
fn peekExact(self: Self, probe_ahead: usize) u8 {
    const probe_exact = self.current + probe_ahead;
    if (!self.isDone() and probe_exact < self.source.len) {
        return self.source[probe_exact];
    }
    return 0;
}

/// Return the character from the next 2 position.
fn peekNext(self: Self) u8 {
    return self.peekExact(1);
}

/// Return the next character and keep the `current`.
fn peek(self: Self) u8 {
    return self.peekExact(0);
}

/// Return the next character and increase `current`.
fn next(self: *Self) u8 {
    const peeked = self.peek();
    if (peeked != 0) {
        self.current += 1;
    }
    return peeked;
}

/// If the next character is `ch`, increase `current` position by one and return true.
/// If not, return false.
fn matchesWith(self: *Self, ch: u8) bool {
    if (self.peek() == ch) {
        self.current += 1;
        return true;
    }
    return false;
}

/// Same as `appendIfMatches2`, but only 1 case.
fn appendIfMatches(
    self: *Self,
    ch: u8,
    ok: TokenKind,
    alt: TokenKind,
) !void {
    if (self.matchesWith(ch)) {
        try self.append(ok, null);
    } else {
        try self.append(alt, null);
    }
}

/// Try if the next character is either `case1` or `case2`.
/// If not, append single token as `alt`.
fn appendIfMatches2(
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

/// Ignore comments.
fn comment(self: *Self) !void {
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

fn removeQuote(s: []const u8) []const u8 {
    if (s.len < 3) {
        return "";
    } else {
        return s[1 .. s.len - 1];
    }
}

/// Parse string that's start with the double quote.
/// Support basic ANSI escape sequences.
fn string(self: *Self) !void {
    var escaped = false;
    while (!self.isDone()) {
        const peeked = self.peek();
        switch (peeked) {
            '\t', '\n', '\r' => |ch| {
                const as_char: u8 = switch (ch) {
                    '\n' => 'n',
                    '\r' => 'r',
                    '\t' => 't',
                    else => '0',
                };
                self.report("Cannot use '\\{c}' directly, use escape sequence instead", .{as_char});
                return error.InvalidCharacter;
            },
            '\\' => if (escaped) {
                escaped = false;
            } else {
                escaped = true;
            },

            '"' => if (escaped) {
                escaped = false;
            } else {
                _ = self.next();
                const inner = removeQuote(self.getLexeme());
                try self.append(.string, .{ .string = .{ .normal = inner } });
                return;
            },

            '\'', 'a', 'b', 'f', 'n', 'r', 't', 'v' => if (escaped) {
                escaped = false;
            },
            else => |other| if (escaped) {
                self.report("Unsupported escape sequence of '\\{c}'", .{other});
                escaped = false;
            },
        }
        _ = self.next();
    }
    self.report("Unterminated string literal, missing double-quote '{c}'", .{'"'});
}

/// Parse string that's start with the backtick quote.
fn rawString(self: *Self) !void {
    while (!self.isDone()) {
        switch (self.peek()) {
            '`' => {
                _ = self.next();
                const inner = removeQuote(self.getLexeme());
                try self.append(.string, .{ .string = .{ .raw = inner } });
                return;
            },

            '\n' => self.line += 1,
            else => {},
        }
        _ = self.next();
    }
    self.report("Unterminated string literal, missing backtick '{c}'", .{'`'});
}

/// Parse lexeme into hex, binary, or octal. If character after `context` from
/// `digit` is an ascii digit, parse into base 10.
fn prefixedDigit(self: *Self) !void {
    _ = self.next();
    while (!self.isDone()) {
        const peeked = self.peek();

        switch (peeked) {
            '_' => _ = self.next(),
            else => |other| if (!isAsciiBase16(other)) {
                break;
            },
        }
        _ = self.next();
    }

    const lexeme = self.getLexeme();
    const num = fmt.parseInt(i64, lexeme, 0) catch |err| blk: {
        self.report("parseInt() failed, got '{any}' while parsing '{s}'", .{ err, lexeme });
        break :blk 0;
    };

    try self.append(.int, .{ .int = num });
}

/// Turn a lexeme into a digit. The digit can be either `i64` or `f64`.
/// Uses the zig builtin parsing numbers function.
/// `context` is used as a trap, if the next character is `x`, `b`, or `o`,
/// which is hex, binary, and octal respectively, it'll switch to `prefixedDigit`,
/// if not, treat it as decimal base 10 or a float.
fn digit(self: *Self, context: u8) !void {
    const prefixed = switch (self.peek()) {
        'b', 'o', 'x' => true,
        else => |other| if (ascii.isDigit(other)) true else false,
    };

    if (context == '0' and prefixed) {
        try self.prefixedDigit();
        return;
    }

    var is_float = false;
    while (!self.isDone()) {
        switch (self.peek()) {
            '_' => _ = self.next(),
            '.' => if (is_float) break else {
                _ = self.next();
                is_float = true;
            },
            else => |other| if (!ascii.isDigit(other)) break,
        }
        _ = self.next();
    }

    const lexeme = self.getLexeme();
    var data: Literal = undefined;
    var kind: TokenKind = undefined;

    if (is_float) {
        kind = .float;
        data = .{ .float = fmt.parseFloat(f64, lexeme) catch |err| blk: {
            self.report("parseFloat() failed, got '{any}' while parsing '{s}'", .{ err, lexeme });
            break :blk 0.0;
        } };
    } else {
        kind = .int;
        data = .{ .int = fmt.parseInt(i64, lexeme, 10) catch |err| blk: {
            self.report("parseFloat() failed, got '{any}' while parsing '{s}'", .{ err, lexeme });
            break :blk 0;
        } };
    }

    try self.append(kind, data);
}

/// Pull a `TokenKind` keyword from the corresponding lexemes.
/// Append the keyword if found, if not, treat it as an identifier.
fn keywordAndIdent(self: *Self) !void {
    while (!self.isDone()) {
        if (!isAlphanumeric(self.peek()))
            break;

        _ = self.next();
    }

    const kind = kw_table.get(self.getLexeme()) orelse .identifier;
    const data: ?Literal = switch (kind) {
        .benar => .{ .boolean = true },
        .salah => .{ .boolean = false },
        .hampa => .hampa,
        else => null,
    };

    try self.append(kind, data);
}

/// Scan the source code 1 token at a time.
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
        '<' => try self.appendIfMatches2('=', '<', .less_equal, .less_less, .less),
        '>' => try self.appendIfMatches2('=', '>', .greater_equal, .greater_greater, .greater),

        '/' => try self.comment(),
        '`' => try self.rawString(),
        '"' => try self.string(),

        '0'...'9' => try self.digit(ch),
        'A'...'Z', 'a'...'z', '_' => try self.keywordAndIdent(),
        else => self.report("Unexpected character '{c}'", .{ch}),
    }
}

/// Scan the entire source by calling `scanOnce()` multiple times
/// and synchronize `start` with `current`.
/// Appending an `.eof` if the scanning completed.
pub fn scan(self: *Self) !void {
    while (!self.isDone()) {
        try self.scanOnce();
        self.begin = self.current;
    }

    try self.append(.eof, null);
}

pub const TokenKind = enum {
    // single token
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

    // 1 - 2 kind of token
    bang,
    bang_equal,
    equal,
    equal_equal,

    // 1 - 3 kind of token
    greater,
    greater_greater,
    greater_equal,
    less,
    less_less,
    less_equal,

    // Literal and identifier
    identifier,
    string,
    int,
    float,

    // Keyword
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

    // end marker
    eof,
};

/// Represent an identity for one or more lexeme.
pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    line: usize,
    data: ?Literal,
};
