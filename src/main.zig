const std = @import("std");
const builtin = @import("builtin");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const codes = struct {
    const clear = "\x1B[2J";
    const attr_reset = "\x1B[0m";
    const sync_set = "\x1B[?2026h";
    const sync_reset = "\x1B[?2026l";
    const clear_to_line_end = "\x1B[0K";
    const cursor = struct {
        const hide = "\x1B[?25l";
        const show = "\x1B[?25h";
        const save_pos = "\x1B[s";
        const restore_pos = "\x1B[u";
        const move = "\x1B[{};{}H";
    };
    const screen = struct {
        const save = "\x1B[?47h";
        const restore = "\x1B[?47l";
    };
    const alt_buf = struct {
        const enter = "\x1B[?1049h";
        const leave = "\x1B[?1049l";
    };
    const mouse = struct {
        const enable_any_event = "\x1B[?1003h";
        const disable_any_event = "\x1B[?1003l";
        const enable_sgr_mouse_mode = "\x1B[?1006h";
        const disable_sgr_mouse_mode = "\x1B[?1006l";
    };
    const focus = struct {
        const enable = "\x1B[?1004h";
        const disable = "\x1B[?1004l";
    };

    const kitty = struct {
        // https://sw.kovidgoyal.net/kitty/keyboard-protocol/?utm_source=chatgpt.com#progressive-enhancement
        const enable_input_protocol = std.fmt.comptimePrint("\x1B[>{d}u", .{@as(u5, @bitCast(ProgressiveEnhancement{
            .disambiguate_escape_codes = true,
            .report_event_types = true,
            .report_alternate_keys = true,
            .report_all_keys_as_escape_codes = true,
            // .report_associated_text = true,
        }))});
        const disable_input_protocol = "\x1B[<u";

        const ProgressiveEnhancement = packed struct(u5) {
            disambiguate_escape_codes: bool = false,
            report_event_types: bool = false,
            report_alternate_keys: bool = false,
            report_all_keys_as_escape_codes: bool = false,
            report_associated_text: bool = false,
        };
    };
};

const border = struct {
    const edge = struct {
        const vertical = "│";
        const horizontal = "─";
    };
    const rounded = struct {
        const top_left = "╭";
        const top_right = "╮";
        const bottom_left = "╰";
        const bottom_right = "╯";
    };
    const square = struct {
        const top_left = "┌";
        const top_right = "┐";
        const bottom_left = "└";
        const bottom_right = "┘";
    };
    const cross = struct {
        const nse = "├";
        const wse = "┬";
        const nws = "┤";
        const wne = "┴";
        const nwse = "┼";
    };
};

const Vec2 = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn splat(t: u16) @This() {
        return .{ .x = t, .y = t };
    }

    pub fn add(self: *const @This(), other: @This()) @This() {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: *const @This(), other: @This()) @This() {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn max(self: *const @This(), other: @This()) @This() {
        return .{ .x = @max(self.x, other.x), .y = @max(self.y, other.y) };
    }

    pub fn min(self: *const @This(), other: @This()) @This() {
        return .{ .x = @min(self.x, other.x), .y = @min(self.y, other.y) };
    }
};

