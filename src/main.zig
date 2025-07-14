const std = @import("std");

const ansi = struct {
    const clear = "\x1B[2J";
    const attr_reset = "\x1B[0m";
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

const Term = struct {
    tty: std.fs.File,

    size: Size,
    cooked_termios: ?std.posix.termios = null,
    raw: ?std.posix.termios = null,

    i: u32 = 0,

    const Size = struct { width: usize, height: usize };

    fn init() !@This() {
        const tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        var win_size = std.mem.zeroes(std.posix.winsize);
        const err = std.os.linux.ioctl(tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&win_size));
        if (std.posix.errno(err) != .SUCCESS) {
            return std.posix.unexpectedErrno(@as(std.posix.E, @enumFromInt(err)));
        }
        const size = Size{ .height = win_size.row, .width = win_size.col };

        return @This(){
            .tty = tty,
            .size = size,
        };
    }

    fn deinit(self: *@This()) void {
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

    fn cursor_move(self: *@This(), v: struct { y: u16 = 0, x: u16 = 0 }) !void {
        try self.tty.writer().print(ansi.cursor.move, .{ v.y, v.x });
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

    var term = try Term.init();
    defer term.deinit();

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
    defer term.cook_restore() catch {};

    var buf = std.mem.zeroes([1]u8);
    while (true) {
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

// fn render() !void {
//     const writer = tty.writer();
//     try writeLine(writer, "foo", 0, size.width, i == 0);
//     try writeLine(writer, "bar", 1, size.width, i == 1);
//     try writeLine(writer, "baz", 2, size.width, i == 2);
//     try writeLine(writer, "xyzzy", 3, size.width, i == 3);
// }

// fn writeLine(writer: anytype, txt: []const u8, y: usize, width: usize, selected: bool) !void {
//     if (selected) {
//         try blueBackground(writer);
//     } else {
//         try attributeReset(writer);
//     }
//     try moveCursor(writer, y, 0);
//     try writer.writeAll(txt);
//     try writer.writeByteNTimes(' ', width - txt.len);
// }

// fn blueBackground(writer: anytype) !void {
//     try writer.writeAll("\x1B[44m");
// }
