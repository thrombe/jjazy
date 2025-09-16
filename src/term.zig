const std = @import("std");
const builtin = @import("builtin");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const math_mod = @import("math.zig");

const unicode_mod = @import("unicode.zig");

const lay_mod = @import("lay.zig");
const Vec2 = lay_mod.Vec2;
const Region = lay_mod.Region;

// - [Terminal API (VT)](https://ghostty.org/docs/vt)
pub const codes = struct {
    pub const clear = "\x1B[2J";
    pub const sync_set = "\x1B[?2026h";
    pub const sync_reset = "\x1B[?2026l";
    pub const clear_to_line_end = "\x1B[0K";
    pub const cursor = struct {
        pub const hide = "\x1B[?25l";
        pub const show = "\x1B[?25h";
        pub const save_pos = "\x1B[s";
        pub const restore_pos = "\x1B[u";
        pub const move = "\x1B[{};{}H";
    };
    pub const screen = struct {
        pub const save = "\x1B[?47h";
        pub const restore = "\x1B[?47l";
    };
    pub const alt_buf = struct {
        pub const enter = "\x1B[?1049h";
        pub const leave = "\x1B[?1049l";
    };
    pub const mouse = struct {
        pub const enable_basic_mouse = "\x1B[?1000h";
        pub const disable_basic_mouse = "\x1B[?1000l";
        pub const enable_any_event = "\x1B[?1003h";
        pub const disable_any_event = "\x1B[?1003l";
        pub const enable_sgr_mouse_mode = "\x1B[?1006h";
        pub const disable_sgr_mouse_mode = "\x1B[?1006l";

        // - [Shift-Escape Behavior (XTSHIFTESCAPE) - CSI](https://ghostty.org/docs/vt/csi/xtshiftescape)
        pub const enable_shift_escape = "\x1B[>1s";
        pub const disable_shift_escape = "\x1B[>0s";
    };
    pub const focus = struct {
        pub const enable = "\x1B[?1004h";
        pub const disable = "\x1B[?1004l";
    };
    pub const style = struct {
        pub const reset = "\x1B[0m";
        pub const invert = "\x1B[7m";
    };

    pub const kitty = struct {
        // https://sw.kovidgoyal.net/kitty/keyboard-protocol/?utm_source=chatgpt.com#progressive-enhancement
        pub const enable_input_protocol = std.fmt.comptimePrint("\x1B[>{d}u", .{@as(u5, @bitCast(ProgressiveEnhancement{
            .disambiguate_escape_codes = true,
            .report_event_types = true,
            .report_alternate_keys = true,
            .report_all_keys_as_escape_codes = true,
            // .report_associated_text = true,
        }))});
        pub const disable_input_protocol = "\x1B[<u";

        pub const ProgressiveEnhancement = packed struct(u5) {
            disambiguate_escape_codes: bool = false,
            report_event_types: bool = false,
            report_alternate_keys: bool = false,
            report_all_keys_as_escape_codes: bool = false,
            report_associated_text: bool = false,
        };
    };
};

pub const symbols = struct {
    pub const arrow = struct {
        pub const up = "↑";
        pub const down = "↓";
        pub const left = "←";
        pub const right = "→";
    };
    pub const key = struct {
        pub const backspace = "⌫";
        pub const tab = "⌫";
        pub const space = "␣";
        pub const shift = "⇧";
    };
    pub const border = struct {
        pub const double = struct {
            pub const corners = struct {
                pub const top_left = "╔";
                pub const top_right = "╗";
                pub const bottom_left = "╚";
                pub const bottom_right = "╝";
            };
            pub const edges = struct {
                pub const vertical = "║";
                pub const horizontal = "═";
            };
            pub const cross = struct {
                pub const nse = "╠";
                pub const wse = "╦";
                pub const nws = "╣";
                pub const wne = "╩";
                pub const nwse = "╬";
            };
        };
        pub const thin = struct {
            pub const corners = struct {
                pub const rounded = struct {
                    pub const top_left = "╭";
                    pub const top_right = "╮";
                    pub const bottom_left = "╰";
                    pub const bottom_right = "╯";
                };
                pub const square = struct {
                    pub const top_left = "┌";
                    pub const top_right = "┐";
                    pub const bottom_left = "└";
                    pub const bottom_right = "┘";
                };
            };
            pub const edges = struct {
                pub const top = "▔";
                pub const bottom = "▁";
                pub const right = "▕";
                pub const left = "▏";
                pub const vertical = "│";
                pub const horizontal = "─";
            };
            pub const cross = struct {
                pub const nse = "├";
                pub const wse = "┬";
                pub const nws = "┤";
                pub const wne = "┴";
                pub const nwse = "┼";
            };
        };
        pub const block = struct {
            pub const full = "█";
            pub const corners = struct {
                pub const inverse = struct {
                    pub const top_right = "▖";
                    pub const top_left = "▗";
                    pub const bottom_right = "▘";
                    pub const bottom_left = "▝";
                };
                pub const filled = struct {
                    pub const top_right = "▜";
                    pub const top_left = "▛";
                    pub const bottom_right = "▟";
                    pub const bottom_left = "▙";
                };
            };
            pub const edges = struct {
                pub const left = "▌";
                pub const right = "▐";
                pub const top = "▀";
                pub const bottom = "▄";
            };
        };
    };
};
pub const border = struct {
    pub const none = struct {
        pub const corners = struct {
            pub const top_right = " ";
            pub const top_left = " ";
            pub const bottom_right = " ";
            pub const bottom_left = " ";
        };
        pub const edges = struct {
            pub const top = " ";
            pub const bottom = " ";
            pub const right = " ";
            pub const left = " ";
            pub const vertical = " ";
            pub const horizontal = " ";
        };
        pub const cross = struct {
            pub const nse = " ";
            pub const wse = " ";
            pub const nws = " ";
            pub const wne = " ";
            pub const nwse = " ";
        };
    };
    pub const thin = struct {
        pub const rounded = struct {
            pub const corners = symbols.border.thin.corners.rounded;
            pub const edges = symbols.border.thin.edges;
            pub const cross = symbols.border.thin.cross;
        };
        pub const square = struct {
            pub const corners = symbols.border.thin.corners.square;
            pub const edges = symbols.border.thin.edges;
            pub const cross = symbols.border.thin.cross;
        };
    };
    pub const block = struct {
        pub const filled = struct {
            pub const corners = symbols.border.block.corners.filled;
            pub const edges = symbols.border.block.edges;
            pub const cross = struct {
                pub const nse = symbols.border.block.full;
                pub const wse = symbols.border.block.full;
                pub const nws = symbols.border.block.full;
                pub const wne = symbols.border.block.full;
                pub const nwse = symbols.border.block.full;
            };
        };
        pub const inverse = struct {
            pub const corners = symbols.border.block.corners.inverse;
            pub const edges = struct {
                pub const left = symbols.border.block.edges.right;
                pub const right = symbols.border.block.edges.right;
                pub const top = symbols.border.block.edges.bottom;
                pub const bottom = symbols.border.block.edges.top;
            };
            pub const cross = struct {
                pub const nse = symbols.border.block.full;
                pub const wse = symbols.border.block.full;
                pub const nws = symbols.border.block.full;
                pub const wne = symbols.border.block.full;
                pub const nwse = symbols.border.block.full;
            };
        };
    };
};

