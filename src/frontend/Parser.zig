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
const baik = @import("baik");
const log = std.log;
const ExprPool = std.heap.MemoryPool(Expr);
const Allocator = std.mem.Allocator;
const Lexer = @import("Lexer.zig");
const TokenKind = Lexer.TokenKind;
const Token = Lexer.Token;
const Literal = Lexer.Literal;
const OperationError = Lexer.Literal.OperationError;

const Self = @This();
const ParsingError = error{
    UnexpectedToken,
    NotExpression,
};

const ParseExprResult = ParsingError!*Expr;

allocator: Allocator,
expr_pool: ExprPool,
tokens: []const Token,
current: u64,

pub fn init(allocator: Allocator, tokens: []const Token) !Self {
    const prealloc_size = baik.determinePreallocSize(Token, tokens);
    return .{
        .allocator = allocator,
        .expr_pool = try .initCapacity(allocator, prealloc_size),
        .tokens = tokens,
        .current = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.expr_pool.deinit(self.allocator);
}

fn fallBackEof(self: *const Self) *const Token {
    return &self.tokens[self.tokens.len - 1];
}

fn isDone(self: Self) bool {
    return self.current >= self.tokens.len or self.tokens[self.current].kind == .Eof;
}

fn peek(self: *const Self) *const Token {
    if (!self.isDone())
        return &self.tokens[self.current];

    return self.fallBackEof();
}

fn previous(self: *const Self) *const Token {
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

fn validateToken(self: *const Self, kind: TokenKind) bool {
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

    while (self.matchTokens(&.{.Comma})) {
        const operator = self.previous().kind;
        const rhs = try self.conditionExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn conditionExpr(self: *Self) ParseExprResult {
    var lhs = try self.equalityExpr();

    while (self.matchTokens(&.{ .Dan, .Atau })) {
        const operator = self.previous().kind;
        const rhs = try self.equalityExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn equalityExpr(self: *Self) ParseExprResult {
    var lhs = try self.compareExpr();

    while (self.matchTokens(&.{ .EqualEqual, .BangEqual })) {
        const operator = self.previous().kind;
        const rhs = try self.compareExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn compareExpr(self: *Self) ParseExprResult {
    var lhs = try self.bitMoveExpr();

    while (self.matchTokens(&.{ .Less, .LessEqual, .Greater, .GreaterEqual })) {
        const operator = self.previous().kind;
        const rhs = try self.bitMoveExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn bitMoveExpr(self: *Self) ParseExprResult {
    var lhs = try self.bitOpExpr();

    while (self.matchTokens(&.{ .LessLess, .GreaterGreater })) {
        const operator = self.previous().kind;
        const rhs = try self.bitOpExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn bitOpExpr(self: *Self) ParseExprResult {
    var lhs = try self.termExpr();

    while (self.matchTokens(&.{ .Ampersand, .Caret, .Bar })) {
        const operator = self.previous().kind;
        const rhs = try self.termExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn termExpr(self: *Self) ParseExprResult {
    var lhs = try self.factorExpr();

    while (self.matchTokens(&.{ .Star, .Slash, .Percent })) {
        const operator = self.previous().kind;
        const rhs = try self.factorExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn factorExpr(self: *Self) ParseExprResult {
    var lhs = try self.unaryExpr();

    while (self.matchTokens(&.{ .Plus, .Minus })) {
        const operator = self.previous().kind;
        const rhs = try self.unaryExpr();
        lhs = self.initExpr(.{ .Binary = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
        } });
    }

    return lhs;
}

fn unaryExpr(self: *Self) ParseExprResult {
    if (self.matchTokens(&.{ .Minus, .Bang, .Tilde })) {
        const operator = self.previous().kind;
        const primary = try self.unaryExpr();
        return self.initExpr(.{
            .Unary = .{
                .operator = operator,
                .expr = primary,
            },
        });
    }

    return try self.primaryExpr();
}

fn primaryExpr(self: *Self) ParseExprResult {
    if (self.matchTokens(&.{
        .Benar,
        .Salah,
        .Int,
        .Float,
        .String,
        .Hampa,
    })) {
        return self.initExpr(.{
            .Primary = self.previous().data orelse unreachable,
        });
    }

    if (self.matchTokens(&.{.LeftParen})) {
        const inside = try self.parseExpr();
        _ = try self.nextExpect(.RightParen, ")");
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
    Primary: Literal,
    Group: *Expr,
    Unary: struct {
        operator: TokenKind,
        expr: *Expr,
    },
    Binary: struct {
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

fn eval(self: *Expr) Expr.EvalResult {
    switch (self.*) {
        .Primary => return self.Primary,
        .Group => return try eval(self),
        .Unary => switch (try eval(self.Unary.expr)) {
            .Bool => |expr| if (self.Unary.operator == .Bang)
                return .{ .Bool = !expr }
            else
                return error.WrongOperator,

            .Int => |expr| switch (self.Unary.operator) {
                .Minus => return .{ .Int = expr },
                .Tilde => return .{ .Int = ~expr },
                else => return error.WrongOperator,
            },

            .Float => |expr| if (self.Unary.operator == .Minus)
                return .{ .Float = -expr }
            else
                return error.WrongOperator,

            else => return error.TypeMissMatch,
        },
        .Binary => |binary| {
            const lhs = try eval(binary.lhs);
            const rhs = try eval(binary.rhs);
            switch (binary.operator) {
                .Plus => return lhs.add(rhs),
                .Minus => return lhs.subtract(rhs),
                .Star => return lhs.multiply(rhs),
                .Slash => return lhs.divide(rhs),
                .Percent => return lhs.remainder(rhs),
                .Dan => return lhs.boolAnd(rhs),
                .Atau => return lhs.boolOr(rhs),
                .EqualEqual => return lhs.cmpEqual(rhs),
                .BangEqual => return lhs.cmpNotEqual(rhs),
                .Less => return lhs.cmpLess(rhs),
                .LessEqual => return lhs.cmpLessEqual(rhs),
                .Greater => return lhs.cmpGreater(rhs),
                .GreaterEqual => return lhs.cmpGreaterEqual(rhs),
                .Ampersand => return lhs.bitAnd(rhs),
                .Bar => return lhs.bitOr(rhs),
                .Caret => return lhs.bitXor(rhs),
                .LessLess => return lhs.bitShiftLeft(rhs),
                .GreaterGreater => return lhs.bitShiftRight(rhs),
                .Comma => return rhs,
                else => unreachable,
            }
        },
    }
}
