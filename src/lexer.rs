pub use crate::literal::Literal;
use std::collections::HashMap;

macro_rules! report {
    ($lexer:expr, $fmt:expr) => {{
        eprintln!(concat!("[ERROR] (line {}): ", $fmt), $lexer.line);
        $lexer.error += 1;
    }};

    ($lexer:expr, $fmt:expr, $($arg:expr),* $(,)?) => {{
        eprintln!(concat!("[ERROR] (line {}): ", $fmt), $lexer.line, $($arg),*);
        $lexer.error += 1;
    }};
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum TokenKind {
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

    Ident,
    RawString,

    String,
    Int,
    Float,

    Benar,
    Salah,
    Hampa,

    Dan,
    Atau,

    Variabel,
    Fungsi,
    Tipe,
    Induk,
    Ini,

    Jika,
    Lain,
    Selama,
    Untuk,
    Kembali,
    Berhenti,
    Cetak,

    Eof,
}

/// Single token contains identity of a lexeme.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Token<'a> {
    pub lexeme: &'a str,
    pub kind: TokenKind,
    pub line: u32,
    pub data: Option<Literal<'a>>,
}

#[derive(Debug, Clone)]
pub struct Lexer<'a> {
    src: &'a [u8],
    result: Vec<Token<'a>>,
    kw_table: HashMap<&'static [u8], TokenKind>,

    start: usize,
    now: usize,
    line: u32,
    error: u32,
}

