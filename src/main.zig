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

    fn draw_buf(self: *@This(), buf: []const u8, min: Vec2, max: Vec2) !void {
        var line_it = utils_mod.LineIterator{ .buf = buf };
        for (@intCast(self.size.min(min).max(.{}).y)..@intCast(self.size.min(max.add(.splat(1))).y)) |y| {
            const line = line_it.next() orelse break;
            try self.cursor_move(.{ .y = cast(u16, y), .x = min.x });

            var codepoint_it = try TermStyledGraphemeIterator.init(line);

            var x: i32 = min.x;
            while (try codepoint_it.next()) |token| {
                // execute all control chars
                // but don't print beyond the size
                if (token.is_ansi_codepoint) {
                    try self.writer().writeAll(token.grapheme);
                } else if (x <= max.min(self.size.sub(.splat(1))).x) {
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
        diff,
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
                    const res = utils_mod.jjcall(&[_][]const u8{ "jj", "--color", "always" }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.responses.send(.{ .req = req, .res = .{ .ok = res } });
                },
                .diff => {
                    const res = utils_mod.jjcall(&[_][]const u8{ "jj", "--color", "always", "diff", "--tool", "delta" }, self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.responses.send(.{ .req = req, .res = .{ .ok = res } });
                },
            };

            if (self.quit.check()) break;

            std.Thread.sleep(std.time.ns_per_ms * 100);
        }
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

    status: []const u8,
    diff: []const u8,

    const Event = union(enum) {
        sigwinch,
        rerender,
        quit,
        input: u8,
    };

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
        try jj.requests.send(.diff);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .term = term,
            .events = events,
            .jj = jj,
            .status = &.{},
            .diff = &.{},
            .input_thread = undefined,
        };

        const input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        errdefer {
            _ = self.quit.fuse();
            input_thread.join();
        }

        self.input_thread = input_thread;
        app = self;
        return self;
    }

    fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer alloc.free(self.status);
        defer alloc.free(self.diff);
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
            if (try std.posix.poll(&fds, 100) > 0) {
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
                        },
                        .err => |buf| {
                            self.status = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
                .diff => {
                    self.alloc.free(self.diff);
                    switch (res.res) {
                        .ok => |buf| {
                            self.diff = buf;
                        },
                        .err => |buf| {
                            self.diff = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
            };

            std.Thread.sleep(std.time.ns_per_ms * 100);
        }
    }

    fn render(self: *@This()) !void {
        try self.term.update_size();
        {
            try self.term.clear_region(.{}, self.term.size.sub(.splat(1)));
            try self.term.draw_buf(self.diff, .splat(1), self.term.size.sub(.splat(2)));
            try self.term.draw_border(.{}, self.term.size.sub(.splat(1)), border.rounded);

            const min = Vec2{ .x = 30, .y = 3 };
            const max = min.add(.{ .x = 60, .y = 20 });
            const split_x: i32 = 55;
            try self.term.clear_region(min, max);
            try self.term.draw_buf(self.diff, min.add(.splat(1)), (Vec2{ .x = split_x, .y = max.y }).sub(.splat(1)));
            try self.term.draw_buf(self.status, (Vec2{ .x = split_x, .y = min.y }).add(.splat(1)), max.sub(.splat(1)));
            try self.term.draw_border(min, max, border.rounded);
            try self.term.draw_split(min, max, split_x, null);
        }
        try self.term.flush_writes();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const app = try App.init(gpa.allocator());
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