pub const TermStyledGraphemeIterator = struct {
    width_table: *unicode_mod.WidthTable,
    utf8: std.unicode.Utf8Iterator,
    style: StyleSet = .{},

    pub const Token = struct {
        visual_width: ?u3 = null,
        grapheme: []const u8,
        codepoint: ?Codepoint,
    };

    pub const Codepoint = union(enum) {
        cursor_up: u32,
        cursor_down: u32,
        cursor_fwd: u32,
        cursor_back: u32,
        cursor_next_line: u32,
        cursor_prev_line: u32,
        cursor_horizontal_absolute: u32,
        cursor_set_position: struct { n: u32, m: u32 },
        erase_in_display: u32,
        erase_in_line: u32,
        scroll_up: u32,
        scroll_down: u32,
        cursor_get_position,

        cursor_position_save,
        cursor_position_restore,
        cursor_hide,
        enable_focus_reporting, // ESC[I and ESC[0
        disable_focus_reporting,
        enable_alt_screen,
        disable_alt_screen,
        enable_bracketed_paste, // ESC[200~ <content> ESC[201~
        disable_bracketed_paste,
        render_sync_start,
        render_sync_end,

        set_style: StyleSet,
    };
    pub const StyleSet = struct {
        weight: enum { normal, faint, bold } = .normal,
        italic: bool = false,
        underline: enum { none, single, double } = .none,
        blink: enum { none, slow, rapid } = .none,
        hide: bool = false,
        strike: bool = false,
        font: ?u4 = null,
        foreground_color: Color = .from_theme(.default_foreground),
        background_color: Color = .from_theme(.default_background),

        fn consume(self: *@This(), style: Style) void {
            switch (style) {
                .reset => self.* = .{},
                .bold => self.weight = .bold,
                .normal_intensity => self.weight = .normal,
                .faint => self.weight = .faint,
                .italic => self.italic = true,
                .no_italic => self.italic = false,
                .underline => self.underline = .single,
                .double_underline => self.underline = .double,
                .no_underline => self.underline = .none,
                .slow_blink => self.blink = .slow,
                .rapid_blink => self.blink = .rapid,
                .no_blink => self.blink = .none,
                .hide => self.hide = true,
                .strike => self.strike = true,
                .no_strike => self.strike = false,
                .font_default => self.font = null,
                .alt_font => |i| self.font = i,
                .default_foreground_color => self.foreground_color = .from_theme(.default_foreground),
                .default_background_color => self.background_color = .from_theme(.default_background),
                .foreground_color => |col| self.foreground_color = col,
                .background_color => |col| self.background_color = col,
                .invert => std.mem.swap(Color, &self.foreground_color, &self.background_color),

                .not_supported => {},
            }
        }

        pub fn write_diff(self: @This(), other: @This(), w: std.ArrayList(u8).Writer) !void {
            if (utils_mod.auto_eql(self, other, .{ .pointer_eq = .follow })) {
                return;
            }

            if (utils_mod.auto_eql(other, .{}, .{ .pointer_eq = .follow })) {
                try Style.write_to(.reset, w);
                return;
            }

            if (!utils_mod.auto_eql(self.weight, other.weight, .{})) try Style.write_to(switch (other.weight) {
                .normal => .normal_intensity,
                .faint => .faint,
                .bold => .bold,
            }, w);

            if (!utils_mod.auto_eql(self.underline, other.underline, .{})) try Style.write_to(switch (other.underline) {
                .none => .no_underline,
                .single => .underline,
                .double => .double_underline,
            }, w);

            if (!utils_mod.auto_eql(self.blink, other.blink, .{})) try Style.write_to(switch (other.blink) {
                .none => .no_blink,
                .slow => .slow_blink,
                .rapid => .rapid_blink,
            }, w);

            if (self.italic != other.italic) try Style.write_to(if (other.italic) .italic else .no_italic, w);

            if (self.strike != other.strike) try Style.write_to(if (other.strike) .strike else .no_strike, w);

            if (self.font != other.font) try Style.write_to(if (other.font) |font| .{ .alt_font = font } else .font_default, w);

            if (!utils_mod.auto_eql(self.foreground_color, other.foreground_color, .{ .pointer_eq = .follow })) {
                try Style.write_to(.{ .foreground_color = other.foreground_color }, w);
            }

            if (!utils_mod.auto_eql(self.background_color, other.background_color, .{ .pointer_eq = .follow })) {
                try Style.write_to(.{ .background_color = other.background_color }, w);
            }

            // self.hide does not matter
        }
    };
    pub const Style = union(enum) {
        reset,
        bold,
        normal_intensity,
        faint,
        italic,
        no_italic,
        underline,
        no_underline,
        slow_blink,
        rapid_blink,
        no_blink,
        invert,
        hide,
        strike,
        no_strike,
        font_default,
        alt_font: u4, // 1 to 9
        double_underline,
        default_foreground_color,
        default_background_color,
        foreground_color: Color,
        background_color: Color,

        not_supported,

        pub fn write_to(self: @This(), writer: anytype) !void {
            switch (self) {
                .reset => try writer.print("\x1B[0m", .{}),
                .bold => try writer.print("\x1B[1m", .{}),
                .faint => try writer.print("\x1B[2m", .{}),
                .italic => try writer.print("\x1B[3m", .{}),
                .no_italic => try writer.print("\x1B[23m", .{}),
                .underline => try writer.print("\x1B[4m", .{}),
                .no_underline => try writer.print("\x1B[24m", .{}),
                .slow_blink => try writer.print("\x1B[5m", .{}),
                .rapid_blink => try writer.print("\x1B[6m", .{}),
                .no_blink => try writer.print("\x1B[25m", .{}),
                .invert => try writer.print("\x1B[7m", .{}),
                .hide => try writer.print("\x1B[8m", .{}),
                .strike => try writer.print("\x1B[9m", .{}),
                .no_strike => try writer.print("\x1B[29m", .{}),
                .font_default => try writer.print("\x1B[10m", .{}),
                .normal_intensity => try writer.print("\x1B[22m", .{}),
                .alt_font => |alt| try writer.print("\x1B[{d}m", .{alt + 1}),
                .default_foreground_color => try writer.print("\x1B[39m", .{}),
                .default_background_color => try writer.print("\x1B[49m", .{}),
                .foreground_color, .background_color => |col| {
                    switch (col) {
                        .bit3 => |v| try writer.print("\x1B[{d}m", .{switch (self) {
                            .foreground_color => @as(u32, v) + 30,
                            .background_color => @as(u32, v) + 40,
                            else => unreachable,
                        }}),
                        else => {
                            switch (self) {
                                .foreground_color => try writer.print("\x1B[38", .{}),
                                .background_color => try writer.print("\x1B[48", .{}),
                                else => unreachable,
                            }
                            switch (col) {
                                .bit8 => |v| try writer.print(";5;{d}m", .{v}),
                                .bit24 => |v| try writer.print(";2;{d};{d};{d}m", .{ v[0], v[1], v[2] }),
                                else => unreachable,
                            }
                        },
                    }
                },
                .double_underline, .not_supported => {},
            }
        }
    };
    pub const Color = union(enum) {
        bit3: u3,
        bit8: u8,
        bit24: [3]u8,

        fn from_params(m: ?u32, r: ?u32, g: ?u32, b: ?u32) ?@This() {
            switch (m orelse return null) {
                5 => return .{ .bit8 = cast(u8, r orelse 0) },
                2 => return .{ .bit24 = [3]u8{
                    cast(u8, r orelse 0),
                    cast(u8, g orelse 0),
                    cast(u8, b orelse 0),
                } },
                else => return null,
            }
        }

        pub fn from_hex(comptime hex: []const u8) @This() {
            const col = math_mod.ColorParse.hex_u8rgba(struct { r: u8, g: u8, b: u8, a: u8 }, hex);
            return .{ .bit24 = [3]u8{ col.r, col.g, col.b } };
        }

        pub fn from_theme(t: enum(u8) {
            default_background = 0,
            errors = 1,
            success = 2,
            warnings = 3,
            info = 4,
            alt_info = 5,
            status = 6,
            default_foreground = 7,
            dim_text = 8,
            bright_errors = 9,
            bright_success = 10,
            bright_warnings = 11,
            bright_info = 12,
            bright_alt_info = 13,
            bright_status = 14,
            max_contrast = 15,
        }) @This() {
            return .{ .bit8 = @intFromEnum(t) };
        }
    };

    pub fn init(width_table: *unicode_mod.WidthTable, buf: []const u8) !@This() {
        const utf8_view = try std.unicode.Utf8View.init(buf);
        return .{
            .width_table = width_table,
            .utf8 = utf8_view.iterator(),
            .style = .{},
        };
    }

    pub fn next(self: *@This()) !?Token {
        // TODO: we want an iterator here that returns 1 char worth of slices :/
        //  - should take care of the combiners etc
        if (try self.next_codepoint()) |t| return t;
        // TODO: a codepoint slice is not a grapheme cluster. fix this.
        const grapheme = self.utf8.nextCodepointSlice() orelse return null;
        const len = self.codepoint_length(grapheme);
        return Token{
            .grapheme = grapheme,
            .codepoint = null,
            .visual_width = len,
        };
    }

    // null 0 1 2 or 4
    fn codepoint_length(self: *@This(), codepoint_bytes: []const u8) ?u3 {
        const codepoint = unicode_mod.WidthTable.to_u32_codepoint(codepoint_bytes);
        const width = self.width_table.length(codepoint);

        if (width == -1) {
            return null;
        } else {
            return cast(u3, width);
        }
    }

    // https://en.wikipedia.org/wiki/ANSI_escape_code#C0_control_codes
    fn next_codepoint(self: *@This()) !?Token {
        const buf = self.utf8.bytes[self.utf8.i..];
        var it = ByteIterator{ .buf = buf };
        switch (it.next() orelse return null) {
            // 0x07, 0x08, 0x09, 0x0A, 0x0C, 0x0D => return Token{ .grapheme = try self.consume(it.i), .codepoint = null },

            0x1B => switch (try it.expect()) {
                '[' => {
                    if (it.consume("6n")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .cursor_get_position };
                    if (it.consume("?1004h")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .enable_focus_reporting };
                    if (it.consume("?1004l")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .disable_focus_reporting };
                    if (it.consume("?1049h")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .enable_alt_screen };
                    if (it.consume("?1049l")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .disable_alt_screen };
                    if (it.consume("?2004h")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .enable_bracketed_paste };
                    if (it.consume("?2004l")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .disable_bracketed_paste };
                    if (it.consume("?2006h")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .render_sync_start };
                    if (it.consume("?2006l")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .render_sync_end };

                    blk: {
                        // any number of style params can come after '[' and before 'm'.
                        // so we have a sort of state machine style style parsing. here.
                        const bak = it;
                        defer it = bak;

                        var n = it.param();
                        var m: ?u32 = null;
                        var r: ?u32 = null;
                        var g: ?u32 = null;
                        var b: ?u32 = null;

                        var style = self.style;
                        while (true) {
                            switch (n orelse 0) {
                                0 => style.consume(.reset),
                                1 => style.consume(.bold),
                                2 => style.consume(.faint),
                                3 => style.consume(.italic),
                                4 => style.consume(.underline),
                                5 => style.consume(.slow_blink),
                                6 => style.consume(.rapid_blink),
                                7 => style.consume(.invert),
                                8 => style.consume(.hide),
                                9 => style.consume(.strike),
                                29 => style.consume(.no_strike),
                                10 => style.consume(.font_default),
                                11...19 => style.consume(.{ .alt_font = cast(u4, n.? - 11) }),
                                22 => style.consume(.normal_intensity),
                                23 => style.consume(.no_italic),
                                24 => style.consume(.no_underline),
                                25 => style.consume(.no_blink),

                                39 => style.consume(.default_foreground_color),
                                49 => style.consume(.default_background_color),

                                30...37 => style.consume(.{ .foreground_color = .{ .bit3 = cast(u3, n.? - 30) } }),
                                40...47 => style.consume(.{ .background_color = .{ .bit3 = cast(u3, n.? - 40) } }),

                                // handled separately
                                38, 48 => {
                                    _ = it.consume(";");
                                    m = it.param();
                                    _ = it.consume(";");
                                    r = it.param();
                                    _ = it.consume(";");
                                    g = it.param();
                                    _ = it.consume(";");
                                    b = it.param();

                                    switch (n.?) {
                                        // TODO: orelse should be error
                                        38 => style.consume(.{ .foreground_color = Color.from_params(m, r, g, b) orelse Color.from_theme(.default_foreground) }),
                                        48 => style.consume(.{ .background_color = Color.from_params(m, r, g, b) orelse Color.from_theme(.default_background) }),
                                        else => {},
                                    }
                                },

                                20...21, 26...28, 50...107 => style.consume(.not_supported),
                                else => {},
                            }

                            if (it.consume("m")) {
                                self.style = style;
                                return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .set_style = style } };
                            }

                            m = null;
                            r = null;
                            g = null;
                            b = null;
                            _ = it.consume(";");
                            n = it.param() orelse break :blk;
                        }
                    }

                    const n = it.param();
                    _ = it.consume(";");
                    const m = it.param();
                    switch (try it.expect()) {
                        'A' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_up = n orelse 1 } },
                        'B' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_down = n orelse 1 } },
                        'C' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_fwd = n orelse 1 } },
                        'D' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_back = n orelse 1 } },
                        'E' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_next_line = n orelse 1 } },
                        'F' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_prev_line = n orelse 1 } },
                        'G' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_horizontal_absolute = n orelse 1 } },
                        'H' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .cursor_set_position = .{ .n = n orelse 1, .m = m orelse 1 } } },
                        'J' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .erase_in_display = n orelse 0 } },
                        'K' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .erase_in_line = n orelse 0 } },
                        'S' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .scroll_up = n orelse 1 } },
                        'T' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .scroll_down = n orelse 1 } },
                        's' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .cursor_position_save },
                        'u' => return Token{ .grapheme = try self.consume(it.i), .codepoint = .cursor_position_restore },

                        else => return error.CannotHandleThisByte,
                    }
                },
                else => return error.CannotHandleThisByte,
            },
            else => return null,
        }
    }

    fn consume(self: *@This(), n: u32) ![]const u8 {
        const buf = self.utf8.bytes[self.utf8.i..];
        if (buf.len < n) return error.ExpectedMoreBytes;
        self.utf8.i += n;
        return buf[0..n];
    }

    const ByteIterator = struct {
        buf: []const u8,
        i: u32 = 0,

        fn peek(self: *@This()) ?u8 {
            if (self.buf.len > self.i) {
                return self.buf[self.i];
            }
            return null;
        }

        fn next(self: *@This()) ?u8 {
            if (self.buf.len > self.i) {
                defer self.i += 1;
                return self.buf[self.i];
            }
            return null;
        }

        fn expect(self: *@This()) !u8 {
            return self.next() orelse return error.ExpectedAnotherByte;
        }

        fn param(self: *@This()) ?u32 {
            var n: ?u32 = null;
            while (self.peek()) |x| switch (x) {
                '0'...'9' => {
                    if (n == null) n = 0;
                    n.? *= 10;
                    n.? += x - '0';
                    self.i += 1;
                },
                else => return n,
            };
            return n;
        }

        fn consume(self: *@This(), buf: []const u8) bool {
            var it = self.*;
            for (buf) |c| {
                const d = it.next() orelse return false;
                if (c != d) return false;
            }
            self.* = it;
            return true;
        }
    };
};

