//! Parser module, handle the syntax checking
//! and AST building.
//! The grammar rule is as follow:
//! Expression rule:
//!
//! `EXPR`   : `COMMA`
//! `COMMA`  : `EQU` ( ( "," ) `EQU` )*
//! `EQU`    : `CMP` ( ( "==" | "!=" ) `CMP` )*
//! `CMP`    : `BITMOV` ( ( ">" | ">=" | "<" | "<=" ) `BITMOV` )*
//! `BITMOV` : `BITOP` ( ( "<<" | ">>" ) `BITOP` )*
//! `BITOP`  : `TERM` ( ( "&" | "|" | "^" ) `TERM` )*
//! `TERM`   : `FACTOR` ( ( "+" | "-" ) `FACTOR` )*
//! `FACTOR` : `UNARY` ( ( "*" | "/" ) `UNARY` )*
//! `UNARY`  : ( "-" | "!" | "~" ) `UNARY` | `PRIMARY`
//! `PRIMARY`: `STRING` | `NUMBER` | `FLOAT` | "benar" | "salah" | "hampa" | "(" `EXPR` ")"
const std = @import("std");
const common = @import("common.zig");
const log = std.log;
const ExprPool = std.heap.MemoryPool(Expr);
const Allocator = std.mem.Allocator;
const Lexer = @import("Lexer.zig");
const TokenKind = Lexer.TokenKind;
const Token = Lexer.Token;
const Literal = Lexer.Literal;
const OperationError = Lexer.Literal.OperationError;

allocator: Allocator,
expr_pool: ExprPool,
tokens: []const Token,
current: usize,

const Self = @This();
const ParsingError = error{
    UnexpectedToken,
    NotExpression,
};

const ParseExprResult = ParsingError!*Expr;

pub fn init(allocator: Allocator, tokens: []const Token) !Self {
    const prealloc_size = common.preallocSize(tokens.len);
    return .{
        .allocator = allocator,
        .expr_pool = try .initCapacity(allocator, prealloc_size),
        .tokens = tokens,
        .current = 0,
    };
}

pub fn fromLexer(lexer: Lexer) !Self {
    return try .init(lexer.allocator, lexer.tokens.items);
}

pub fn deinit(self: *Self) void {
    self.expr_pool.deinit(self.allocator);
}

fn fallBackEof(self: Self) *const Token {
    return &self.tokens[self.tokens.len - 1];
}

fn isDone(self: Self) bool {
    return self.current >= self.tokens.len or self.tokens[self.current].kind == .eof;
}

fn peek(self: Self) *const Token {
    if (!self.isDone())
        return &self.tokens[self.current];

    return self.fallBackEof();
}

fn previous(self: Self) *const Token {
    if (self.current > 0)
        return &self.tokens[self.current - 1];

    return self.fallBackEof();
}

fn next(self: *Self) *const Token {
    if (!self.isDone()) {
        self.current += 1;
        return self.previous();
    }
    return self.fallBackEof();
}

fn validateToken(self: Self, kind: TokenKind) bool {
    if (self.peek().kind == kind)
        return true;

    return false;
}

fn matchTokens(self: *Self, kinds: []const TokenKind) bool {
    for (kinds) |kind| {
        if (self.validateToken(kind)) {
            self.current += 1;
            return true;
        }
    }
    return false;
}

fn nextExpect(self: *Self, kind: TokenKind, lexeme: []const u8) ParsingError!*const Token {
    if (self.validateToken(kind))
        return self.next();

    const peeked = self.peek();
    log.err("[line {}]: Expected '{s}', got '{s}'", .{
        peeked.line,
        lexeme,
        peeked.lexeme,
    });

    return error.UnexpectedToken;
}

pub fn parseExpr(self: *Self) ParseExprResult {
    return try self.commaExpr();
}