const TermStyledGraphemeIterator = struct {
    utf8: std.unicode.Utf8Iterator,

    const Token = struct {
        grapheme: []const u8,
        codepoint: ?Codepoint,
    };

    const Codepoint = union(enum) {
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
    const StyleSet = struct {
        weight: enum { normal, faint, bold } = .normal,
        italic: bool = false,
        underline: enum { none, single, double } = .none,
        blink: enum { none, slow, rapid } = .none,
        hide: bool = false,
        strike: bool = false,
        font: ?u3 = null,
        foreground_color: ?Color = null,
        background_color: ?Color = null,

        fn consume(self: *@This(), style: Style) void {
            switch (style) {
                .reset => self.* = .{},
                .bold => self.weight = .bold,
                .normal_intensity => self.weight = .normal,
                .faint => self.weight = .faint,
                .italic => self.italic = true,
                .underline => self.underline = .single,
                .double_underline => self.underline = .double,
                .slow_blink => self.blink = .slow,
                .rapid_blink => self.blink = .rapid,
                .hide => self.hide = true,
                .strike => self.strike = true,
                .font_default => self.font = null,
                .alt_font => |i| self.font = i,
                .default_foreground_color => self.foreground_color = null,
                .default_background_color => self.background_color = null,
                .foreground_color => |col| self.foreground_color = col,
                .background_color => |col| self.background_color = col,
                .invert => std.mem.swap(?Color, &self.foreground_color, &self.background_color),

                .not_supported => {},
            }
        }
    };
    const Style = union(enum) {
        reset,
        bold,
        normal_intensity,
        faint,
        italic,
        underline,
        slow_blink,
        rapid_blink,
        invert,
        hide,
        strike,
        font_default,
        alt_font: u3, // 1 to 9
        double_underline,
        default_foreground_color,
        default_background_color,
        foreground_color: Color,
        background_color: Color,

        not_supported,
    };
    const Color = union(enum) {
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
    };

    fn init(buf: []const u8) !@This() {
        const utf8_view = try std.unicode.Utf8View.init(buf);
        return .{
            .utf8 = utf8_view.iterator(),
        };
    }

    fn next(self: *@This()) !?Token {
        if (try self.next_codepoint()) |t| return t;
        return .{
            .grapheme = self.utf8.nextCodepointSlice() orelse return null,
            .codepoint = null,
        };
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

                    var n = it.param();
                    _ = it.consume(";");
                    var m = it.param();

                    blk: {
                        // any number of style params can come after '[' and before 'm'.
                        // so we have a sort of state machine style style parsing. here.
                        const bak = it;
                        defer it = bak;

                        var style = StyleSet{};
                        while (true) {
                            _ = it.consume(";");
                            const r = it.param();
                            _ = it.consume(";");
                            const g = it.param();
                            _ = it.consume(";");
                            const b = it.param();

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
                                10 => style.consume(.font_default),
                                11...19 => style.consume(.{ .alt_font = cast(u3, n.? - 11) }),

                                39 => style.consume(.default_foreground_color),
                                49 => style.consume(.default_background_color),

                                30...37 => style.consume(.{ .foreground_color = .{ .bit3 = cast(u3, n.? - 30) } }),
                                40...47 => style.consume(.{ .background_color = .{ .bit3 = cast(u3, n.? - 40) } }),

                                38 => style.consume(.{ .foreground_color = Color.from_params(m, r, g, b) orelse return error.BadColorParams }),
                                48 => style.consume(.{ .background_color = Color.from_params(m, r, g, b) orelse return error.BadColorParams }),

                                20...29, 50...107 => style.consume(.not_supported),
                                else => {},
                            }

                            if (it.consume("m")) return Token{ .grapheme = try self.consume(it.i), .codepoint = .{ .set_style = style } };

                            _ = it.consume(";");
                            n = it.param() orelse break :blk;
                            _ = it.consume(";");
                            m = it.param();
                        }
                    }

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

const TermInputIterator = struct {
    input: utils_mod.Deque(u8),

    const Input = union(enum) {
        key: struct { key: u16, mod: Modifiers = .{}, action: Action = .press },
        functional: struct { key: FunctionalKey, mod: Modifiers = .{}, action: Action = .press },
        mouse: struct { pos: Vec2, key: MouseKey, mod: Modifiers = .{}, action: Action = .press },
        focus: enum { in, out },
        unsupported: u8,
    };
    const Modifiers = packed struct(u8) {
        shift: bool = false,
        alt: bool = false,
        ctrl: bool = false,
        super: bool = false,
        hyper: bool = false,
        meta: bool = false,
        caps_lock: bool = false,
        num_lock: bool = false,

        fn eq(self: @This(), other: @This()) bool {
            return std.meta.eql(self, other);
        }
    };
    const Action = enum(u2) {
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
    const FunctionalKey = enum(u16) {
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
    const MouseKey = enum(u8) {
        left = 0,
        middle = 1,
        right = 2,
        move = 35,
        scroll_up = 64,
        scroll_down = 65,
        scroll_left = 66,
        scroll_right = 67,
    };

    fn add(self: *@This(), char: u8) !void {
        try self.input.push_back(char);
    }

    // https://sw.kovidgoyal.net/kitty/keyboard-protocol/
    fn next(self: *@This()) !?Input {
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

                                return Input{ .mouse = .{ .pos = .{ .x = cast(i32, x), .y = cast(i32, y) }, .key = button, .mod = mod, .action = action } };
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
                            => return Input{ .key = .{ .key = cast(u16, shifted_keycode orelse unicode_keycode), .mod = mod, .action = action } },
                            else => return Input{ .functional = .{ .key = try std.meta.intToEnum(FunctionalKey, unicode_keycode), .mod = mod, .action = action } },
                        },
                        '~' => switch (unicode_keycode) {
                            13 => return Input{ .functional = .{ .key = .f3, .mod = mod, .action = action } },
                            else => return Input{ .functional = .{ .key = try std.meta.intToEnum(FunctionalKey, unicode_keycode), .mod = mod, .action = action } },
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
                        0x1B => return Input{ .functional = .{ .key = .escape } },
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
                    'a'...'z',
                    'A'...'Z',
                    '0'...'9',
                    ' ',
                    33...47, // !"#$%&'()*+,-./
                    58...64, // :;<=>?@
                    91...96, // [\]^_
                    123...126, // {|}~
                    => return Input{ .key = .{ .key = cast(u16, c) } },
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

const Term = struct {
    tty: std.fs.File,

    size: Vec2 = .{},
    cooked_termios: ?std.posix.termios = null,
    raw: ?std.posix.termios = null,

    cmdbuf: std.ArrayList(u8),

    fn init(alloc: std.mem.Allocator) !@This() {
        const tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        var self = @This(){
            .tty = tty,
            .cmdbuf = .init(alloc),
        };

        try self.update_size();

        return self;
    }

    fn deinit(self: *@This()) void {
        self.cmdbuf.deinit();
        self.tty.close();
    }

    fn uncook(self: *@This(), handler: anytype) !void {
        try self.enter_raw_mode();
        try self.tty.writeAll("" ++
            codes.cursor.hide ++
            codes.alt_buf.enter ++
            codes.kitty.enable_input_protocol ++
            codes.mouse.enable_any_event ++
            codes.mouse.enable_sgr_mouse_mode ++
            codes.focus.enable ++
            codes.clear ++
            "");
        self.register_signal_handlers(handler);
    }

    fn cook_restore(self: *@This()) !void {
        try self.tty.writeAll("" ++
            codes.mouse.disable_any_event ++
            codes.mouse.disable_sgr_mouse_mode ++
            codes.kitty.disable_input_protocol ++
            codes.focus.disable ++
            codes.clear ++
            codes.alt_buf.leave ++
            codes.cursor.show ++
            codes.attr_reset ++
            "");
        try std.posix.tcsetattr(self.tty.handle, .FLUSH, self.cooked_termios.?);
        self.raw = null;
        self.cooked_termios = null;
        self.unregister_signal_handlers();
    }

    fn writer(self: *@This()) std.ArrayList(u8).Writer {
        return self.cmdbuf.writer();
    }

    fn flush_writes(self: *@This()) !void {
        // cmdbuf's last command is sync reset
        try self.writer().writeAll(codes.sync_reset);

        // flush and clear cmdbuf
        try self.tty.writeAll(self.cmdbuf.items);
        self.cmdbuf.clearRetainingCapacity();

        // cmdbuf's first command is sync start
        try self.writer().writeAll(codes.sync_set ++ codes.clear);
    }

    fn clear_region(self: *@This(), min: Vec2, max: Vec2) !void {
        for (@intCast(self.size.min(min).max(.{}).y)..@intCast(self.size.min(max.add(.splat(1))).y)) |y| {
            try self.cursor_move(.{ .y = cast(u16, y), .x = min.x });
            try self.writer().writeByteNTimes(' ', @intCast(max.min(self.size).sub(min).max(.{}).x));
        }
    }

    fn draw_at(self: *@This(), pos: Vec2, token: []const u8) !void {
        if (self.size.x > pos.x and self.size.y > pos.y) {
            try self.cursor_move(pos);
            try self.writer().writeAll(token);
        }
    }

    fn draw_border(self: *@This(), min: Vec2, max: Vec2, corners: anytype) !void {
        const x_lim = max.min(self.size).sub(min).max(.{}).x;
        try self.cursor_move(min);
        try self.writer().writeBytesNTimes(border.edge.horizontal, @intCast(x_lim));
        if (max.y < self.size.y) {
            try self.cursor_move(.{ .x = min.x, .y = max.y });
            try self.writer().writeBytesNTimes(border.edge.horizontal, @intCast(x_lim));
        }

        for (@intCast(min.min(self.size).y)..@intCast(self.size.min(max.add(.splat(1))).y)) |y| {
            try self.draw_at(.{ .y = @intCast(y), .x = min.x }, border.edge.vertical);
            try self.draw_at(.{ .y = @intCast(y), .x = max.x }, border.edge.vertical);
        }

        // write corners last so that it overwrites the edges (this simplifies code)
        try self.draw_at(.{ .x = min.x, .y = min.y }, corners.top_left);
        try self.draw_at(.{ .x = max.x, .y = min.y }, corners.top_right);
        try self.draw_at(.{ .x = min.x, .y = max.y }, corners.bottom_left);
        try self.draw_at(.{ .x = max.x, .y = max.y }, corners.bottom_right);
    }

    fn draw_split(self: *@This(), min: Vec2, max: Vec2, x: ?i32, y: ?i32, borders: bool) !void {
        if (y) |_y| {
            const x_lim = max.min(self.size).sub(min).max(.{}).x;
            try self.cursor_move(.{ .x = min.x, .y = _y });
            try self.writer().writeBytesNTimes(border.edge.horizontal, @intCast(x_lim));
            if (borders) {
                try self.draw_at(.{ .y = _y, .x = min.x }, border.cross.nse);
                try self.draw_at(.{ .y = _y, .x = max.x }, border.cross.nws);
            }
        }
        if (x) |_x| {
            for (@intCast(min.min(self.size).y)..@intCast(self.size.min(max.add(.splat(1))).y)) |_y| {
                try self.draw_at(.{ .x = _x, .y = @intCast(_y) }, border.edge.vertical);
            }
            if (borders) {
                try self.draw_at(.{ .x = _x, .y = min.y }, border.cross.wse);
                try self.draw_at(.{ .x = _x, .y = max.y }, border.cross.wne);
            }
        }
        if (x) |_x| if (y) |_y| try self.draw_at(.{ .x = _x, .y = _y }, border.cross.nwse);
    }

    fn draw_buf(self: *@This(), buf: []const u8, min: Vec2, max: Vec2, y_offset: i32, y_skip: u32) !struct { y: i32, skipped: i32 } {
        var last_y: i32 = y_offset;
        var skipped: i32 = 0;

        var line_it = utils_mod.LineIterator{ .buf = buf };
        for (0..y_skip) |_| {
            skipped += 1;
            _ = line_it.next();
        }

        // these ranges look crazy to handle edge conditions :P
        for (@intCast(self.size.min(.{ .x = min.x, .y = min.y + y_offset }).max(.{}).y)..@intCast(self.size.min((Vec2{ .x = max.x, .y = @max(max.y + 1, min.y + y_offset) })).y)) |y| {
            const line = line_it.next() orelse break;
            try self.cursor_move(.{ .y = cast(i32, y), .x = min.x });

            var codepoint_it = try TermStyledGraphemeIterator.init(line);

            var x: i32 = min.x;
            while (try codepoint_it.next()) |token| {
                // execute all control chars
                // but don't print beyond the size
                if (token.codepoint) |codepoint| {
                    if (codepoint != .erase_in_line) {
                        try self.writer().writeAll(token.grapheme);
                    }
                } else if (x <= max.min(self.size.sub(.splat(1))).x) {
                    try self.writer().writeAll(token.grapheme);
                    x += 1;
                }
            }

            last_y += 1;
        }

        return .{ .y = last_y, .skipped = skipped };
    }

    fn update_size(self: *@This()) !void {
        var win_size = std.mem.zeroes(std.posix.winsize);
        const err = std.os.linux.ioctl(self.tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&win_size));
        if (std.posix.errno(err) != .SUCCESS) {
            return std.posix.unexpectedErrno(@as(std.posix.E, @enumFromInt(err)));
        }
        self.size = .{ .y = win_size.row, .x = win_size.col };
    }

    fn cursor_move(self: *@This(), v: Vec2) !void {
        try self.writer().print(codes.cursor.move, .{ v.y + 1, v.x + 1 });
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

    fn register_signal_handlers(_: *@This(), handler: anytype) void {
        std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
            .handler = .{ .handler = handler.winch },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
    }

    fn unregister_signal_handlers(_: *@This()) void {
        std.posix.sigaction(std.posix.SIG.WINCH, &std.os.linux.Sigaction{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
    }
};

const JujutsuServer = struct {
    alloc: std.mem.Allocator,
    quit: utils_mod.Fuse = .{},
    thread: std.Thread,
    requests: utils_mod.Channel(Request),

    // not owned
    events: utils_mod.Channel(App.Event),

    const Request = union(enum) {
        status,
        diff: Change,
    };

    const Result = union(enum) {
        ok: []u8,
        err: []u8,
    };

    const Response = struct {
        req: Request,
        res: Result,
    };

    fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(App.Event)) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        self.* = .{
            .events = events,
            .requests = try .init(alloc),
            .alloc = alloc,
            .thread = undefined,
        };

        self.thread = try std.Thread.spawn(.{}, @This()._start, .{self});
        errdefer {
            _ = self.quit.fuse();
            self.thread.join();
        }

        return self;
    }

    fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.requests.deinit();
        defer self.thread.join();
        _ = self.quit.fuse();
        _ = self.requests.close();
    }

    fn _start(self: *@This()) void {
        self.start() catch |e| utils_mod.dump_error(e);
    }

    fn start(self: *@This()) !void {
        while (self.requests.wait_recv()) |req| {
            if (self.quit.check()) return;
            switch (req) {
                .status => {
                    const res = jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                    }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = res } } });
                },
                .diff => |change| {
                    const stat = jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "show",
                        "--stat",
                        "-r",
                        change.hash[0..],
                    }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    defer self.alloc.free(stat);
                    const diff = jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "diff",
                        "--tool",
                        "delta",
                        "-r",
                        change.hash[0..],
                    }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    defer self.alloc.free(diff);

                    var output = std.ArrayList(u8).init(self.alloc);
                    errdefer output.deinit();
                    try output.appendSlice(stat);
                    try output.appendSlice(diff);

                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = try output.toOwnedSlice() } } });
                },
            }
        }
    }

    fn jjcall(args: []const []const u8, alloc: std.mem.Allocator) ![]u8 {
        var child = std.process.Child.init(args, alloc);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdin = child.stdin orelse return error.NoStdin;
        child.stdin = null;
        const stdout = child.stdout orelse return error.NoStdout;
        child.stdout = null;
        const stderr = child.stderr orelse return error.NoStderr;
        child.stderr = null;
        defer stdout.close();
        defer stderr.close();
        stdin.close();

        // similar to child.collectOutput
        const max_output_bytes = 1000 * 1000;
        var poller = std.io.poll(alloc, enum { stdout, stderr }, .{
            .stdout = stdout,
            .stderr = stderr,
        });
        defer poller.deinit();

        while (try poller.poll()) {
            if (poller.fifo(.stdout).count > max_output_bytes)
                return error.StdoutStreamTooLong;
            if (poller.fifo(.stderr).count > max_output_bytes)
                return error.StderrStreamTooLong;
        }

        const err = try child.wait();
        blk: {
            var err_buf = std.ArrayList(u8).init(alloc);
            defer err_buf.deinit();

            switch (err) {
                .Exited => |e| {
                    if (e != 0) {
                        _ = try err_buf.writer().print("exited with code: {}\n", .{e});
                    } else {
                        err_buf.deinit();
                        break :blk;
                    }
                },
                // .Signal => |code| {},
                // .Stopped => |code| {},
                // .Unknown => |code| {},
                else => |e| {
                    try err_buf.writer().print("exited with code: {}\n", .{e});
                },
            }

            const fifo = poller.fifo(.stderr);
            try err_buf.appendSlice(fifo.buf[fifo.head..][0..fifo.count]);

            std.debug.print("{s}\n", .{err_buf.items});
            return error.SomeErrorIdk;
        }

        const fifo = poller.fifo(.stdout);
        var out = std.ArrayList(u8).init(alloc);
        try out.appendSlice(fifo.buf[fifo.head..][0..fifo.count]);
        return try out.toOwnedSlice();
    }
};