pub const TermInputIterator = struct {
    emu: Term.Emulator,
    features: Term.Features,
    input: utils_mod.Deque(u8),

    pub const Input = union(enum) {
        key: struct { key: u8, mod: Modifiers = .{}, action: Action = .press },
        functional: struct { key: FunctionalKey, mod: Modifiers = .{}, action: Action = .press },
        mouse: struct { pos: Vec2, key: MouseKey, mod: Modifiers = .{}, action: Action = .press },
        focus: enum { in, out },
        unsupported: u8,
    };
    pub const Modifiers = packed struct(u8) {
        shift: bool = false,
        alt: bool = false,
        ctrl: bool = false,
        super: bool = false,
        hyper: bool = false,
        meta: bool = false,
        caps_lock: bool = false,
        num_lock: bool = false,

        pub fn eq(self: @This(), other: @This()) bool {
            return std.meta.eql(self, other);
        }
    };
    pub const Action = enum(u2) {
        none = 0,
        press = 1,
        repeat = 2,
        release = 3,

        pub fn just_pressed(self: @This()) bool {
            return switch (self) {
                .none => false,
                .press => true,
                .repeat => false,
                .release => false,
            };
        }

        pub fn pressed(self: @This()) bool {
            return switch (self) {
                .none => false,
                .press => true,
                .repeat => true,
                .release => false,
            };
        }

        pub fn just_released(self: @This()) bool {
            return switch (self) {
                .none => false,
                .press => false,
                .repeat => false,
                .release => true,
            };
        }

        pub fn repeated(self: @This()) bool {
            return switch (self) {
                .none => false,
                .press => false,
                .repeat => true,
                .release => false,
            };
        }
    };
    pub const FunctionalKey = enum(u16) {
        escape = 27, // 27 u
        enter = 13, // 13 u
        tab = 9, // 9 u
        backspace = 127, // 127 u
        insert = 2, // 2 ~
        delete = 3, // 3 ~

        // collision
        left = 201, // 1 D
        right = 202, // 1 C
        up = 203, // 1 A
        down = 204, // 1 B

        page_up = 5, // 5 ~
        page_down = 6, // 6 ~
        home = 7, // 1 H or 7 ~
        end = 8, // 1 F or 8 ~
        caps_lock = 57358, // 57358 u
        scroll_lock = 57359, // 57359 u
        num_lock = 57360, // 57360 u
        print_screen = 57361, // 57361 u
        pause = 57362, // 57362 u
        menu = 57363, // 57363 u
        f1 = 11, // 1 P or 11 ~
        f2 = 12, // 1 Q or 12 ~

        // oof. collision
        f3 = 205, // 13 ~

        f4 = 14, // 1 S or 14 ~
        f5 = 15, // 15 ~
        f6 = 17, // 17 ~
        f7 = 18, // 18 ~
        f8 = 19, // 19 ~
        f9 = 20, // 20 ~
        f10 = 21, // 21 ~
        f11 = 23, // 23 ~
        f12 = 24, // 24 ~
        f13 = 57376, // 57376 u
        f14 = 57377, // 57377 u
        f15 = 57378, // 57378 u
        f16 = 57379, // 57379 u
        f17 = 57380, // 57380 u
        f18 = 57381, // 57381 u
        f19 = 57382, // 57382 u
        f20 = 57383, // 57383 u
        f21 = 57384, // 57384 u
        f22 = 57385, // 57385 u
        f23 = 57386, // 57386 u
        f24 = 57387, // 57387 u
        f25 = 57388, // 57388 u
        f26 = 57389, // 57389 u
        f27 = 57390, // 57390 u
        f28 = 57391, // 57391 u
        f29 = 57392, // 57392 u
        f30 = 57393, // 57393 u
        f31 = 57394, // 57394 u
        f32 = 57395, // 57395 u
        f33 = 57396, // 57396 u
        f34 = 57397, // 57397 u
        f35 = 57398, // 57398 u
        kp_0 = 57399, // 57399 u
        kp_1 = 57400, // 57400 u
        kp_2 = 57401, // 57401 u
        kp_3 = 57402, // 57402 u
        kp_4 = 57403, // 57403 u
        kp_5 = 57404, // 57404 u
        kp_6 = 57405, // 57405 u
        kp_7 = 57406, // 57406 u
        kp_8 = 57407, // 57407 u
        kp_9 = 57408, // 57408 u
        kp_decimal = 57409, // 57409 u
        kp_divide = 57410, // 57410 u
        kp_multiply = 57411, // 57411 u
        kp_subtract = 57412, // 57412 u
        kp_add = 57413, // 57413 u
        kp_enter = 57414, // 57414 u
        kp_equal = 57415, // 57415 u
        kp_separator = 57416, // 57416 u
        kp_left = 57417, // 57417 u
        kp_right = 57418, // 57418 u
        kp_up = 57419, // 57419 u
        kp_down = 57420, // 57420 u
        kp_page_up = 57421, // 57421 u
        kp_page_down = 57422, // 57422 u
        kp_home = 57423, // 57423 u
        kp_end = 57424, // 57424 u
        kp_insert = 57425, // 57425 u
        kp_delete = 57426, // 57426 u
        kp_begin = 57427, // 1 E or 57427 ~
        media_play = 57428, // 57428 u
        media_pause = 57429, // 57429 u
        media_play_pause = 57430, // 57430 u
        media_reverse = 57431, // 57431 u
        media_stop = 57432, // 57432 u
        media_fast_forward = 57433, // 57433 u
        media_rewind = 57434, // 57434 u
        media_track_next = 57435, // 57435 u
        media_track_previous = 57436, // 57436 u
        media_record = 57437, // 57437 u
        lower_volume = 57438, // 57438 u
        raise_volume = 57439, // 57439 u
        mute_volume = 57440, // 57440 u
        left_shift = 57441, // 57441 u
        left_control = 57442, // 57442 u
        left_alt = 57443, // 57443 u
        left_super = 57444, // 57444 u
        left_hyper = 57445, // 57445 u
        left_meta = 57446, // 57446 u
        right_shift = 57447, // 57447 u
        right_control = 57448, // 57448 u
        right_alt = 57449, // 57449 u
        right_super = 57450, // 57450 u
        right_hyper = 57451, // 57451 u
        right_meta = 57452, // 57452 u
        iso_level3_shift = 57453, // 57453 u
        iso_level5_shift = 57454, // 57454 u
    };
    pub const MouseKey = enum(u8) {
        left = 0,
        middle = 1,
        right = 2,
        move = 35,
        scroll_up = 64,
        scroll_down = 65,
        scroll_left = 66,
        scroll_right = 67,
    };

    pub fn add(self: *@This(), char: u8) !void {
        try self.input.push_back(char);
    }

    // https://sw.kovidgoyal.net/kitty/keyboard-protocol/
    pub fn next(self: *@This()) !?Input {
        const bak = self.*;
        errdefer self.* = bak;

        const c = self.pop() orelse return null;
        switch (c) {
            0x1B => switch (try self.expect()) {
                '[' => {
                    const unicode_keycode = self.param() orelse {
                        // alacritty sends legacy codes even when using kitty :/
                        switch (try self.expect()) {
                            'A' => return .{ .functional = .{ .key = .up } },
                            'B' => return .{ .functional = .{ .key = .down } },
                            'C' => return .{ .functional = .{ .key = .right } },
                            'D' => return .{ .functional = .{ .key = .left } },
                            'E' => return .{ .functional = .{ .key = .kp_begin } },
                            'F' => return .{ .functional = .{ .key = .end } },
                            'H' => return .{ .functional = .{ .key = .home } },
                            'P' => return .{ .functional = .{ .key = .f1 } },
                            'Q' => return .{ .functional = .{ .key = .f2 } },
                            'R' => return .{ .functional = .{ .key = .f3 } },
                            'S' => return .{ .functional = .{ .key = .f4 } },

                            // mouse input
                            '<' => {
                                const buttons = self.param() orelse return self.expect_byte_else(error.ExpectedMouseButtons);
                                _ = self.consume(";");
                                const x = self.param() orelse return self.expect_byte_else(error.ExpectedMouseX);
                                _ = self.consume(";");
                                const y = self.param() orelse return self.expect_byte_else(error.ExpectedMouseY);
                                _ = self.consume(";");
                                var action: Action = switch (try self.expect()) {
                                    'm' => .release,
                                    'M' => .press,
                                    else => return error.UnexpectedByte,
                                };
                                if (buttons & 0b0100000 > 0) action = .repeat;

                                const button: MouseKey = switch (buttons & 0b1100011) {
                                    0, 32 => .left,
                                    1, 33 => .middle,
                                    2, 34 => .right,
                                    35 => .move,
                                    64 => .scroll_up,
                                    65 => .scroll_down,
                                    66 => .scroll_left,
                                    67 => .scroll_right,
                                    else => return error.UnexpectedParam,
                                };

                                const mod: Modifiers = .{
                                    .shift = buttons & 0b0000100 > 0,
                                    .alt = buttons & 0b0001000 > 0,
                                    .ctrl = buttons & 0b0010000 > 0,
                                };

                                return Input{ .mouse = .{
                                    .pos = .{ .x = cast(i32, x), .y = cast(i32, y) },
                                    .key = button,
                                    .mod = mod,
                                    .action = action,
                                } };
                            },

                            // focus events
                            'I' => return Input{ .focus = .in },
                            'O' => return Input{ .focus = .out },

                            else => return error.ExpectedParam,
                        }
                        return error.ExpectedParam;
                    };
                    const shifted_keycode = if (self.consume(":")) self.param() else null;
                    const base_layout_key = if (self.consume(":")) self.param() else null;
                    const mod: Modifiers = if (self.consume(";")) @bitCast(@as(u8, @intCast(self.param() orelse 1)) - 1) else .{};
                    const action: Action = if (self.consume(":")) try std.meta.intToEnum(Action, self.param() orelse 1) else .press;
                    const end = try self.expect();

                    _ = base_layout_key;
                    // std.log.debug("unicode-keycode: {d}", .{unicode_keycode});
                    // std.log.debug("shifted-keycode: {?d}", .{shifted_keycode});
                    // std.log.debug("base-layout-key: {?d}", .{base_layout_key});
                    // std.log.debug("modifiers: {any}", .{mod});
                    // std.log.debug("action: {any}", .{action});
                    // std.log.debug("end: {d}", .{end});

                    switch (end) {
                        'u' => switch (unicode_keycode) {
                            'a'...'z',
                            'A'...'Z',
                            '0'...'9',
                            ' ',
                            33...47, // !"#$%&'()*+,-./
                            58...64, // :;<=>?@
                            91...96, // [\]^_
                            123...126, // {|}~
                            => return Input{ .key = .{ .key = cast(u8, shifted_keycode orelse unicode_keycode), .mod = mod, .action = action } },
                            else => return Input{ .functional = .{
                                .key = try std.meta.intToEnum(FunctionalKey, unicode_keycode),
                                .mod = mod,
                                .action = action,
                            } },
                        },
                        '~' => switch (unicode_keycode) {
                            13 => return Input{ .functional = .{ .key = .f3, .mod = mod, .action = action } },
                            else => return Input{ .functional = .{
                                .key = try std.meta.intToEnum(FunctionalKey, unicode_keycode),
                                .mod = mod,
                                .action = action,
                            } },
                        },
                        else => if (unicode_keycode == 1) switch (end) {
                            'A' => return .{ .functional = .{ .key = .up, .mod = mod, .action = action } },
                            'B' => return .{ .functional = .{ .key = .down, .mod = mod, .action = action } },
                            'C' => return .{ .functional = .{ .key = .right, .mod = mod, .action = action } },
                            'D' => return .{ .functional = .{ .key = .left, .mod = mod, .action = action } },
                            'E' => return .{ .functional = .{ .key = .kp_begin, .mod = mod, .action = action } },
                            'F' => return .{ .functional = .{ .key = .end, .mod = mod, .action = action } },
                            'H' => return .{ .functional = .{ .key = .home, .mod = mod, .action = action } },
                            'P' => return .{ .functional = .{ .key = .f1, .mod = mod, .action = action } },
                            'Q' => return .{ .functional = .{ .key = .f2, .mod = mod, .action = action } },
                            'R' => return .{ .functional = .{ .key = .f3, .mod = mod, .action = action } },
                            'S' => return .{ .functional = .{ .key = .f4, .mod = mod, .action = action } },
                            else => return error.UnexpectedByte,
                        } else return error.UnexpectedByte,
                    }
                },
                else => {
                    // std.log.debug("non kitty kb event: {d}", .{c});

                    switch (c) {
                        // TODO: pressing escape in non-kitty sends 0x1b once. which is kinda ignored by the input handling code.
                        //   this line only executes when escape is pressed twice
                        //   - look up how helix does this
                        0x1B => {
                            // OOF: zellij alt + backspace sends (27 0x1b) twice
                            if (self.features.kitty_kb and self.emu.zellij) {
                                return Input{ .functional = .{ .key = .backspace, .mod = .{ .alt = true } } };
                            } else {
                                return Input{ .functional = .{ .key = .escape } };
                            }
                        },
                        else => {
                            std.log.debug("unexpected byte: {d}", .{c});
                            return error.UnsupportedEscapeCode;
                        },
                    }
                },
            },
            else => {
                // std.log.debug("non kitty kb event: {d}", .{c});

                switch (c) {
                    'A'...'Z' => return Input{ .key = .{ .key = cast(u8, c), .mod = .{ .shift = true } } },
                    'a'...'z',
                    '0'...'9',
                    ' ',
                    33...47, // !"#$%&'()*+,-./
                    58...64, // :;<=>?@
                    91...96, // [\]^_
                    123...126, // {|}~
                    => return Input{ .key = .{ .key = cast(u8, c) } },
                    127 => return Input{ .functional = .{ .key = .backspace } },
                    '\t' => return Input{ .functional = .{ .key = .tab } },
                    '\r' => return Input{ .functional = .{ .key = .enter } }, // more useful as enter
                    '\n' => return Input{ .key = .{ .key = 'j', .mod = .{ .ctrl = true } } }, // more useful as ctrl j
                    11 => return Input{ .key = .{ .key = 'k', .mod = .{ .ctrl = true } } }, // obsolete key otherwise
                    8 => return Input{ .functional = .{ .key = .backspace } }, // obsolete key otherwise
                    else => {
                        std.log.err("unsupported input event: {d}", .{c});
                        return .{ .unsupported = c };
                    },
                }
            },
        }
    }

    fn pop(self: *@This()) ?u8 {
        return self.input.pop_front();
    }

    fn expect(self: *@This()) !u8 {
        return self.pop() orelse error.ExpectedByte;
    }

    fn consume(self: *@This(), buf: []const u8) bool {
        var it = self.*;
        for (buf) |c| {
            const d = it.pop() orelse return false;
            if (c != d) return false;
        }
        self.* = it;
        return true;
    }

    fn param(self: *@This()) ?u32 {
        var n: ?u32 = null;
        while (self.input.peek_front()) |x| switch (x.*) {
            '0'...'9' => {
                if (n == null) n = 0;
                n.? *= 10;
                n.? += x.* - '0';
                _ = self.input.pop_front();
            },
            else => return n,
        };
        return n;
    }

    fn is_empty(self: *@This()) bool {
        return self.input.peek_front() == null;
    }

    fn expect_byte_else(self: *@This(), els: anytype) anyerror {
        if (self.is_empty()) return error.ExpectedByte;
        return els;
    }
};

