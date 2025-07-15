const std = @import("std");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const ansi = struct {
    const clear = "\x1B[2J";
    const attr_reset = "\x1B[0m";
    const sync_set = "\x1B[?2026h";
    const sync_reset = "\x1B[?2026l";
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
    const rounded = struct {
        const horizontal = "─";
        const vertical = "│";
        const top_left = "╭";
        const top_right = "╮";
        const bottom_left = "╰";
        const bottom_right = "╯";
    };
    const square = struct {
        const horizontal = "─";
        const vertical = "│";
        const top_left = "┌";
        const top_right = "┐";
        const bottom_left = "└";
        const bottom_right = "┘";
    };
};

const Vec2 = struct {
    x: u16 = 0,
    y: u16 = 0,

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
        is_ansi_codepoint: bool,
    };

    fn init(buf: []const u8) !@This() {
        const utf8_view = try std.unicode.Utf8View.init(buf);
        return .{
            .utf8 = utf8_view.iterator(),
        };
    }

    fn next(self: *@This()) !?Token {
        const buf = self.utf8.bytes;
        const start = self.utf8.i;
        const c = self.utf8.nextCodepointSlice() orelse return null;
        var token = Token{ .grapheme = c, .is_ansi_codepoint = false };
        if (c.len > 1) {
            return token;
        }
        const char = c[0];
        if (char & '\x1F' >= 'a' and char & '\x1F' <= 'w') {
            token.is_ansi_codepoint = true;
            return token;
        }
        if (char == '\n' or char == '\r') {
            return token;
        }
        if (char != '\x1B') {
            return token;
        }
        if (buf[start..].len <= 1) {
            return error.IncompleteCodepoint;
        }
        if (buf[start + 1] != '[') {
            return error.CannotDecodeYet;
        }

        const len = self.consume_till_m();
        if (len == 0) {
            return error.BadCodepoint;
        }
        return Token{ .grapheme = buf[start..][0..len], .is_ansi_codepoint = true };
    }

    fn consume_till_m(self: *@This()) usize {
        var it = self.utf8;
        const start = it.i;
        while (it.nextCodepointSlice()) |c| {
            if (c.len != 1) {
                return 0;
            }
            if (c[0] == 'm') {
                self.utf8 = it;
                return it.i - start + 1;
            }
        }
        return 0;
    }
};

