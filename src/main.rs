pub mod lexer;
pub mod literal;
pub mod parser;

use crate::lexer::{Lexer, Literal};
use crate::parser::Parser;
use std::fs;
use std::process;
use std::time::Instant;

fn main() -> Result<(), usize> {
    let tm_begin = Instant::now();
    let buf = fs::read_to_string("./example.baik").unwrap();
    let src = buf.as_bytes();
    let mut lexer = Lexer::new(src);

    lexer.scan();
    let tokens = lexer.as_tokens()?;

    let mut parser = Parser::new(tokens);
    let data = match parser.expr() {
        Ok(expr) => match expr.eval() {
            Ok(data) => data,
            Err(err) => {
                eprintln!("ERROR: {err:?}");
                process::exit(1);
            }
        },
        Err(err) => {
            eprintln!("ERROR: {err:?}");
            process::exit(2);
        }
    };

    match data {
        Literal::String(s) => println!("{:?}", s.to_string()),
        other => println!("{other:?}"),
    }

    let elapsed = Instant::now() - tm_begin;
    println!("Completed in {} sec", elapsed.as_secs_f32());

    Ok(())
}