pub const Term = struct {
    tty: std.fs.File,
    screen: Region = .{ .size = .{} },
    cooked_termios: ?std.posix.termios = null,
    raw: ?std.posix.termios = null,

    features: Features,
    emulator: Emulator,
    envmap: std.process.EnvMap,
    alloc: std.mem.Allocator,

    const Emulator = struct {
        zellij: bool,

        // these are kinda mutually exclusive, but it's easier to use.
        kitty: bool,
        ghostty: bool,
        alacritty: bool,
    };
    const Features = struct {
        kitty_kb: bool,
        kitty_graphics: bool,

        fn init(emu: Emulator) @This() {
            // TODO: there are better ways to get this info.
            return .{
                .kitty_kb = emu.kitty or emu.ghostty or emu.alacritty,
                .kitty_graphics = emu.ghostty or emu.kitty,
            };
        }
    };

    pub fn init(alloc: std.mem.Allocator) !@This() {
        var envmap = try std.process.getEnvMap(alloc);
        errdefer envmap.deinit();

        const tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        const emu: Emulator = .{
            .zellij = std.mem.eql(u8, envmap.get("ZELLIJ") orelse "", "0"),
            .alacritty = std.mem.eql(u8, envmap.get("TERM") orelse "", "alacritty"),
            .ghostty = std.mem.eql(u8, envmap.get("TERM") orelse "", "xterm-ghostty"),
            .kitty = std.mem.eql(u8, envmap.get("TERM") orelse "", "xterm-kitty"),
        };

        std.log.info("emulator: {any}", .{emu});

        var self = @This(){
            .tty = tty,
            .features = .init(emu),
            .emulator = emu,
            .envmap = envmap,
            .alloc = alloc,
        };

        try self.update_size();

        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.envmap.deinit();
        self.tty.close();
    }

    pub fn uncook(self: *@This()) !void {
        try self.enter_raw_mode();
        try self.tty.writeAll("" ++
            codes.cursor.hide ++
            codes.alt_buf.enter ++
            codes.kitty.enable_input_protocol ++
            codes.mouse.enable_basic_mouse ++
            codes.mouse.enable_any_event ++
            codes.mouse.enable_sgr_mouse_mode ++
            codes.mouse.enable_shift_escape ++
            codes.focus.enable ++
            codes.clear ++
            "");
    }

    pub fn cook_restore(self: *@This()) !void {
        try self.tty.writeAll("" ++
            codes.mouse.disable_basic_mouse ++
            codes.mouse.disable_any_event ++
            codes.mouse.disable_sgr_mouse_mode ++
            codes.mouse.disable_shift_escape ++
            codes.kitty.disable_input_protocol ++
            codes.focus.disable ++
            codes.clear ++
            codes.alt_buf.leave ++
            codes.cursor.show ++
            codes.style.reset ++
            "");
        try std.posix.tcsetattr(self.tty.handle, .FLUSH, self.cooked_termios.?);
        self.raw = null;
        self.cooked_termios = null;
    }

    pub fn fancy_features_that_break_gdb(self: *@This(), set: enum { enable, disable }, v: struct {
        input: bool = true,
        focus: bool = true,
        mouse: bool = true,
    }) !void {
        switch (set) {
            .enable => {
                if (v.input) try self.tty.writeAll(codes.kitty.enable_input_protocol);
                if (v.focus) try self.tty.writeAll(codes.focus.enable);
                if (v.mouse) try self.tty.writeAll("" ++
                    codes.mouse.enable_basic_mouse ++
                    codes.mouse.enable_any_event ++
                    codes.mouse.enable_sgr_mouse_mode ++
                    codes.mouse.enable_shift_escape ++
                    "");
            },
            .disable => {
                if (v.input) try self.tty.writeAll(codes.kitty.disable_input_protocol);
                if (v.focus) try self.tty.writeAll(codes.focus.disable);
                if (v.mouse) try self.tty.writeAll("" ++
                    codes.mouse.disable_basic_mouse ++
                    codes.mouse.disable_any_event ++
                    codes.mouse.disable_sgr_mouse_mode ++
                    codes.mouse.disable_shift_escape ++
                    "");
            },
        }
    }

    pub fn update_size(self: *@This()) !void {
        var win_size = std.mem.zeroes(std.posix.winsize);
        const err = std.os.linux.ioctl(self.tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&win_size));
        if (std.posix.errno(err) != .SUCCESS) {
            return std.posix.unexpectedErrno(@as(std.posix.E, @enumFromInt(err)));
        }
        self.screen.size = .{ .y = win_size.row, .x = win_size.col };
    }

    fn enter_raw_mode(self: *@This()) !void {
        self.cooked_termios = try std.posix.tcgetattr(self.tty.handle);

        var raw = self.cooked_termios.?;
        //   ECHO: Stop the terminal from displaying pressed keys.
        // ICANON: Disable canonical ("cooked") input mode. Allows us to read inputs
        //         byte-wise instead of line-wise.
        //   ISIG: Disable signals for Ctrl-C (SIGINT) and Ctrl-Z (SIGTSTP), so we
        //         can handle them as "normal" escape sequences.
        // IEXTEN: Disable input preprocessing. This allows us to handle Ctrl-V,
        //         which would otherwise be intercepted by some terminals.
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        //   IXON: Disable software control flow. This allows us to handle Ctrl-S
        //         and Ctrl-Q.
        //  ICRNL: Disable converting carriage returns to newlines. Allows us to
        //         handle Ctrl-J and Ctrl-M.
        // BRKINT: Disable converting sending SIGINT on break conditions. Likely has
        //         no effect on anything remotely modern.
        //  INPCK: Disable parity checking. Likely has no effect on anything
        //         remotely modern.
        // ISTRIP: Disable stripping the 8th bit of characters. Likely has no effect
        //         on anything remotely modern.
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Disable output processing. Common output processing includes prefixing
        // newline with a carriage return.
        raw.oflag.OPOST = false;

        // Set the character size to 8 bits per byte. Likely has no efffect on
        // anything remotely modern.
        raw.cflag.CSIZE = .CS8;

        raw.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 0;
        raw.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 1;

        try std.posix.tcsetattr(self.tty.handle, .FLUSH, raw);
        self.raw = raw;
    }

    pub fn register_signal_handlers(_: *@This(), handler: anytype) void {
        std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
            .handler = .{ .handler = handler.winch },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
    }

    pub fn unregister_signal_handlers(_: *@This()) void {
        std.posix.sigaction(std.posix.SIG.WINCH, &std.os.linux.Sigaction{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
    }
};

pub const DiffTerm = struct {
    raw: struct {
        last: std.ArrayList(u8),
        curr: std.ArrayList(u8),
    },
    styled: struct {
        size: Vec2,
        last: std.ArrayList(Cell),
        curr: std.ArrayList(Cell),
    },
    cmdbuf: std.ArrayList(u8),

    const Writer = std.ArrayList(u8).Writer;

    const Style = TermStyledGraphemeIterator.StyleSet;
    const Cell = struct {
        grapheme: []const u8,
        style: Style,
    };

    fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .raw = .{
                .last = .init(alloc),
                .curr = .init(alloc),
            },
            .styled = .{
                .size = .{},
                .last = .init(alloc),
                .curr = .init(alloc),
            },
            .cmdbuf = .init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        self.raw.last.deinit();
        self.raw.curr.deinit();
        self.styled.last.deinit();
        self.styled.curr.deinit();
        self.cmdbuf.deinit();
    }

    fn resize(self: *@This(), size: Vec2) !void {
        self.styled.size = size;
        self.styled.last.clearRetainingCapacity();
        try self.styled.last.appendNTimes(.{ .grapheme = " ", .style = .{} }, @intCast(self.styled.size.x * self.styled.size.y));

        self.styled.curr.clearRetainingCapacity();
        try self.styled.curr.appendNTimes(.{ .grapheme = " ", .style = .{} }, @intCast(self.styled.size.x * self.styled.size.y));

        self.raw.last.clearRetainingCapacity();
        self.raw.curr.clearRetainingCapacity();

        try self.cmdbuf.writer().writeAll(codes.clear);
    }

    fn clear(self: *@This()) !void {
        self.raw.curr.clearRetainingCapacity();

        self.styled.curr.clearRetainingCapacity();
        try self.styled.curr.appendNTimes(.{ .grapheme = " ", .style = .{} }, @intCast(self.styled.size.x * self.styled.size.y));
    }

    fn swap(self: *@This()) void {
        std.mem.swap(std.ArrayList(u8), &self.raw.last, &self.raw.curr);
        std.mem.swap(std.ArrayList(Cell), &self.styled.last, &self.styled.curr);
    }

    fn writer(self: *@This()) Writer {
        return self.raw.curr.writer();
    }

    // render from raw.curr to styled.curr
    fn _render_styled(self: *@This(), width_table: *unicode_mod.WidthTable) !void {
        const size = self.styled.size;
        var it = try TermStyledGraphemeIterator.init(width_table, self.raw.curr.items);

        var style: Style = .{};
        var x: i32 = 0;
        var y: i32 = 0;
        while (try it.next()) |t| {
            if (t.codepoint) |c| {
                switch (c) {
                    .cursor_up => |e| y = @max(y - cast(i32, e), 0),
                    .cursor_down => |e| y = @min(y + cast(i32, e), @max(size.y - 1, 0)),
                    .cursor_fwd => |e| x = @min(x + cast(i32, e), @max(size.x - 1, 0)),
                    .cursor_back => |e| x = @max(x - cast(i32, e), 0),
                    .cursor_next_line => |e| {
                        x = 0;
                        y = @min(y + cast(i32, e), @max(size.y - 1, 0));
                    },
                    .cursor_prev_line => |e| {
                        x = 0;
                        y = @max(y - cast(i32, e), 0);
                    },
                    .cursor_horizontal_absolute => |e| {
                        x = cast(i32, e) - 1;
                        x = @max(x, 0);
                        x = @min(x, @max(size.x - 1, 0));
                    },
                    .cursor_set_position => |e| {
                        x = cast(i32, e.m - 1);
                        y = cast(i32, e.n - 1);

                        x = @max(x, 0);
                        x = @min(x, @max(size.x - 1, 0));

                        y = @max(y, 0);
                        y = @min(y, @max(size.y - 1, 0));
                    },
                    .erase_in_display => |e| {
                        _ = e;
                        return error.Todo;
                    },
                    .erase_in_line => |e| {
                        _ = e;
                        return error.Todo;
                    },

                    .scroll_up, .scroll_down, .cursor_get_position, .cursor_position_save, .cursor_position_restore, .cursor_hide, .enable_focus_reporting, .disable_focus_reporting, .enable_alt_screen, .disable_alt_screen, .enable_bracketed_paste, .disable_bracketed_paste, .render_sync_start, .render_sync_end => {
                        // ignore
                    },

                    .set_style => |e| style = e,
                }

                continue;
            }

            std.debug.assert(std.mem.indexOf(u8, t.grapheme, "\x1b[") == null);
            if (size.x == x and size.y == y) continue;
            switch (t.visual_width orelse 0) {
                0 => {},
                1 => {
                    self.styled.curr.items[cast(usize, y * size.x + x)].grapheme = t.grapheme;
                    self.styled.curr.items[cast(usize, y * size.x + x)].style = style;
                    x += 1;
                },
                2 => {
                    self.styled.curr.items[cast(usize, y * size.x + x)].grapheme = t.grapheme;
                    self.styled.curr.items[cast(usize, y * size.x + x)].style = style;

                    if (size.x > x + 1) {
                        self.styled.curr.items[cast(usize, y * size.x + x + 1)].grapheme = "\x00";
                        self.styled.curr.items[cast(usize, y * size.x + x + 1)].style = style;
                    }
                    x += 2;
                },
                4 => {
                    self.styled.curr.items[cast(usize, y * size.x + x)].grapheme = t.grapheme;
                    self.styled.curr.items[cast(usize, y * size.x + x)].style = style;

                    if (size.x > x + 1) {
                        self.styled.curr.items[cast(usize, y * size.x + x + 1)].grapheme = "\x00";
                        self.styled.curr.items[cast(usize, y * size.x + x + 1)].style = style;
                    }
                    if (size.x > x + 2) {
                        self.styled.curr.items[cast(usize, y * size.x + x + 2)].grapheme = "\x00";
                        self.styled.curr.items[cast(usize, y * size.x + x + 2)].style = style;
                    }
                    if (size.x > x + 3) {
                        self.styled.curr.items[cast(usize, y * size.x + x + 3)].grapheme = "\x00";
                        self.styled.curr.items[cast(usize, y * size.x + x + 3)].style = style;
                    }
                    x += 4;
                },
                else => unreachable,
            }
            if (x >= size.x) {
                x = 0;
                y += 1;
            }
            y = @min(y, @max(size.y - 1, 0));
        }
    }

    // render from styled.curr to cmdbuf
    fn _render_diff(self: *@This()) !void {
        const size = self.styled.size;
        var style = Style{};
        var x: i32 = 0;
        var y: i32 = 0;
        var jump = true;
        for (self.styled.last.items, self.styled.curr.items) |last, curr| {
            defer {
                x += 1;
                if (x >= size.x) {
                    x = 0;
                    y += 1;
                    jump = true;
                }
            }

            // if (true) {
            //     try Style.write_diff(.{}, curr.style, self.cmdbuf.writer());
            //     try self.cmdbuf.writer().print(codes.cursor.move, .{ y + 1, x + 1 });
            //     try self.cmdbuf.writer().writeAll(curr.grapheme);
            //     try TermStyledGraphemeIterator.Style.write_to(.reset, self.cmdbuf.writer());
            //     continue;
            // }

            if (!utils_mod.auto_eql(last, curr, .{ .pointer_eq = .follow })) {
                if (jump) {
                    try TermStyledGraphemeIterator.Style.write_to(.reset, self.cmdbuf.writer());
                    style = .{};
                    try self.cmdbuf.writer().print(codes.cursor.move, .{ y + 1, x + 1 });
                }

                if (!utils_mod.auto_eql(style, curr.style, .{ .pointer_eq = .follow })) {
                    // TODO: not sure why a reset is needed here. Style.write_diff() should have worked.
                    try TermStyledGraphemeIterator.Style.write_to(.reset, self.cmdbuf.writer());
                    style = .{};
                    try style.write_diff(curr.style, self.cmdbuf.writer());
                    style = curr.style;
                }

                try self.cmdbuf.writer().writeAll(curr.grapheme);
                jump = false;
            } else {
                jump = true;
            }
        }
        try TermStyledGraphemeIterator.Style.write_to(.reset, self.cmdbuf.writer());
    }

    fn render(self: *@This(), width_table: *unicode_mod.WidthTable) ![]const u8 {
        try self._render_styled(width_table);
        try self._render_diff();
        return self.cmdbuf.items;
    }
};

