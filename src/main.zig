const std = @import("std");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const ansi = struct {
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

    fn next_codepoint(self: *@This()) !?Token {
        const buf = self.utf8.bytes[self.utf8.i..];
        var it = ByteIterator{ .buf = buf };
        switch (it.next() orelse return null) {
            // https://en.wikipedia.org/wiki/ANSI_escape_code#C0_control_codes
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

const Term = struct {
    tty: std.fs.File,

    size: Vec2 = .{},
    cooked_termios: ?std.posix.termios = null,
    raw: ?std.posix.termios = null,

    alloc: std.mem.Allocator,
    cmdbuf: std.ArrayList(u8),

    fn init(alloc: std.mem.Allocator) !@This() {
        const tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        var self = @This(){
            .tty = tty,
            .alloc = alloc,
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
        try self.tty.writeAll(ansi.cursor.hide ++ ansi.alt_buf.enter ++ ansi.clear);
        self.register_signal_handlers(handler);
    }

    fn cook_restore(self: *@This()) !void {
        try self.tty.writeAll(ansi.clear ++ ansi.alt_buf.leave ++ ansi.cursor.show ++ ansi.attr_reset);
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
        try self.writer().writeAll(ansi.sync_reset);

        // flush and clear cmdbuf
        try self.tty.writeAll(self.cmdbuf.items);
        self.cmdbuf.clearRetainingCapacity();

        // cmdbuf's first command is sync start
        try self.writer().writeAll(ansi.sync_set ++ ansi.clear);
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

    fn draw_split(self: *@This(), min: Vec2, max: Vec2, x: ?i32, y: ?i32) !void {
        if (y) |_y| {
            const x_lim = max.min(self.size).sub(min).max(.{}).x;
            try self.cursor_move(.{ .x = min.x, .y = _y });
            try self.writer().writeBytesNTimes(border.edge.horizontal, @intCast(x_lim));
            try self.draw_at(.{ .y = _y, .x = min.x }, border.cross.nse);
            try self.draw_at(.{ .y = _y, .x = max.x }, border.cross.nws);
        }
        if (x) |_x| {
            for (@intCast(min.min(self.size).y)..@intCast(self.size.min(max.add(.splat(1))).y)) |_y| {
                try self.draw_at(.{ .x = _x, .y = @intCast(_y) }, border.edge.vertical);
            }
            try self.draw_at(.{ .x = _x, .y = min.y }, border.cross.wse);
            try self.draw_at(.{ .x = _x, .y = max.y }, border.cross.wne);
        }
        if (x) |_x| if (y) |_y| try self.draw_at(.{ .x = _x, .y = _y }, border.cross.nwse);
    }

    fn draw_buf(self: *@This(), buf: []const u8, min: Vec2, max: Vec2, y_offset: i32, y_skip: u32) !i32 {
        var last_y: i32 = y_offset;

        var line_it = utils_mod.LineIterator{ .buf = buf };
        for (0..y_skip) |_| _ = line_it.next();

        // these ranges look crazy to handle edge conditions :P
        for (@intCast(self.size.min(.{ .x = min.x, .y = min.y + y_offset }).max(.{}).y)..@intCast(self.size.min((Vec2{ .x = max.x, .y = @max(max.y, min.y + y_offset) }).add(.splat(1))).y)) |y| {
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

        return last_y;
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
        try self.writer().print(ansi.cursor.move, .{ v.y + 1, v.x + 1 });
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
    responses: utils_mod.Channel(Response),

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

    fn init(alloc: std.mem.Allocator) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        self.* = .{
            .responses = try .init(alloc),
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
        defer self.responses.deinit();
        defer self.requests.deinit();
        defer self.thread.join();
        _ = self.quit.fuse();
    }

    fn _start(self: *@This()) void {
        self.start() catch |e| utils_mod.dump_error(e);
    }

    fn start(self: *@This()) !void {
        while (true) {
            while (self.requests.try_recv()) |req| switch (req) {
                .status => {
                    const res = utils_mod.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                    }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.responses.send(.{ .req = req, .res = .{ .ok = res } });
                },
                .diff => |change| {
                    const stat = utils_mod.jjcall(&[_][]const u8{
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
                    const diff = utils_mod.jjcall(&[_][]const u8{
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

                    try self.responses.send(.{ .req = req, .res = .{ .ok = try output.toOwnedSlice() } });
                },
            };

            if (self.quit.check()) break;

            std.Thread.sleep(std.time.ns_per_ms * 20);
        }
    }
};

const ChangeIterator = struct {
    line_index: u32 = 0,
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
        self.line_index = 0;
    }

    fn next(self: *@This()) !?Change {
        while (self.state.next()) |line| {
            self.line_index += 1;
            if (self.line_index % 2 == 0) continue;

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
            return change;
        }

        return null;
    }
};

const Change = struct {
    id: [8]u8 = [1]u8{'z'} ** 8,
    hash: [8]u8 = [1]u8{0} ** 8,

    fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.hash, 0);
    }
};

const App = struct {
    term: Term,

    quit: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    events: utils_mod.Channel(Event),

    jj: *JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    y: i32 = 0,
    status: []const u8,
    diff: []const u8,
    changes: ChangeIterator,
    diffcache: DiffCache,
    focused_change: Change = .{},

    const Event = union(enum) {
        sigwinch,
        rerender,
        quit,
        input: u8,
    };

    const CachedDiff = struct {
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

        const jj = try JujutsuServer.init(alloc);
        errdefer jj.deinit();

        try jj.requests.send(.status);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .term = term,
            .events = events,
            .jj = jj,
            .status = &.{},
            .diff = &.{},
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
        defer self.events.deinit();
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
                var buf = std.mem.zeroes([1]u8);
                _ = try self.term.tty.read(&buf);
                try self.events.send(.{ .input = buf[0] });
            }

            if (self.quit.check()) {
                break;
            }
        }
    }

    fn event_loop(self: *@This()) !void {
        try self.events.send(.rerender);

        while (true) {
            while (self.events.try_recv()) |event| switch (event) {
                .rerender => {
                    try self.render();
                },
                .sigwinch => {
                    try self.events.send(.rerender);
                },
                .input => |char| {
                    if (char == 'q') {
                        try self.events.send(.quit);
                    }
                    if (char == 'j') {
                        self.y += 2;
                        try self.events.send(.rerender);

                        try self.request_jj();
                    }
                    if (char == 'k') {
                        self.y -= 2;
                        self.y = @max(0, self.y);
                        try self.events.send(.rerender);

                        try self.request_jj();
                    }
                },
                .quit => {
                    return;
                },
            };

            while (self.jj.responses.try_recv()) |res| switch (res.req) {
                .status => {
                    self.alloc.free(self.status);
                    switch (res.res) {
                        .ok => |buf| {
                            self.status = buf;
                            self.changes.reset(buf);
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
            };

            std.Thread.sleep(std.time.ns_per_ms * 20);
        }
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
            const n: i32 = 3;
            if (self.y == i * 2) {
                self.focused_change = change;
            } else if (@abs(self.y - i * 2) < 2 * n) {
                if (self.diffcache.get(change.hash) == null) {
                    try self.diffcache.put(change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change });
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
        try self.term.update_size();
        {
            if (self.diffcache.get(self.focused_change.hash)) |cdiff| if (cdiff.diff) |diff| {
                self.diff = diff;
            };

            try self.term.clear_region(.{}, self.term.size.sub(.splat(1)));
            try self.term.draw_border(.{}, self.term.size.sub(.splat(1)), border.rounded);
            _ = try self.term.draw_buf(self.status, .splat(1), self.term.size.sub(.splat(2)), 0, cast(u32, self.y));

            const min = Vec2{ .x = 30, .y = 3 };
            const max = min.add(.{ .x = 80, .y = 40 });
            const split_x: i32 = min.x + 40;
            try self.term.clear_region(min, max);
            try self.term.draw_border(min, max, border.rounded);
            try self.term.draw_split(min, max, split_x, null);
            const y_off = try self.term.draw_buf("hello man", min.add(.splat(1)), (Vec2{ .x = split_x, .y = max.y }).sub(.splat(1)), 0, 0);
            _ = try self.term.draw_buf(self.diff, min.add(.splat(1)), (Vec2{ .x = split_x, .y = max.y }).sub(.splat(1)), y_off, 0);
            _ = try self.term.draw_buf(self.status, (Vec2{ .x = split_x, .y = min.y }).add(.splat(1)), max.sub(.splat(1)), 0, 0);
        }
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