const ChangeIterator = struct {
    state: utils_mod.LineIterator,

    temp: std.heap.ArenaAllocator,
    scratch: std.ArrayListUnmanaged(u8) = .{},

    fn init(alloc: std.mem.Allocator, buf: []const u8) @This() {
        return .{ .temp = .init(alloc), .state = .init(buf) };
    }

    fn deinit(self: *@This()) void {
        self.temp.deinit();
    }

    fn reset(self: *@This(), buf: []const u8) void {
        self.scratch.clearRetainingCapacity();
        self.state = .init(buf);
    }

    fn next(self: *@This()) !?ChangeEntry {
        const start = self.state.index;
        while (self.state.next()) |line| {
            self.scratch.clearRetainingCapacity();
            var tokens = try TermStyledGraphemeIterator.init(line);

            while (try tokens.next()) |token| {
                if (token.codepoint != null) {
                    continue;
                }

                try self.scratch.appendSlice(self.temp.allocator(), token.grapheme);
            }

            const hash = blk: {
                var chunks = std.mem.splitBackwardsScalar(u8, self.scratch.items, ' ');
                while (chunks.next()) |chunk| {
                    if (chunk.len == 8) {
                        break :blk chunk;
                    }
                }
                return error.ErrorParsingChangeHash;
            };
            const id = blk: {
                var chunks = std.mem.splitScalar(u8, self.scratch.items, ' ');
                while (chunks.next()) |chunk| {
                    if (chunk.len == 8) {
                        break :blk chunk;
                    }
                }
                return error.ErrorParsingChangeId;
            };

            var change = std.mem.zeroes(Change);
            @memcpy(change.id[0..], id);
            @memcpy(change.hash[0..], hash);

            // description line
            _ = self.state.next();

            return .{ .change = change, .buf = self.state.buf[start..self.state.index] };
        }

        return null;
    }

    const ChangeEntry = struct {
        buf: []const u8,
        change: Change,
    };
};