fn commaExpr(self: *Self) ParseExprResult {
    var lhs = try self.conditionExpr();

    while (self.matchTokens(&.{.comma})) {
        const operator = self.previous().kind;
        const rhs = try self.conditionExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn conditionExpr(self: *Self) ParseExprResult {
    var lhs = try self.equalityExpr();

    while (self.matchTokens(&.{ .dan, .atau })) {
        const operator = self.previous().kind;
        const rhs = try self.equalityExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn equalityExpr(self: *Self) ParseExprResult {
    var lhs = try self.compareExpr();

    while (self.matchTokens(&.{ .equal_equal, .bang_equal })) {
        const operator = self.previous().kind;
        const rhs = try self.compareExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn compareExpr(self: *Self) ParseExprResult {
    var lhs = try self.bitOpExpr();

    while (self.matchTokens(&.{ .less, .less_equal, .greater, .greater_equal })) {
        const operator = self.previous().kind;
        const rhs = try self.bitOpExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn bitOpExpr(self: *Self) ParseExprResult {
    var lhs = try self.bitMoveExpr();

    while (self.matchTokens(&.{ .ampersand, .caret, .bar })) {
        const operator = self.previous().kind;
        const rhs = try self.bitMoveExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn bitMoveExpr(self: *Self) ParseExprResult {
    var lhs = try self.termExpr();

    while (self.matchTokens(&.{ .less_less, .greater_greater })) {
        const operator = self.previous().kind;
        const rhs = try self.termExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn termExpr(self: *Self) ParseExprResult {
    var lhs = try self.factorExpr();

    while (self.matchTokens(&.{ .plus, .minus })) {
        const operator = self.previous().kind;
        const rhs = try self.factorExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn factorExpr(self: *Self) ParseExprResult {
    var lhs = try self.unaryExpr();

    while (self.matchTokens(&.{ .slash, .star, .percent })) {
        const operator = self.previous().kind;
        const rhs = try self.unaryExpr();
        lhs = self.initExpr(.{ .binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn unaryExpr(self: *Self) ParseExprResult {
    if (self.matchTokens(&.{ .minus, .bang, .tilde })) {
        const operator = self.previous().kind;
        const primary = try self.unaryExpr();
        return self.initExpr(.{
            .unary = .{
                .operator = operator,
                .expr = primary,
            },
        });
    }

    return try self.primaryExpr();
}

fn primaryExpr(self: *Self) ParseExprResult {
    if (self.matchTokens(&.{
        .benar,
        .salah,
        .int,
        .float,
        .string,
        .hampa,
    })) {
        return self.initExpr(.{
            .primary = self.previous().data orelse return error.NotExpression,
        });
    }

    if (self.matchTokens(&.{.left_paren})) {
        const inside = try self.parseExpr();
        _ = try self.nextExpect(.right_paren, ")");
        return inside;
    }

    return error.NotExpression;
}

fn initExpr(self: *Self, expr: Expr) *Expr {
    const heaped = self.expr_pool.create(self.allocator) catch unreachable;
    heaped.* = expr;
    return heaped;
}

pub const Expr = union(enum) {
    primary: Literal,
    group: *Expr,
    unary: struct {
        operator: TokenKind,
        expr: *Expr,
    },
    binary: struct {
        operator: TokenKind,
        lhs: *Expr,
        rhs: *Expr,
    },

    pub const EvalError = error{
        WrongOperator,
    } || OperationError;

    const EvalResult = EvalError!Literal;
    pub const eval = Self.eval;
};

fn eval(self: *Expr, a: Allocator) Expr.EvalResult {
    return switch (self.*) {
        .primary => self.primary,
        .group => try eval(self, a),
        .unary => switch (try eval(self.unary.expr, a)) {
            .boolean => |expr| if (self.unary.operator == .bang)
                .{ .boolean = !expr }
            else
                error.WrongOperator,

            .int => |expr| switch (self.unary.operator) {
                .minus => .{ .int = -%expr }, // wrap around
                .tilde => .{ .int = ~expr },
                else => error.WrongOperator,
            },

            .float => |expr| if (self.unary.operator == .minus)
                .{ .float = -expr }
            else
                error.WrongOperator,

            else => error.TypeMissMatch,
        },
        .binary => |binary| blk: {
            const lhs = try eval(binary.lhs, a);
            const rhs = try eval(binary.rhs, a);
            break :blk switch (binary.operator) {
                .plus => lhs.add(rhs),
                .minus => lhs.subtract(rhs),
                .star => lhs.multiply(rhs),
                .slash => lhs.divide(rhs),
                .percent => lhs.remainder(rhs),
                .dan => lhs.boolAnd(rhs),
                .atau => lhs.boolOr(rhs),
                .equal_equal => lhs.cmpEqual(rhs, a),
                .bang_equal => lhs.cmpNotEqual(rhs, a),
                .less => lhs.cmpLess(rhs),
                .less_equal => lhs.cmpLessEqual(rhs),
                .greater => lhs.cmpGreater(rhs),
                .greater_equal => lhs.cmpGreaterEqual(rhs),
                .ampersand => lhs.bitAnd(rhs),
                .bar => lhs.bitOr(rhs),
                .caret => lhs.bitXor(rhs),
                .less_less => lhs.bitShiftLeft(rhs),
                .greater_greater => lhs.bitShiftRight(rhs),
                .comma => rhs,
                else => unreachable,
            };
        },
    };
}
