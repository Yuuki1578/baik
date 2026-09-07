use crate::lexer::Literal;
use std::error::Error;
type L<'a> = Literal<'a>;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum OperationError {
    TypeMissmatch,
    WrongOperator,
}

impl std::fmt::Display for OperationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl Error for OperationError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        None
    }

    fn description(&self) -> &str {
        match self {
            Self::TypeMissmatch => "The types that being operated on isn't matches or ambigous",
            Self::WrongOperator => "The current operator is ambigous to the current expression",
        }
    }

    fn cause(&self) -> Option<&dyn Error> {
        None
    }
}

impl<'a> Literal<'a> {
    pub fn add(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs + rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Float(lhs + rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Float(lhs as f64 + rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Float(lhs + rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn sub(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs - rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Float(lhs - rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Float(lhs as f64 - rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Float(lhs - rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn mul(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs * rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Float(lhs * rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Float(lhs as f64 * rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Float(lhs * rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn div(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs / rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Float(lhs / rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Float(lhs as f64 / rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Float(lhs / rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn rem(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs % rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Float(lhs % rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Float(lhs as f64 % rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Float(lhs % rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_and(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs & rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_or(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs | rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_xor(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs ^ rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bin_and(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Bool(lhs), L::Bool(rhs)) => L::Bool(lhs && rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bin_or(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Bool(lhs), L::Bool(rhs)) => L::Bool(lhs || rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bin_not(self) -> Result<Self, OperationError> {
        Ok(match self {
            L::Bool(expr) => L::Bool(!expr),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn shift_left(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs.wrapping_shl(rhs as u32)),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn shift_right(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Int(lhs >> rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_eq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Bool(lhs == rhs),
            (L::Float(lhs), L::Float(rhs)) => L::Bool(lhs == rhs),
            (L::Bool(lhs), L::Bool(rhs)) => L::Bool(lhs == rhs),
            (L::Nil, L::Nil) => L::Bool(true),
            (L::Nil, _) | (_, L::Nil) => L::Bool(false),
            (L::String(lhs), L::String(rhs)) => L::Bool(match (lhs.to_string(), rhs.to_string()) {
                (Some(lhs), Some(rhs)) => match lhs.cmp(&rhs) {
                    std::cmp::Ordering::Equal => true,
                    _ => false,
                },
                _ => false,
            }),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_neq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match self.cmp_eq(rhs)? {
            L::Bool(cond) => L::Bool(!cond),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_lt(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Bool(lhs < rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Bool((lhs as f64) < rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Bool(lhs < rhs as f64),
            (L::Float(lhs), L::Float(rhs)) => L::Bool(lhs < rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_gt(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (L::Int(lhs), L::Int(rhs)) => L::Bool(lhs > rhs),
            (L::Int(lhs), L::Float(rhs)) => L::Bool((lhs as f64) > rhs),
            (L::Float(lhs), L::Int(rhs)) => L::Bool(lhs > rhs as f64),
            (L::Float(lhs), L::Float(rhs)) => L::Bool(lhs > rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_lteq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self.cmp_eq(rhs)?, self.cmp_lt(rhs)?) {
            (Self::Bool(eq), Self::Bool(lt)) => Self::Bool(lt || eq),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_gteq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self.cmp_eq(rhs)?, self.cmp_gt(rhs)?) {
            (Self::Bool(eq), Self::Bool(lt)) => Self::Bool(lt || eq),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cond_and(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Bool(lhs), Self::Bool(rhs)) => Self::Bool(lhs && rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cond_or(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Bool(lhs), Self::Bool(rhs)) => Self::Bool(lhs || rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }
}