const Change = struct {
    id: [8]u8 = [1]u8{'z'} ** 8,
    hash: [8]u8 = [1]u8{0} ** 8,

    fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.hash, 0);
    }
};

const Surface = struct {
    border: bool = false,
    _split_x: ?i32 = null,
    _split_y: ?i32 = null,
    y: i32 = 0,
    y_scroll: i32 = 0,
    min: Vec2,
    max: Vec2,
    term: *Term,

    const Self = @This();

    fn clear(self: *@This()) !void {
        try self.term.clear_region(self.min, self.max);
    }

    fn draw_border(self: *@This(), borders: anytype) !void {
        if (self.border) {
            try self.term.draw_border(self.min, self.max, borders);
        }
        try self.term.draw_split(self.min, self.max, self._split_x, self._split_y, self.border);
    }

    fn draw_buf(self: *@This(), buf: []const u8) !void {
        self.y = @max(0, self.y);
        self.y_scroll = @max(0, self.y_scroll);
        const res = try self.term.draw_buf(
            buf,
            self.min.add(.splat(@intCast(@intFromBool(self.border)))),
            self.max.sub(.splat(@intCast(@intFromBool(self.border)))),
            self.y,
            cast(u32, self.y_scroll),
        );
        self.y = res.y;
        self.y_scroll -= res.skipped;
    }

    fn split_x(self: *@This(), x: i32, _draw_border: bool) struct { left: Self, right: Self } {
        self._split_x = x;
        return .{
            .left = @This(){
                .term = self.term,
                .min = self.min.add(.splat(@intCast(@intFromBool(self.border)))),
                .max = (Vec2{
                    .x = x - @as(i32, if (_draw_border) 1 else 0),
                    .y = self.max.y - @intFromBool(self.border),
                }),
            },
            .right = @This(){
                .term = self.term,
                .min = (Vec2{
                    .x = x + @as(i32, if (_draw_border) 1 else 0),
                    .y = self.min.y + @intFromBool(self.border),
                }),
                .max = self.max.sub(.splat(@intCast(@intFromBool(self.border)))),
            },
        };
    }

    fn split_y(self: *@This(), y: i32, _draw_border: bool) struct { top: Self, bottom: Self } {
        self._split_y = y;
        return .{
            .top = @This(){
                .term = self.term,
                .min = self.min.add(.splat(@intCast(@intFromBool(self.border)))),
                .max = (Vec2{
                    .y = y - @as(i32, if (_draw_border) 1 else 0),
                    .x = self.max.x - @intFromBool(self.border),
                }),
            },
            .bottom = @This(){
                .term = self.term,
                .min = (Vec2{
                    .y = y + @as(i32, if (_draw_border) 1 else 0),
                    .x = self.min.x + @intFromBool(self.border),
                }),
                .max = self.max.sub(.splat(@intCast(@intFromBool(self.border)))),
            },
        };
    }
};

