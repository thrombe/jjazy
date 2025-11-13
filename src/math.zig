pub const ColorParse = struct {
    pub fn hex_u8rgba(typ: type, comptime hex: []const u8) typ {
        if (hex.len != 9 or hex[0] != '#') {
            @compileError("invalid color");
        }

        return .{
            .r = @as(u8, parseHex(hex[1], hex[2])),
            .g = @as(u8, parseHex(hex[3], hex[4])),
            .b = @as(u8, parseHex(hex[5], hex[6])),
            .a = @as(u8, parseHex(hex[7], hex[8])),
        };
    }

    fn parseHex(comptime high: u8, comptime low: u8) u8 {
        return (hexDigitToInt(high) << 4) | hexDigitToInt(low);
    }

    fn hexDigitToInt(comptime digit: u8) u8 {
        if (digit >= '0' and digit <= '9') {
            return digit - '0';
        } else if (digit >= 'a' and digit <= 'f') {
            return digit - 'a' + 10;
        } else if (digit >= 'A' and digit <= 'F') {
            return digit - 'A' + 10;
        }
        @compileError("invalid hex digit");
    }

    pub const Runtime = struct {
        pub fn hex_u8rgb(typ: type, hex: []const u8) !typ {
            if (hex.len != 7 or hex[0] != '#') {
                return error.BadRgbaHex;
            }

            return .{
                .r = @as(u8, try _parseHex(hex[1], hex[2])),
                .g = @as(u8, try _parseHex(hex[3], hex[4])),
                .b = @as(u8, try _parseHex(hex[5], hex[6])),
            };
        }

        fn _parseHex(high: u8, low: u8) !u8 {
            return (try _hexDigitToInt(high) << 4) | try _hexDigitToInt(low);
        }

        fn _hexDigitToInt(digit: u8) !u8 {
            if (digit >= '0' and digit <= '9') {
                return digit - '0';
            } else if (digit >= 'a' and digit <= 'f') {
                return digit - 'a' + 10;
            } else if (digit >= 'A' and digit <= 'F') {
                return digit - 'A' + 10;
            }
            return error.BadHex;
        }
    };
};
