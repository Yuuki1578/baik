const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const String = union(enum) {
    normal: []const u8,
    raw: []const u8,

    const Self = @This();

    pub fn cmp(self: Self, other: Self, a: Allocator) bool {
        return blk: switch (self) {
            .normal => if (other == .normal) {
                const lhs = self.toAllocSlice(a) orelse break :blk false;
                defer a.free(lhs);
                const rhs = other.toAllocSlice(a) orelse break :blk false;
                defer a.free(rhs);

                break :blk mem.eql(u8, lhs, rhs);
            } else {
                const lhs = self.toAllocSlice(a) orelse break :blk false;
                defer a.free(lhs);

                break :blk mem.eql(u8, lhs, other.raw);
            },
            .raw => if (other == .raw) {
                break :blk mem.eql(u8, self.raw, other.raw);
            } else {
                const rhs = other.toAllocSlice(a) orelse break :blk false;
                defer a.free(rhs);

                break :blk mem.eql(u8, self.raw, rhs);
            },
        };
    }

    pub fn isNormalString(self: Self) bool {
        return switch (self) {
            .normal => true,
            .raw => false,
        };
    }

    pub fn toAllocSlice(self: Self, a: Allocator) ?[]u8 {
        const ctx = switch (self) {
            .normal => |s| if (s.len < 1) return null else s,
            .raw => |s| if (s.len < 1) return null else {
                return a.dupe(u8, s) catch null;
            },
        };

        const buf = a.alloc(u8, ctx.len) catch return null;
        var escaped: bool = false;
        var i: usize = 0;

        for (ctx) |ch| {
            const pushed = switch (ch) {
                '\\' => switch (escaped) {
                    true => blk: {
                        escaped = false;
                        break :blk '\\';
                    },
                    false => {
                        escaped = true;
                        continue;
                    },
                },

                '"', '\'', 'a', 'b', 'f', 't', 'n', 'v', 'r' => |c| switch (escaped) {
                    true => blk: {
                        const seq: u8 = switch (c) {
                            '"' => '"',
                            '\'' => '\'',
                            'a' => '\x07',
                            'b' => '\x08',
                            'f' => '\x0c',
                            't' => '\t',
                            'n' => '\n',
                            'v' => '\x0b',
                            'r' => '\r',
                            else => break,
                        };
                        escaped = false;
                        break :blk seq;
                    },
                    false => switch (c) {
                        '"' => break,
                        else => c,
                    },
                },

                else => ch,
            };
            buf[i] = pushed;
            i += 1;
        }

        return a.realloc(buf, i) catch null;
    }
};

pub const Literal = union(enum) {
    string: String,
    int: i64,
    float: f64,
    boolean: bool,
    hampa,

    const Self = @This();

    pub const OperationError = error{
        TypeMissMatch,
    };

    pub fn bitAnd(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv & rv },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn bitOr(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv | rv },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn bitXor(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv ^ rv },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn bitShiftLeft(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv <<| @as(usize, @abs(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn bitShiftRight(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| blk: {
                    const shifter: u6 = @intCast(@abs(rv));
                    break :blk .{ .int = lv >> shifter };
                },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn boolAnd(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| .{ .boolean = lv and rv },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn boolOr(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| .{ .boolean = lv or rv },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn cmpEqual(lhs: Self, rhs: Self, a: ?Allocator) OperationError!Self {
        return switch (lhs) {
            .boolean => |lv| switch (rhs) {
                .boolean => |rv| .{ .boolean = lv == rv },
                .hampa => .{ .boolean = false },
                else => error.TypeMissMatch,
            },
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .boolean = lv == rv },
                .float => |rv| .{ .boolean = @as(f64, @floatFromInt(lv)) == rv },
                .hampa => .{ .boolean = false },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .boolean = lv == rv },
                .int => |rv| .{ .boolean = lv == @as(f64, @floatFromInt(rv)) },
                .hampa => .{ .boolean = false },
                else => error.TypeMissMatch,
            },
            .string => |lv| switch (rhs) {
                .string => |rv| .{ .boolean = lv.cmp(rv, a.?) },
                .hampa => .{ .boolean = false },
                else => error.TypeMissMatch,
            },
            else => switch (rhs) {
                .hampa => .{ .boolean = true },
                else => .{ .boolean = false },
            },
        };
    }

    pub fn cmpNotEqual(lhs: Self, rhs: Self, a: ?Allocator) OperationError!Self {
        return switch (try lhs.cmpEqual(rhs, a)) {
            .boolean => |b| if (b) .{ .boolean = false } else .{ .boolean = true },
            else => error.TypeMissMatch,
        };
    }

    pub fn cmpLess(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .boolean = lv < rv },
                .float => |rv| .{ .boolean = @as(f64, @floatFromInt(lv)) < rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .boolean = lv < rv },
                .int => |rv| .{ .boolean = lv < @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn cmpLessEqual(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .boolean = lv <= rv },
                .float => |rv| .{ .boolean = @as(f64, @floatFromInt(lv)) <= rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .boolean = lv <= rv },
                .int => |rv| .{ .boolean = lv <= @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn cmpGreater(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .boolean = lv > rv },
                .float => |rv| .{ .boolean = @as(f64, @floatFromInt(lv)) > rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .boolean = lv > rv },
                .int => |rv| .{ .boolean = lv > @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn cmpGreaterEqual(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .boolean = lv >= rv },
                .float => |rv| .{ .boolean = @as(f64, @floatFromInt(lv)) >= rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .boolean = lv >= rv },
                .int => |rv| .{ .boolean = lv >= @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn add(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv + rv },
                .float => |rv| .{ .float = @as(f64, @floatFromInt(lv)) + rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .float = lv + rv },
                .int => |rv| .{ .float = lv + @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn subtract(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv -% rv },
                .float => |rv| .{ .float = @as(f64, @floatFromInt(lv)) - rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .float = lv - rv },
                .int => |rv| .{ .float = lv - @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn multiply(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| .{ .int = lv *% rv },
                .float => |rv| .{ .float = @as(f64, @floatFromInt(lv)) * rv },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| .{ .float = lv * rv },
                .int => |rv| .{ .float = lv * @as(f64, @floatFromInt(rv)) },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn divide(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| if (rv != 0) .{ .int = @divTrunc(lv, rv) } else .{ .int = 0 },
                .float => |rv| if (rv != 0.0) .{ .float = @as(f64, @floatFromInt(lv)) / rv } else .{ .float = 0.0 },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| if (rv != 0.0) .{ .float = lv / rv } else .{ .float = 0.0 },
                .int => |rv| if (rv != 0) .{ .float = lv / @as(f64, @floatFromInt(rv)) } else .{ .int = 0 },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }

    pub fn remainder(lhs: Self, rhs: Self) OperationError!Self {
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| if (rv != 0) .{ .int = @rem(lv, rv) } else .{ .int = 0 },
                .float => |rv| if (rv != 0.0) .{ .float = @rem(@as(f64, @floatFromInt(lv)), rv) } else .{ .float = 0.0 },
                else => error.TypeMissMatch,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| if (rv != 0) .{ .float = @rem(lv, rv) } else .{ .float = 0.0 },
                .int => |rv| if (rv != 0) .{ .float = @rem(lv, @as(f64, @floatFromInt(rv))) } else .{ .float = 0.0 },
                else => error.TypeMissMatch,
            },
            else => error.TypeMissMatch,
        };
    }
};