const App = struct {
    term: Term,

    quit: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    input_iterator: TermInputIterator,
    events: utils_mod.Channel(Event),

    jj: *JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    x_split: f32 = 0.55,
    y: i32 = 0,
    status: []const u8,
    changes: ChangeIterator,
    diffcache: DiffCache,
    focused_change: Change = .{},

    const Event = union(enum) {
        sigwinch,
        rerender,
        quit,
        input: TermInputIterator.Input,
        jj: JujutsuServer.Response,
        err: anyerror,
    };

    const CachedDiff = struct {
        y: i32 = 0,
        diff: ?[]const u8 = null,
    };
    const DiffCache = std.HashMap([8]u8, CachedDiff, struct {
        pub fn hash(self: @This(), s: [8]u8) u64 {
            _ = self;
            return std.hash_map.StringContext.hash(.{}, s[0..]);
        }
        pub fn eql(self: @This(), a: [8]u8, b: [8]u8) bool {
            _ = self;
            return std.hash_map.StringContext.eql(.{}, a[0..], b[0..]);
        }
    }, std.hash_map.default_max_load_percentage);

    var app: *@This() = undefined;

    fn init(alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();

        var term = try Term.init(alloc);
        errdefer term.deinit();

        try term.uncook(@This());
        errdefer term.cook_restore() catch |e| utils_mod.dump_error(e);

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        const jj = try JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        try jj.requests.send(.status);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .term = term,
            .input_iterator = .{ .input = try .init(alloc) },
            .events = events,
            .jj = jj,
            .status = &.{},
            .changes = .init(alloc, &[_]u8{}),
            .diffcache = .init(alloc),
            .input_thread = undefined,
        };

        const input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        errdefer {
            _ = self.quit.fuse();
            input_thread.join();
        }

        try self.diffcache.put(self.focused_change.hash, .{ .diff = &.{} });

        self.input_thread = input_thread;
        app = self;
        return self;
    }

    fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.changes.deinit();
        defer {
            var it = self.diffcache.iterator();
            while (it.next()) |e| if (e.value_ptr.diff) |diff| {
                self.alloc.free(diff);
            };
            self.diffcache.deinit();
        }
        defer self.arena.deinit();
        defer self.term.deinit();
        defer self.term.cook_restore() catch |e| utils_mod.dump_error(e);
        defer self.input_iterator.input.deinit();
        defer {
            while (self.events.try_recv()) |e| switch (e) {
                .jj => |res| switch (res.res) {
                    .ok, .err => |buf| self.alloc.free(buf),
                },
                else => {},
            };
            self.events.deinit();
        }
        defer self.jj.deinit();
        defer self.input_thread.join();
        _ = self.quit.fuse();
    }

    fn winch(_: c_int) callconv(.C) void {
        app.events.send(.sigwinch) catch |e| utils_mod.dump_error(e);
    }

    fn _input_loop(self: *@This()) void {
        self.input_loop() catch |e| utils_mod.dump_error(e);
    }

    fn input_loop(self: *@This()) !void {
        while (true) {
            var fds = [1]std.posix.pollfd{.{ .fd = self.term.tty.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            if (try std.posix.poll(&fds, 20) > 0) {
                var buf = std.mem.zeroes([32]u8);
                const n = try self.term.tty.read(&buf);
                for (buf[0..n]) |c| try self.input_iterator.input.push_back(c);

                while (self.input_iterator.next() catch |e| switch (e) {
                    error.ExpectedByte => null,
                    else => {
                        try self.events.send(.{ .err = e });
                        return;
                    },
                }) |input| {
                    try self.events.send(.{ .input = input });
                }
            }

            if (self.quit.check()) {
                break;
            }
        }
    }

    fn event_loop(self: *@This()) !void {
        try self.events.send(.rerender);

        while (self.events.wait_recv()) |event| switch (event) {
            .quit => return,
            .err => |err| return err,
            .rerender => try self.render(),
            .sigwinch => try self.events.send(.rerender),
            .input => |input| {
                switch (input) {
                    .key => |key| {
                        std.log.debug("got input event: {any}", .{key});

                        if (key.key == 'q') {
                            try self.events.send(.quit);
                        }
                        if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{})) {
                            self.y += 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{})) {
                            self.y -= 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            if (self.diffcache.getPtr(self.focused_change.hash)) |diff| {
                                diff.y += 10;
                            }
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            if (self.diffcache.getPtr(self.focused_change.hash)) |diff| {
                                diff.y -= 10;
                            }
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'h' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.x_split -= 0.05;
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'l' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.x_split += 0.05;
                            try self.events.send(.rerender);
                        }

                        if (comptime builtin.mode == .Debug) {
                            if (key.action.just_pressed() and key.mod.eq(.{ .ctrl = true })) switch (key.key) {
                                '1' => try self.term.tty.writeAll(codes.kitty.disable_input_protocol),
                                '2' => try self.term.tty.writeAll(codes.focus.disable),
                                '3' => try self.term.tty.writeAll(codes.mouse.disable_any_event ++ codes.mouse.disable_sgr_mouse_mode),
                                else => {},
                            };
                            if (key.action.just_pressed() and key.mod.eq(.{})) switch (key.key) {
                                '1' => try self.term.tty.writeAll(codes.kitty.enable_input_protocol),
                                '2' => try self.term.tty.writeAll(codes.focus.enable),
                                '3' => try self.term.tty.writeAll(codes.mouse.enable_any_event ++ codes.mouse.enable_sgr_mouse_mode),
                                else => {},
                            };
                        }
                    },
                    .functional => |key| {
                        _ = key;
                        // std.log.debug("got input event: {any}", .{key});
                    },
                    .mouse => |key| {
                        // std.log.debug("got mouse input event: {any}", .{key});

                        if (key.key == .scroll_down and key.action.pressed() and key.mod.eq(.{})) {
                            self.y += 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == .scroll_up and key.action.pressed() and key.mod.eq(.{})) {
                            self.y -= 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                    },
                    .focus => |e| {
                        // _ = e;
                        std.log.debug("got focus event: {any}", .{e});
                    },
                    .unsupported => {},
                }
            },
            .jj => |res| switch (res.req) {
                .status => {
                    self.alloc.free(self.status);
                    switch (res.res) {
                        .ok => |buf| {
                            self.status = buf;
                            self.changes.reset(buf);

                            try self.request_jj();
                        },
                        .err => |buf| {
                            self.status = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
                .diff => |req| {
                    switch (res.res) {
                        .ok, .err => |buf| {
                            self.diffcache.getPtr(req.hash).?.diff = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
            },
        };
    }

    fn save_diff(self: *@This(), change: *const Change, diff: []const u8) !void {
        try self.diffcache.put(try self.alloc.dupe(u8, change.hash[0..]), diff);
    }

    fn maybe_request_diff(self: *@This(), change: *const Change) !void {
        if (self.diffcache.get(change.hash) == null) {
            try self.jj.requests.send(.{ .diff = change });
        }
    }

    fn request_jj(self: *@This()) !void {
        self.changes.reset(self.status);
        var i: i32 = 0;
        while (try self.changes.next()) |change| {
            // const n: i32 = 3;
            const n: i32 = 0;
            if (self.y == i) {
                self.focused_change = change.change;
            } else if (@abs(self.y - i) < n) {
                if (self.diffcache.get(change.change.hash) == null) {
                    try self.diffcache.put(change.change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change.change });
                }
            }
            i += 1;
        }

        if (self.diffcache.get(self.focused_change.hash)) |_| {
            try self.events.send(.rerender);
        } else {
            try self.diffcache.put(self.focused_change.hash, .{});
            try self.jj.requests.send(.{ .diff = self.focused_change });
        }
    }

    fn render(self: *@This()) !void {
        self.y = @max(0, self.y);
        self.x_split = @min(@max(0.0, self.x_split), 1.0);

        try self.term.update_size();
        {
            const min = Vec2{};
            const max = min.add(self.term.size.sub(.splat(1)));
            const split_x: i32 = cast(i32, cast(f32, max.x) * self.x_split);
            var entire = Surface{ .term = &self.term, .border = true, .min = min, .max = max };
            try entire.clear();

            var hori = entire.split_x(split_x, true);
            var skip = self.y;
            self.changes.reset(self.status);
            while (try self.changes.next()) |change| {
                if (skip > 0) {
                    skip -= 1;
                    continue;
                }
                try hori.left.draw_buf(change.buf);
            }

            if (self.diffcache.getPtr(self.focused_change.hash)) |cdiff| if (cdiff.diff) |diff| {
                cdiff.y = @max(0, cdiff.y);
                hori.right.y_scroll = cdiff.y;
                try hori.right.draw_buf(diff);
            } else {
                try hori.right.draw_buf(" loading ... ");
            };

            try entire.draw_border(border.rounded);
        }
        // {
        //     const min = Vec2{};
        //     const max = min.add(self.term.size.sub(.splat(1)));
        //     const split_x: i32 = cast(i32, cast(f32, max.x) * self.x_split);
        //     try self.term.clear_region(min, max);
        //     try self.term.draw_border(min, max, border.rounded);
        //     try self.term.draw_split(min, max, split_x, null, true);

        //     var skip = self.y;
        //     var y_off: i32 = 0;
        //     self.changes.reset(self.status);
        //     while (try self.changes.next()) |change| {
        //         if (skip > 0) {
        //             skip -= 1;
        //             continue;
        //         }
        //         y_off = try self.term.draw_buf(
        //             change.buf,
        //             min.add(.splat(1)),
        //             (Vec2{ .x = split_x, .y = max.y }).sub(.splat(1)),
        //             y_off,
        //             0,
        //         );
        //     }

        //     if (self.diffcache.getPtr(self.focused_change.hash)) |cdiff| if (cdiff.diff) |diff| {
        //         cdiff.y = @max(0, cdiff.y);
        //         _ = try self.term.draw_buf(diff, (Vec2{ .x = split_x, .y = min.y }).add(.splat(1)), max.sub(.splat(1)), 0, cast(u32, cdiff.y));
        //     } else {
        //         _ = try self.term.draw_buf(" loading ... ", (Vec2{ .x = split_x, .y = min.y }).add(.splat(1)), max.sub(.splat(1)), 0, 0);
        //     };
        // }
        try self.term.flush_writes();
    }
};

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = utils_mod.Log.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    try utils_mod.Log.logger.init(alloc);
    defer utils_mod.Log.logger.deinit();

    defer _ = gpa.deinit();

    const app = try App.init(alloc);
    defer app.deinit();

    try app.event_loop();
}

// pub fn main1() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     while (true) {
//         var buf = std.mem.zeroes([1]u8);

//         if (buf[0] == 'q') {
//             return;
//         } else if (buf[0] == '\x1B') {
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 1;
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 0;
//             try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

//             var esc_buf: [8]u8 = undefined;
//             const esc_read = try term.tty.read(&esc_buf);

//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 0;
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 1;
//             try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

//             if (std.mem.eql(u8, esc_buf[0..esc_read], "[A")) {
//                 term.i -|= 1;
//             } else if (std.mem.eql(u8, esc_buf[0..esc_read], "[B")) {
//                 term.i = @min(term.i + 1, 3);
//             }
//         }
//     }
// }