// 'b : 'static (auto)
impl<'a> Lexer<'a> {
    pub fn new(src: &'a [u8]) -> Self {
        let kw_table: HashMap<&'static [u8], TokenKind> = HashMap::from([
            // Expr
            ("benar".as_bytes(), TokenKind::Benar),
            ("salah".as_bytes(), TokenKind::Salah),
            ("hampa".as_bytes(), TokenKind::Hampa),
            // Flow
            ("dan".as_bytes(), TokenKind::Dan),
            ("atau".as_bytes(), TokenKind::Atau),
            // Declaration
            ("variabel".as_bytes(), TokenKind::Variabel),
            ("fungsi".as_bytes(), TokenKind::Fungsi),
            ("tipe".as_bytes(), TokenKind::Tipe),
            ("cetak".as_bytes(), TokenKind::Cetak),
            ("induk".as_bytes(), TokenKind::Induk),
            ("ini".as_bytes(), TokenKind::Ini),
            // Control
            ("lain".as_bytes(), TokenKind::Lain),
            ("untuk".as_bytes(), TokenKind::Untuk),
            ("jika".as_bytes(), TokenKind::Jika),
            ("kembali".as_bytes(), TokenKind::Kembali),
            ("selama".as_bytes(), TokenKind::Selama),
            ("berhenti".as_bytes(), TokenKind::Berhenti),
        ]);

        Self {
            src,
            kw_table,
            result: Vec::new(),
            line: 1,
            error: 0,
            start: 0,
            now: 0,
        }
    }

    fn is_done(&self) -> bool {
        if self.now >= self.src.len() {
            return true;
        }
        false
    }

    fn lexeme(&self) -> &'a [u8] {
        &self.src[self.start..self.now]
    }

    fn lexeme_utf8(&self) -> &'a str {
        unsafe { str::from_utf8_unchecked(self.lexeme()) }
    }

    fn push(&mut self, kind: TokenKind, data: Option<Literal<'a>>) {
        self.result.push(Token {
            kind: kind,
            data: data,
            lexeme: self.lexeme_utf8(),
            line: self.line,
        });
    }

    fn peek(&self) -> u8 {
        if self.is_done() {
            return 0;
        }
        self.src[self.now]
    }

    fn peek_next(&self) -> u8 {
        if self.is_done() || self.now + 1 >= self.src.len() {
            return 0;
        }
        self.src[self.now + 1]
    }

    fn next(&mut self) -> u8 {
        if self.is_done() {
            return 0;
        }
        let ch = self.peek();
        self.now += 1;
        ch
    }

    fn matches(&mut self, ch: u8) -> bool {
        match self.peek() {
            peek if peek != ch => return false,
            _ => self.now += 1,
        }
        true
    }

    fn push_matches(&mut self, ch: u8, ok: TokenKind, alt: TokenKind) {
        let pushed = if self.matches(ch) { ok } else { alt };

        self.push(pushed, None);
    }

    fn push_matches2(&mut self, ch: u8, ch2: u8, ok: TokenKind, ok2: TokenKind, alt: TokenKind) {
        let pushed = if self.matches(ch) {
            ok
        } else if self.matches(ch2) {
            ok2
        } else {
            alt
        };

        self.push(pushed, None);
    }

    fn comment(&mut self) {
        if self.matches(b'/') {
            while self.next() != b'\n' {}
            return;
        } else if self.matches(b'*') {
            while !self.is_done() {
                match (self.peek(), self.peek_next()) {
                    (b'*', b'/') => {
                        (self.next(), self.next());
                        return;
                    }
                    (b'\n', _) => self.line += 1,
                    _ => {}
                }
                self.next();
            }
            report!(self, "Missing '*/' in multiline comment");
        } else {
            self.push(TokenKind::Slash, None);
        }
    }

    fn remove_quote(s: &'a [u8]) -> &'a [u8] {
        if s.len() < 3 {
            &s[..0]
        } else {
            &s[1..s.len() - 1]
        }
    }

    fn string(&mut self) {
        let mut escaped = false;

        while !self.is_done() {
            match self.peek() {
                b'\x07' | b'\x08' | b'\x0C' | b'\n' | b'\r' | b'\x0B' => {
                    report!(
                        self,
                        "Cannot use '\\a'..'\\v' directly inside string, use escape sequence instead",
                    );
                    return;
                }

                b'"' if !escaped => {
                    self.next();
                    let lexeme = Self::remove_quote(self.lexeme());
                    self.push(TokenKind::String, Some(Literal::String(lexeme)));
                    return;
                }

                b'\\' if !escaped => escaped = true,
                b'\\' if escaped => escaped = false,

                b'"' | b'\'' | b'a' | b'b' | b'f' | b't' | b'n' | b'v' | b'r' if escaped => {
                    escaped = false
                }
                other if escaped => {
                    report!(self, "Unknown escape sequence of '\\{}'", other);
                    escaped = false;
                }
                _ => {}
            }
            self.next();
        }
        report!(self, "Missing double quote '\"'");
    }

    fn raw_string(&mut self) {
        while !self.is_done() {
            match self.peek() {
                b'`' => {
                    self.next();
                    let lexeme = self.lexeme();
                    let lexeme = Self::remove_quote(lexeme);
                    self.push(TokenKind::RawString, Some(Literal::String(lexeme)));
                    return;
                }

                b'\n' => self.line += 1,
                _ => {}
            }
            self.next();
        }
        report!(self, "Missing backtick quote '`'");
    }

    fn prefixed_digit(&mut self) {
        let mut has_leading_zero = false;
        let base = match self.peek() {
            b'b' => 2,
            b'o' => 8,
            b'x' => 16,

            other if other.is_ascii_digit() => {
                has_leading_zero = true;
                10
            }

            _ => {
                self.push(TokenKind::Int, Some(Literal::Int(0)));
                return;
            }
        };

        self.next();
        while !self.is_done() {
            match self.peek() {
                b'0'..=b'1' if base == 2 => {}
                b'0'..=b'7' if base == 8 => {}
                b'0'..=b'9' if base == 10 || base == 16 => {}
                b'a'..=b'f' | b'A'..=b'F' if base == 16 => {}
                _ => break,
            }
            self.next();
        }
        let leading = if has_leading_zero { 1 } else { 2 };
        let lexeme = &self.lexeme_utf8()[leading..];
        let literal = Literal::Int(match i64::from_str_radix(lexeme, base) {
            Ok(num) => num,
            Err(err) => {
                report!(self, r#"Parse int failed: ({:?}) in "{}""#, err, lexeme);
                0
            }
        });
        self.push(TokenKind::Int, Some(literal));
    }

    fn digit(&mut self, ctx: u8) {
        if ctx == b'0' && self.peek() != b'.' {
            self.prefixed_digit();
            return;
        }

        let mut is_float = false;
        while !self.is_done() {
            match self.peek() {
                b'.' if is_float => break,
                b'.' if !is_float => is_float = true,
                other if !other.is_ascii_digit() => break,
                _ => {}
            }
            self.next();
        }

        let lexeme = self.lexeme_utf8();
        let (kind, data) = if is_float {
            (
                TokenKind::Float,
                Literal::Float(match lexeme.parse() {
                    Ok(num) => num,
                    Err(err) => {
                        report!(self, r#"Parse float failed: ({:?}) in "{}""#, err, lexeme);
                        0.0
                    }
                }),
            )
        } else {
            (
                TokenKind::Int,
                Literal::Int(match lexeme.parse() {
                    Ok(num) => num,
                    Err(err) => {
                        report!(self, r#"Parse int failed: ({:?}) in "{}""#, err, lexeme);
                        0
                    }
                }),
            )
        };

        self.push(kind, Some(data));
    }

    fn keyword_ident(&mut self) {
        while !self.is_done() {
            match self.peek() {
                other if other.is_ascii_alphanumeric() || other == b'_' => {}
                _ => break,
            }
            self.next();
        }

        let lexeme = self.lexeme();
        let (kind, data) = match self.kw_table.get(lexeme) {
            Some(kw) => match *kw {
                TokenKind::Benar => (*kw, Some(Literal::Bool(true))),
                TokenKind::Salah => (*kw, Some(Literal::Bool(false))),
                TokenKind::Hampa => (*kw, Some(Literal::Hampa)),
                _ => (*kw, None),
            },
            None => (TokenKind::Ident, Option::<Literal<'a>>::None),
        };
        self.push(kind, data);
    }

    fn scan_once(&mut self) {
        let ch = self.next();
        match ch {
            b' ' | b'\t' | b'\r' => {}
            b'\n' => self.line += 1,

            b'(' => self.push(TokenKind::LeftParen, None),
            b')' => self.push(TokenKind::RightParen, None),
            b'{' => self.push(TokenKind::LeftBrace, None),
            b'}' => self.push(TokenKind::RightBrace, None),
            b',' => self.push(TokenKind::Comma, None),
            b'.' => self.push(TokenKind::Dot, None),
            b'-' => self.push(TokenKind::Minus, None),
            b'+' => self.push(TokenKind::Plus, None),
            b'*' => self.push(TokenKind::Star, None),
            b'%' => self.push(TokenKind::Percent, None),
            b';' => self.push(TokenKind::Semicolon, None),
            b'|' => self.push(TokenKind::Bar, None),
            b'&' => self.push(TokenKind::Ampersand, None),
            b'~' => self.push(TokenKind::Tilde, None),
            b'^' => self.push(TokenKind::Caret, None),

            b'=' => self.push_matches(b'=', TokenKind::EqualEqual, TokenKind::Equal),
            b'!' => self.push_matches(b'=', TokenKind::BangEqual, TokenKind::Bang),
            b'<' => self.push_matches2(
                b'=',
                b'<',
                TokenKind::LessEqual,
                TokenKind::LessLess,
                TokenKind::Less,
            ),
            b'>' => self.push_matches2(
                b'=',
                b'>',
                TokenKind::GreaterEqual,
                TokenKind::GreaterGreater,
                TokenKind::Greater,
            ),

            b'/' => self.comment(),
            b'"' => self.string(),
            b'`' => self.raw_string(),
            b'0'..=b'9' => self.digit(ch),

            other if other.is_ascii_alphanumeric() || other == b'_' => self.keyword_ident(),
            other => report!(self, "Unknown character '{}'", other as char),
        }
    }

    pub fn scan(&mut self) {
        while !self.is_done() {
            self.scan_once();
            self.start = self.now;
        }
        self.push(TokenKind::Eof, None);
    }

    pub fn as_tokens(self) -> Result<Vec<Token<'a>>, u32> {
        match self.error {
            0 => Ok(self.result),
            too_many_err => Err(too_many_err),
        }
    }
}
