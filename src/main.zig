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

const Vec2 = struct {
    x: u16 = 0,
    y: u16 = 0,
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
        try self.writer().writeAll(ansi.sync_set);
    }

    fn update_size(self: *@This()) !void {
        var win_size = std.mem.zeroes(std.posix.winsize);
        const err = std.os.linux.ioctl(self.tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&win_size));
        if (std.posix.errno(err) != .SUCCESS) {
            return std.posix.unexpectedErrno(@as(std.posix.E, @enumFromInt(err)));
        }
        self.size = .{ .y = win_size.row, .x = win_size.col };
    }

    fn cursor_move(self: *@This(), v: struct { y: u16 = 0, x: u16 = 0 }) !void {
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
        { // render
            var it = utils_mod.LineIterator{ .buf = jj_output };
            var i: u16 = 0;
            while (it.next()) |line| {
                try term.cursor_move(.{ .y = i });
                try term.writer().writeAll(line);
                i += 1;
            }
        }
        { // clear new window size
            const offset = .{ .x = 30, .y = 1 };
            for (offset.y..term.size.y) |y| {
                try term.cursor_move(.{ .y = cast(u16, y) + offset.y, .x = offset.x });
                // for (offset.x..term.size.x) |_| {
                //     try term.writer().writeAll(" ");
                // }
                try term.writer().writeByteNTimes(' ', term.size.x - offset.x);
            }

            { // render again, but offset it on x and y
                var it = utils_mod.LineIterator{ .buf = jj_output };
                var i: u16 = 0;
                while (it.next()) |line| {
                    try term.cursor_move(.{ .y = i + offset.y, .x = offset.x });
                    // for (line) |char| {
                    //     try term.writer().print("{c}", .{char});
                    // }
                    try term.writer().writeAll(line);
                    i += 1;
                }
            }
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
