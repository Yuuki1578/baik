mod lexer;
mod literal;
mod parser;

use crate::{lexer::Lexer, parser::Parser};
use std::{env, fs, process};

fn read_file() -> String {
    let path = match env::args().enumerate().find(|(idx, _)| *idx == 1) {
        Some((_, path)) => path,
        _ => process::exit(1),
    };
    fs::read_to_string(path).unwrap_or_else(|err| {
        eprintln!("Error: {err}");
        Default::default()
    })
}

fn main() {
    let buf = read_file();
    let mut lexer = Lexer::new(buf.as_bytes());
    lexer.scan();

    let tokens = lexer.as_tokens().unwrap();
    for token in &tokens {
        println!("{token:?} => {:?}", token.data);
    }

    let mut parser = Parser::from(&tokens);
    let expr = parser.expr().unwrap();
    let expr = expr.eval().unwrap();

    println!("{expr:?}");
}