pub const Screen = struct {
    term: Term,
    diffterm: DiffTerm,
    unicode_width_table: unicode_mod.WidthTable,

    cmdbuf_id: u32 = 0,
    cmdbufs: std.ArrayList(std.ArrayList(u8)),
    depths: std.ArrayList(DepthEntry),

    alloc: std.mem.Allocator,

    const DepthEntry = struct { id: u32, depth: f32 };

    pub fn init(alloc: std.mem.Allocator, term: Term) !@This() {
        const unicode_data = @embedFile("unicode-width-table.bin");
        var unicode_data_stream = std.io.fixedBufferStream(unicode_data);
        var decomp = std.compress.flate.inflate.decompressor(.raw, unicode_data_stream.reader());

        var table = try unicode_mod.WidthTable.load_from(alloc, decomp.reader());
        errdefer table.deinit();

        return .{
            .alloc = alloc,
            .cmdbufs = .init(alloc),
            .depths = .init(alloc),
            .diffterm = .init(alloc),
            .term = term,
            .unicode_width_table = table,
        };
    }

    pub fn deinit(self: *@This()) void {
        defer {
            for (self.cmdbufs.items) |*e| {
                e.deinit();
            }
            self.cmdbufs.deinit();
        }
        defer self.term.deinit();
        defer self.depths.deinit();
        defer self.diffterm.deinit();
        defer self.unicode_width_table.deinit();
    }

    pub fn update_size(self: *@This()) !void {
        try self.term.update_size();
        try self.diffterm.resize(self.term.screen.size);
    }

    pub fn uncook(self: *@This()) !void {
        try self.term.uncook();
        try self.diffterm.resize(self.term.screen.size);
    }

    pub fn get_cmdbuf_id(self: *@This(), depth: f32) !u32 {
        defer self.cmdbuf_id += 1;
        if (self.cmdbufs.items.len <= self.cmdbuf_id) {
            try self.cmdbufs.append(.init(self.alloc));
        }
        try self.depths.append(.{ .id = self.cmdbuf_id, .depth = depth });
        return self.cmdbuf_id;
    }

    pub fn writer(self: *@This(), id: u32) std.ArrayList(u8).Writer {
        return self.cmdbufs.items[id].writer();
    }

    pub fn flush_writes(self: *@This()) !void {
        const SortCtx = struct {
            fn lessThan(_: @This(), lhs: DepthEntry, rhs: DepthEntry) bool {
                if (lhs.depth < rhs.depth) return true;
                if (lhs.depth == rhs.depth) if (lhs.id < rhs.id) return true;
                return false;
            }
        };
        std.mem.sort(DepthEntry, self.depths.items, SortCtx{}, SortCtx.lessThan);

        {
            self.diffterm.swap();
            try self.diffterm.clear();

            // submit and clear cmdbufs
            for (self.depths.items) |e| {
                const cmdbuf = &self.cmdbufs.items[e.id];
                defer cmdbuf.clearRetainingCapacity();

                try TermStyledGraphemeIterator.Style.write_to(.reset, self.diffterm.writer());
                try self.diffterm.writer().writeAll(cmdbuf.items);
            }
        }

        {
            try self.term.tty.writeAll(codes.sync_set);

            defer self.diffterm.cmdbuf.clearRetainingCapacity();
            const cmdbuf = try self.diffterm.render(&self.unicode_width_table);
            try self.term.tty.writeAll(cmdbuf);

            try self.term.tty.writeAll(codes.sync_reset);
        }

        self.cmdbuf_id = 0;
        self.depths.clearRetainingCapacity();
    }

    pub fn clear_region(self: *@This(), id: u32, region: Region) !void {
        const out = self.term.screen.clamp(region);
        const range_y = out.range_y();
        for (@intCast(range_y.begin)..@intCast(range_y.end)) |y| {
            try self.cursor_move(id, .{ .y = cast(u16, y), .x = out.origin.x });
            try self.writer(id).writeByteNTimes(' ', @intCast(out.size.x));
        }
    }

    pub fn draw_at(self: *@This(), id: u32, pos: Vec2, token: []const u8) !void {
        if (self.term.screen.contains_vec(pos)) {
            try self.cursor_move(id, pos);
            try self.writer(id).writeAll(token);
        }
    }

    pub fn draw_border(self: *@This(), id: u32, region: Region, borders: anytype) !void {
        const out = self.term.screen.clamp(region);
        const end = region.end();
        const range_y = out.range_y();

        if (out.size.x == 0 or out.size.y == 0) {
            return;
        } else if (std.meta.eql(out.size, .splat(1))) {
            return;
        } else if (out.size.x == 1) {
            for (@intCast(range_y.begin)..@intCast(range_y.end)) |y| {
                try self.draw_at(id, .{ .y = @intCast(y), .x = out.origin.x }, borders.edges.vertical);
            }
            return;
        } else if (out.size.y == 1) {
            try self.cursor_move(id, out.origin);
            try self.writer(id).writeBytesNTimes(borders.edges.horizontal, @intCast(out.size.x));
            return;
        }

        if (self.term.screen.contains_y(region.origin.y)) {
            try self.cursor_move(id, out.origin);
            try self.writer(id).writeBytesNTimes(borders.edges.horizontal, @intCast(out.size.x));
        }
        if (self.term.screen.contains_y(end.y)) {
            try self.cursor_move(id, .{ .x = out.origin.x, .y = end.y });
            try self.writer(id).writeBytesNTimes(borders.edges.horizontal, @intCast(out.size.x));
        }

        for (@intCast(range_y.begin)..@intCast(range_y.end)) |y| {
            try self.draw_at(id, .{ .y = @intCast(y), .x = region.origin.x }, borders.edges.vertical);
            try self.draw_at(id, .{ .y = @intCast(y), .x = end.x }, borders.edges.vertical);
        }

        // write corners last so that it overwrites the edges (this simplifies code)
        try self.draw_at(id, .{ .x = region.origin.x, .y = region.origin.y }, borders.corners.top_left);
        try self.draw_at(id, .{ .x = end.x, .y = region.origin.y }, borders.corners.top_right);
        try self.draw_at(id, .{ .x = region.origin.x, .y = end.y }, borders.corners.bottom_left);
        try self.draw_at(id, .{ .x = end.x, .y = end.y }, borders.corners.bottom_right);
    }

    pub fn draw_split(self: *@This(), id: u32, region: Region, _x: ?i32, _y: ?i32, enable_borders: bool, borders: anytype) !void {
        const border_out = self.term.screen.clamp(region);
        const in_region = region.border_sub(.splat(@intFromBool(enable_borders)));
        const out = self.term.screen.clamp(in_region);
        const end = out.end();
        const range_y = out.range_y();

        if (_y) |y| {
            if (self.term.screen.contains_y(y) and in_region.contains_y(y)) {
                try self.cursor_move(id, .{ .x = out.origin.x, .y = y });
                try self.writer(id).writeBytesNTimes(borders.edges.horizontal, @intCast(out.size.x));
            }
            if (enable_borders and in_region.contains_y(y)) {
                if (in_region.contains_x(out.origin.x)) try self.draw_at(id, .{ .y = y, .x = border_out.origin.x }, borders.cross.nse);
                if (in_region.contains_x(end.x)) try self.draw_at(id, .{ .y = y, .x = border_out.end().x }, borders.cross.nws);
            }
        }
        if (_x) |x| {
            for (@intCast(range_y.begin)..@intCast(range_y.end)) |y| {
                try self.draw_at(id, .{ .x = x, .y = @intCast(y) }, borders.edges.vertical);
            }
            if (enable_borders and in_region.contains_x(x)) {
                if (in_region.contains_y(out.origin.y)) try self.draw_at(id, .{ .x = x, .y = border_out.origin.y }, borders.cross.wse);
                if (in_region.contains_y(end.y)) try self.draw_at(id, .{ .x = x, .y = border_out.end().y }, borders.cross.wne);
            }
        }
        if (_x) |x| if (_y) |y| if (in_region.contains_vec(.{ .x = x, .y = y })) try self.draw_at(id, .{ .x = x, .y = y }, borders.cross.nwse);
    }

    pub fn draw_buf(
        self: *@This(),
        id: u32,
        buf: []const u8,
        region: Region,
        y_offset: i32,
        x_offset: i32,
        y_skip: u32,
    ) !struct {
        x: i32,
        y: i32,
        skipped: i32,
    } {
        const out = self.term.screen.clamp(region.clamp(.{
            .origin = region.origin.add(.{ .y = y_offset }),
            .size = region.size.sub(.{ .y = y_offset }),
        }));
        const end = out.end();
        const range_y = out.range_y();

        var last_y: i32 = y_offset;
        var last_x: i32 = out.origin.x + x_offset;
        var skipped: i32 = 0;

        var line_it = utils_mod.LineIterator{ .buf = buf };
        for (0..y_skip) |_| {
            skipped += 1;
            _ = line_it.next();
        }

        var line = line_it.next();
        for (@intCast(range_y.begin)..@intCast(range_y.end)) |y| {
            _ = line orelse break;
            try self.cursor_move(id, .{ .y = cast(i32, y), .x = last_x });

            var codepoint_it = try TermStyledGraphemeIterator.init(&self.unicode_width_table, line.?);

            while (try codepoint_it.next()) |token| {
                // execute all control chars
                // but don't print beyond the size
                if (token.codepoint) |codepoint| {
                    if (codepoint != .erase_in_line) {
                        try self.writer(id).writeAll(token.grapheme);
                    }
                } else if (last_x <= end.x) {
                    try self.writer(id).writeAll(token.grapheme);
                    last_x += token.visual_width orelse 0;
                }
            }

            line = line_it.next() orelse break;
            last_x = out.origin.x;
            last_y += 1;
        }

        return .{ .x = last_x - out.origin.x, .y = last_y, .skipped = skipped };
    }

    pub fn cursor_move(self: *@This(), id: u32, v: Vec2) !void {
        try self.writer(id).print(codes.cursor.move, .{ v.y + 1, v.x + 1 });
    }
};
