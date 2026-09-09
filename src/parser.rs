use crate::{
    lexer::{Literal, Token, TokenKind},
    literal::OperationError,
};

#[derive(Debug, Clone, Copy)]
pub struct Parser<'a> {
    tokens: &'a [Token<'a>],
    now: usize,
}

#[derive(Debug, Clone)]
pub enum Expr<'a> {
    Primary(Literal<'a>),
    Group(Box<Self>),
    Unary(TokenKind, Box<Self>),
    Binary {
        operator: TokenKind,
        lhs: Box<Self>,
        rhs: Box<Self>,
    },
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ParsingError {
    UnexpectedToken,
    NotExpression,
}

pub type ParseExprResult<'a> = Result<Box<Expr<'a>>, ParsingError>;

impl<'a> Parser<'a> {
    pub fn from(tokens: &'a [Token<'a>]) -> Self {
        Self { tokens, now: 0 }
    }

    fn fallback_eof(self) -> &'a Token<'a> {
        self.tokens.last().unwrap()
    }

    fn is_done(self) -> bool {
        match self.tokens.get(self.now) {
            Some(ok) if ok.kind == TokenKind::Eof => true,
            None => true,
            _ => false,
        }
    }

    fn peek(self) -> &'a Token<'a> {
        if !self.is_done() {
            return &self.tokens[self.now];
        }
        self.fallback_eof()
    }

    fn previous(self) -> &'a Token<'a> {
        match self.now {
            0 => self.fallback_eof(),
            other => &self.tokens[other - 1],
        }
    }

    fn next(&mut self) -> &'a Token<'a> {
        match self.now {
            0 => self.fallback_eof(),
            other => {
                self.now += 1;
                &self.tokens[other - 1]
            }
        }
    }

    fn is_matches(self, ctx: TokenKind) -> bool {
        if self.peek().kind == ctx {
            return true;
        }
        false
    }

    fn find_matches<const N: usize>(&mut self, ctxs: [TokenKind; N]) -> bool {
        for token in ctxs {
            if self.is_matches(token) {
                self.now += 1;
                return true;
            }
        }
        false
    }

    fn strict_next(&mut self, expect: TokenKind) -> Result<&'a Token<'a>, ParsingError> {
        if self.is_matches(expect) {
            return Ok(self.next());
        }

        let peek = self.peek();

        eprintln!(
            "[ERROR] (line {}): Expected {:#?}, found {:#?} in \"{}\"",
            peek.line, expect, peek.kind, peek.lexeme,
        );

        Err(ParsingError::UnexpectedToken)
    }

    pub fn expr(&mut self) -> ParseExprResult<'a> {
        self.comma_expr()
    }

    fn comma_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.cond_expr()?;
        while self.find_matches([TokenKind::Comma]) {
            let operator = self.previous().kind;
            let rhs = self.cond_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn cond_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.equal_expr()?;
        while self.find_matches([TokenKind::Dan, TokenKind::Atau]) {
            let operator = self.previous().kind;
            let rhs = self.equal_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn equal_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.compar_expr()?;
        while self.find_matches([TokenKind::EqualEqual, TokenKind::BangEqual]) {
            let operator = self.previous().kind;
            let rhs = self.compar_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn compar_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.bitop_expr()?;
        while self.find_matches([
            TokenKind::Less,
            TokenKind::LessEqual,
            TokenKind::Greater,
            TokenKind::GreaterEqual,
        ]) {
            let operator = self.previous().kind;
            let rhs = self.bitop_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn bitop_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.bitmov_expr()?;
        while self.find_matches([TokenKind::Ampersand, TokenKind::Bar, TokenKind::Caret]) {
            let operator = self.previous().kind;
            let rhs = self.bitmov_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn bitmov_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.term_expr()?;
        while self.find_matches([TokenKind::LessLess, TokenKind::GreaterGreater]) {
            let operator = self.previous().kind;
            let rhs = self.term_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn term_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.factor_expr()?;
        while self.find_matches([TokenKind::Plus, TokenKind::Minus]) {
            let operator = self.previous().kind;
            let rhs = self.factor_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn factor_expr(&mut self) -> ParseExprResult<'a> {
        let mut lhs = self.unary_expr()?;
        while self.find_matches([TokenKind::Star, TokenKind::Slash, TokenKind::Percent]) {
            let operator = self.previous().kind;
            let rhs = self.unary_expr()?;
            lhs = Box::new(Expr::Binary { operator, lhs, rhs });
        }
        Ok(lhs)
    }

    fn unary_expr(&mut self) -> ParseExprResult<'a> {
        if self.find_matches([TokenKind::Bang, TokenKind::Tilde, TokenKind::Minus]) {
            let operator = self.previous().kind;
            let expr = self.unary_expr()?;
            let expr = Box::new(Expr::Unary(operator, expr));
            return Ok(expr);
        }
        self.primary_expr()
    }

    fn primary_expr(&mut self) -> ParseExprResult<'a> {
        if self.find_matches([
            TokenKind::String,
            TokenKind::Int,
            TokenKind::Float,
            TokenKind::Benar,
            TokenKind::Salah,
            TokenKind::Hampa,
        ]) {
            let data = self.previous().data.ok_or(ParsingError::NotExpression)?;
            return Ok(Box::new(Expr::Primary(data)));
        } else if self.find_matches([TokenKind::LeftParen]) {
            let data = self.expr()?;
            match self.strict_next(TokenKind::RightParen) {
                Ok(_) => return Ok(Box::new(Expr::Group(data))),
                Err(err) => return Err(err),
            }
        }
        Err(ParsingError::NotExpression)
    }
}

impl<'a> Expr<'a> {
    pub fn eval(self) -> Result<Literal<'a>, OperationError> {
        match self {
            Self::Primary(data) => Ok(data),
            Self::Group(expr) => expr.eval(),
            Self::Unary(operator, expr) => match (operator, expr.eval()?) {
                (TokenKind::Minus, Literal::Int(num)) => Ok(Literal::Int(-num)),
                (TokenKind::Tilde, Literal::Int(num)) => Ok(Literal::Int(!num)),
                (TokenKind::Minus, Literal::Float(num)) => Ok(Literal::Float(-num)),
                (TokenKind::Bang, Literal::Bool(state)) => Ok(Literal::Bool(!state)),
                _ => Err(OperationError::WrongOperator),
            },
            Self::Binary { operator, lhs, rhs } => match (operator, lhs.eval()?, rhs.eval()?) {
                (TokenKind::Plus, lhs, rhs) => lhs.add(rhs),
                (TokenKind::Minus, lhs, rhs) => lhs.sub(rhs),
                (TokenKind::Star, lhs, rhs) => lhs.mul(rhs),
                (TokenKind::Slash, lhs, rhs) => lhs.div(rhs),
                (TokenKind::Percent, lhs, rhs) => lhs.rem(rhs),
                (TokenKind::Ampersand, lhs, rhs) => lhs.bit_and(rhs),
                (TokenKind::Bar, lhs, rhs) => lhs.bit_or(rhs),
                (TokenKind::Caret, lhs, rhs) => lhs.bit_xor(rhs),
                (TokenKind::LessLess, lhs, rhs) => lhs.shift_left(rhs),
                (TokenKind::GreaterGreater, lhs, rhs) => lhs.shift_right(rhs),
                (TokenKind::EqualEqual, lhs, rhs) => lhs.cmp_eq(rhs),
                (TokenKind::BangEqual, lhs, rhs) => lhs.cmp_neq(rhs),
                (TokenKind::LessEqual, lhs, rhs) => lhs.cmp_lteq(rhs),
                (TokenKind::GreaterEqual, lhs, rhs) => lhs.cmp_gteq(rhs),
                (TokenKind::Less, lhs, rhs) => lhs.cmp_lt(rhs),
                (TokenKind::Greater, lhs, rhs) => lhs.cmp_gt(rhs),
                (TokenKind::Dan, lhs, rhs) => lhs.cond_and(rhs),
                (TokenKind::Atau, lhs, rhs) => lhs.cond_or(rhs),
                _ => Err(OperationError::WrongOperator),
            },
        }
    }
}