const Term = struct {
    tty: std.fs.File,

    size: Vec2 = .{},
    cooked_termios: ?std.posix.termios = null,
    raw: ?std.posix.termios = null,

    i: u32 = 0,

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

    fn uncook(self: *@This()) !void {
        try self.enter_raw_mode();
        try self.tty.writeAll(ansi.cursor.hide ++ ansi.alt_buf.enter ++ ansi.clear);
        self.register_signal_handlers();
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

    fn clear_region(self: *@This(), offset: Vec2, size: Vec2) !void {
        for (offset.y..offset.y + size.y) |y| {
            try self.cursor_move(.{ .y = cast(u16, y), .x = offset.x });
            try self.writer().writeByteNTimes(' ', @min(size.x, cast(u16, @max(cast(i32, self.size.x) - offset.x, 0))));
        }
    }

    fn draw_at(self: *@This(), pos: Vec2, token: []const u8) !void {
        if (self.size.x > pos.x and self.size.y > pos.y) {
            try self.cursor_move(pos);
            try self.writer().writeAll(token);
        }
    }

    fn draw_border(self: *@This(), offset: Vec2, size: Vec2, border_style: anytype) !void {
        try self.cursor_move(offset.add(.{ .x = 1 }));
        try self.writer().writeBytesNTimes(border_style.horizontal, @min(size.x - 2, self.size.x - offset.x - 1));
        try self.cursor_move(offset.add(.{ .x = 1, .y = size.y - 1 }));
        try self.writer().writeBytesNTimes(border_style.horizontal, @min(size.x - 2, self.size.x - offset.x - 1));

        try self.draw_at(offset, border_style.top_left);
        try self.draw_at(offset.add(.{ .x = size.x - 1 }), border_style.top_right);
        try self.draw_at(offset.add(.{ .y = size.y - 1 }), border_style.bottom_left);
        try self.draw_at(offset.add(size).sub(.splat(1)), border_style.bottom_right);

        for (offset.y + 1..offset.y + size.y - 1) |y| {
            try self.draw_at(.{ .y = cast(u16, y), .x = offset.x }, border_style.vertical);
            try self.draw_at(.{ .y = cast(u16, y), .x = offset.x + size.x - 1 }, border_style.vertical);
        }
    }

    fn draw_buf(self: *@This(), buf: []const u8, offset: Vec2, size: Vec2) !void {
        var line_it = utils_mod.LineIterator{ .buf = buf };
        for (offset.y..offset.y + size.y) |y| {
            const line = line_it.next() orelse break;
            try self.cursor_move(.{ .y = cast(u16, y), .x = offset.x });

            var codepoint_it = try TermStyledGraphemeIterator.init(line);

            var x: u16 = 0;
            while (try codepoint_it.next()) |token| {
                // execute all control chars
                // but don't print beyond the size
                if (token.is_ansi_codepoint) {
                    try self.writer().writeAll(token.grapheme);
                } else if (x < size.x and (x + offset.x < self.size.x)) {
                    try self.writer().writeAll(token.grapheme);
                    x += 1;
                }
            }
        }
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

    fn register_signal_handlers(_: *@This()) void {
        const handler = struct {
            fn winch(_: c_int) callconv(.C) void {}
        };
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const temp = arena.allocator();

    var term = try Term.init(alloc);
    defer term.deinit();

    const jj_output = try utils_mod.jjcall(&[_][]const u8{ "jj", "--color", "always" }, temp);
    var inputs = std.ArrayList([]const u8).init(temp);
    defer {
        for (inputs.items) |line| {
            outer: for (line) |char| {
                if (char == '\x1B') {
                    std.debug.print("\\x1B", .{});
                } else if (char == '\n' or char == '\r') {
                    continue :outer;
                } else {
                    const chars = [_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'j', 'k', 'l', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w' };
                    for (chars) |c| {
                        if (char == c & '\x1F') {
                            std.debug.print("\\x{c}", .{c});
                            continue :outer;
                        }
                    }

                    std.debug.print("{c}", .{char});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    try term.uncook();
    defer term.cook_restore() catch |e| utils_mod.dump_error(e);

    while (true) {
        try term.update_size();
        {
            try term.clear_region(.{}, term.size);
            try term.draw_border(.{}, term.size, border.rounded);
            try term.draw_buf(jj_output, .splat(1), term.size.sub(.splat(2)));

            const offset = Vec2{ .x = 30, .y = 3 };
            const size = Vec2{ .x = 60, .y = 20 };
            try term.clear_region(offset, size);
            try term.draw_border(offset, size, border.rounded);
            try term.draw_buf(jj_output, offset.add(.splat(1)), size.sub(.splat(2)));
        }
        try term.flush_writes();

        var buf = std.mem.zeroes([1]u8);
        const len = try term.tty.read(&buf);
        try inputs.append(try temp.dupe(u8, buf[0..len]));

        if (buf[0] == 'q') {
            return;
        } else if (buf[0] == '\x1B') {
            term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 1;
            term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 0;
            try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

            var esc_buf: [8]u8 = undefined;
            const esc_read = try term.tty.read(&esc_buf);

            term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 0;
            term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 1;
            try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

            if (std.mem.eql(u8, esc_buf[0..esc_read], "[A")) {
                term.i -|= 1;
            } else if (std.mem.eql(u8, esc_buf[0..esc_read], "[B")) {
                term.i = @min(term.i + 1, 3);
            }
        }
    }
}
