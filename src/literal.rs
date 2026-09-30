/// Immediate data for number, string, boolean and none.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Literal<'a> {
    Int(i64),
    Float(f64),
    Bool(bool),
    String(&'a [u8]),
    Hampa,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum OperationError {
    TypeMissmatch,
    WrongOperator,
}

impl<'a> Literal<'a> {
    pub fn add(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs + rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Float(lhs + rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Float(lhs as f64 + rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Float(lhs + rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn sub(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs - rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Float(lhs - rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Float(lhs as f64 - rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Float(lhs - rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn mul(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs * rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Float(lhs * rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Float(lhs as f64 * rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Float(lhs * rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn div(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs / rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Float(lhs / rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Float(lhs as f64 / rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Float(lhs / rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn rem(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs % rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Float(lhs % rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Float(lhs as f64 % rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Float(lhs % rhs as f64),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_and(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs & rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_or(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs | rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn bit_xor(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs ^ rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn shift_left(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs.wrapping_shl(rhs as u32)),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn shift_right(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Int(lhs >> rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_eq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Bool(lhs == rhs),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Bool(lhs == rhs),
            (Self::Bool(lhs), Self::Bool(rhs)) => Self::Bool(lhs == rhs),
            (Self::Hampa, Self::Hampa) => Self::Bool(true),
            (Self::Hampa, _) | (_, Self::Hampa) => Self::Bool(false),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_neq(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match self.cmp_eq(rhs)? {
            Self::Bool(cond) => Self::Bool(!cond),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_lt(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Bool(lhs < rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Bool((lhs as f64) < rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Bool(lhs < rhs as f64),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Bool(lhs < rhs),
            _ => return Err(OperationError::TypeMissmatch),
        })
    }

    pub fn cmp_gt(self, rhs: Self) -> Result<Self, OperationError> {
        Ok(match (self, rhs) {
            (Self::Int(lhs), Self::Int(rhs)) => Self::Bool(lhs > rhs),
            (Self::Int(lhs), Self::Float(rhs)) => Self::Bool((lhs as f64) > rhs),
            (Self::Float(lhs), Self::Int(rhs)) => Self::Bool(lhs > rhs as f64),
            (Self::Float(lhs), Self::Float(rhs)) => Self::Bool(lhs > rhs),
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
