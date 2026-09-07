use StringLiteral::*;
use std::collections::HashMap;

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
    String,
    Int,
    Float,

    Hampa,
    Salah,
    Benar,
    Dan,
    Tipe,
    Lain,
    Fungsi,
    Untuk,
    Jika,
    Atau,
    Cetak,
    Kembali,
    Induk,
    Ini,
    Variabel,
    Selama,

    Eof,
}

/// Represent 2 kind of string, `Normal` and `Raw`.
/// `Raw` string begin with backtick and it can't contains escape sequence,
/// while `Normal` don't.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum StringLiteral<'a> {
    Normal(&'a [u8]),
    Raw(&'a [u8]),
}

/// Immediate data for number, string, boolean and none.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Literal<'a> {
    Int(i64),
    Float(f64),
    Bool(bool),
    String(StringLiteral<'a>),
    Nil,
}

/// Single token contains identity of a lexeme.
#[derive(Debug, Clone, Copy)]
pub struct Token<'a> {
    pub lexeme: &'a str,
    pub kind: TokenKind,
    pub line: usize,
    pub data: Option<Literal<'a>>,
}

#[derive(Debug, Clone)]
pub struct Lexer<'a, 'b> {
    src: &'a [u8],
    result: Vec<Token<'a>>,
    error: usize,
    kw_table: HashMap<&'b [u8], TokenKind>,

    start: usize,
    now: usize,
    line: usize,
}

// 'b : 'static (auto)
impl<'a, 'b> Lexer<'a, 'b> {
    pub fn new(src: &'a [u8]) -> Self {
        let kw_table: HashMap<&'b [u8], TokenKind> = HashMap::from([
            ("dan".as_bytes(), TokenKind::Dan),
            ("tipe".as_bytes(), TokenKind::Tipe),
            ("lain".as_bytes(), TokenKind::Lain),
            ("salah".as_bytes(), TokenKind::Salah),
            ("fungsi".as_bytes(), TokenKind::Fungsi),
            ("untuk".as_bytes(), TokenKind::Untuk),
            ("jika".as_bytes(), TokenKind::Jika),
            ("hampa".as_bytes(), TokenKind::Hampa),
            ("atau".as_bytes(), TokenKind::Atau),
            ("cetak".as_bytes(), TokenKind::Cetak),
            ("kembali".as_bytes(), TokenKind::Kembali),
            ("indux".as_bytes(), TokenKind::Induk),
            ("ini".as_bytes(), TokenKind::Ini),
            ("benar".as_bytes(), TokenKind::Benar),
            ("variabel".as_bytes(), TokenKind::Variabel),
            ("selama".as_bytes(), TokenKind::Selama),
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

    fn report(&mut self, msg: &str) {
        eprintln!("[ERROR] (line {}): {msg}", self.line);
        self.error += 1;
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
        match self.peek() {
            b'/' => while self.next() != b'\n' {},
            b'*' => {
                while !self.is_done() {
                    match self.peek() {
                        b'*' if self.peek_next() == b'/' => {
                            self.next();
                            self.next();
                            return;
                        }
                        b'\n' => self.line += 1,
                        _ => {}
                    }
                    self.next();
                }
            }
            _ => self.push(TokenKind::Slash, None),
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
                b'\n' | b'\t' | b'\r' => {
                    self.report(
                        "Cannot use '\\n', '\\t', or '\\r' directly, use escape sequence instead",
                    );
                    return;
                }

                b'"' if !escaped => {
                    self.next();
                    let lexeme = Self::remove_quote(self.lexeme());
                    let lexeme = StringLiteral::Normal(lexeme);
                    self.push(TokenKind::String, Some(Literal::String(lexeme)));
                    return;
                }

                b'\\' if !escaped => escaped = true,
                b'\\' if escaped => escaped = false,

                b'"' | b'\'' | b'a' | b'b' | b'f' | b't' | b'n' | b'v' | b'r' if escaped => {
                    escaped = false
                }
                other if escaped => {
                    self.report(&format!("Unknown escape sequence of '\\{other}'"));
                    escaped = false;
                }
                _ => {}
            }
            self.next();
        }
        self.report("Missing double quote '\"'");
    }

    fn raw_string(&mut self) {
        while !self.is_done() {
            match self.peek() {
                b'`' => {
                    self.next();
                    let lexeme = self.lexeme();
                    let lexeme = Self::remove_quote(lexeme);
                    let lexeme = StringLiteral::Raw(lexeme);
                    self.push(TokenKind::String, Some(Literal::String(lexeme)));
                    return;
                }

                b'\n' => self.line += 1,
                _ => {}
            }
            self.next();
        }
        self.report("Missing backtick quote '`'");
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
                let msg = format!(r#"Parse int failed: ({err:?}) in "{lexeme}""#);
                self.report(&msg);
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
                        self.report(&format!(r#"Parse float failed: ({err:?}) in "{lexeme}""#));
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
                        self.report(&format!(r#"Parse int failed: ({err:?}) in "{lexeme}""#));
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
                TokenKind::Hampa => (*kw, Some(Literal::Nil)),
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
            other => self.report(&format!("Unknown character {other}")),
        }
    }

    pub fn scan(&mut self) {
        while !self.is_done() {
            self.scan_once();
            self.start = self.now;
        }
        self.push(TokenKind::Eof, None);
    }

    pub fn as_tokens(&self) -> Result<&[Token<'a>], usize> {
        match self.error {
            0 => Ok(self.result.as_slice()),
            too_many_err => Err(too_many_err),
        }
    }
}

impl<'a> StringLiteral<'a> {
    pub fn to_string(self) -> Option<String> {
        let string = match self {
            Normal(s) if s.len() > 0 => s,
            Raw(s) if s.len() > 0 => return String::from_utf8(s.to_vec()).ok(),
            _ => return None,
        };

        let mut buf = String::with_capacity(string.len());
        let mut escaped = false;

        for ch in string {
            let ch = match ch {
                b'\\' if escaped => {
                    escaped = false;
                    *ch
                }

                b'\\' => {
                    escaped = true;
                    continue;
                }

                b'a' | b'b' | b'f' | b't' | b'n' | b'v' | b'r' if !escaped => *ch,
                b'"' | b'\'' | b'a' | b'b' | b'f' | b't' | b'n' | b'v' | b'r' if escaped => {
                    escaped = false;
                    match ch {
                        b'"' => b'"',
                        b'\'' => b'\'',
                        b'a' => b'\x07',
                        b'b' => b'\x08',
                        b'f' => b'\x0c',
                        b't' => b'\t',
                        b'n' => b'\n',
                        b'v' => b'\x0b',
                        b'r' => b'\r',
                        _ => unreachable!(),
                    }
                }
                other => *other,
            };

            buf.push(ch as char);
        }

        buf.shrink_to_fit();
        Some(buf)
    }
}
