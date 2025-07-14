const std = @import("std");

var i: usize = 0;
var size: Size = undefined;
var cooked_termios: std.posix.termios = undefined;
var raw: std.posix.termios = undefined;
var tty: std.fs.File = undefined;

pub fn main() !void {
    tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
    defer tty.close();

    try uncook();
    defer cook() catch {};

    size = try getSize();

    std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    while (true) {
        try render();

        var buffer: [1]u8 = undefined;
        _ = try tty.read(&buffer);

        if (buffer[0] == 'q') {
            return;
        } else if (buffer[0] == '\x1B') {
            raw.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 1;
            raw.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 0;
            try std.posix.tcsetattr(tty.handle, .NOW, raw);

            var esc_buffer: [8]u8 = undefined;
            const esc_read = try tty.read(&esc_buffer);

            raw.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 0;
            raw.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 1;
            try std.posix.tcsetattr(tty.handle, .NOW, raw);

            if (std.mem.eql(u8, esc_buffer[0..esc_read], "[A")) {
                i -|= 1;
            } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[B")) {
                i = @min(i + 1, 3);
            }
        }
    }
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    size = getSize() catch return;
    render() catch return;
}

fn render() !void {
    const writer = tty.writer();
    try writeLine(writer, "foo", 0, size.width, i == 0);
    try writeLine(writer, "bar", 1, size.width, i == 1);
    try writeLine(writer, "baz", 2, size.width, i == 2);
    try writeLine(writer, "xyzzy", 3, size.width, i == 3);
}

fn writeLine(writer: anytype, txt: []const u8, y: usize, width: usize, selected: bool) !void {
    if (selected) {
        try blueBackground(writer);
    } else {
        try attributeReset(writer);
    }
    try moveCursor(writer, y, 0);
    try writer.writeAll(txt);
    try writer.writeByteNTimes(' ', width - txt.len);
}

fn uncook() !void {
    const writer = tty.writer();
    cooked_termios = try std.posix.tcgetattr(tty.handle);
    errdefer cook() catch {};

    raw = cooked_termios;
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
    try std.posix.tcsetattr(tty.handle, .FLUSH, raw);

    try hideCursor(writer);
    try enterAlt(writer);
    try clear(writer);
}

fn cook() !void {
    const writer = tty.writer();
    try clear(writer);
    try leaveAlt(writer);
    try showCursor(writer);
    try attributeReset(writer);
    try std.posix.tcsetattr(tty.handle, .FLUSH, cooked_termios);
}

fn moveCursor(writer: anytype, row: usize, col: usize) !void {
    _ = try writer.print("\x1B[{};{}H", .{ row + 1, col + 1 });
}

fn enterAlt(writer: anytype) !void {
    try writer.writeAll("\x1B[s"); // Save cursor position.
    try writer.writeAll("\x1B[?47h"); // Save screen.
    try writer.writeAll("\x1B[?1049h"); // Enable alternative buffer.
}

fn leaveAlt(writer: anytype) !void {
    try writer.writeAll("\x1B[?1049l"); // Disable alternative buffer.
    try writer.writeAll("\x1B[?47l"); // Restore screen.
    try writer.writeAll("\x1B[u"); // Restore cursor position.
}

fn hideCursor(writer: anytype) !void {
    try writer.writeAll("\x1B[?25l");
}

fn showCursor(writer: anytype) !void {
    try writer.writeAll("\x1B[?25h");
}

fn attributeReset(writer: anytype) !void {
    try writer.writeAll("\x1B[0m");
}

fn blueBackground(writer: anytype) !void {
    try writer.writeAll("\x1B[44m");
}

fn clear(writer: anytype) !void {
    try writer.writeAll("\x1B[2J");
}

const Size = struct { width: usize, height: usize };

fn getSize() !Size {
    var win_size = std.mem.zeroes(std.posix.winsize);
    const err = std.os.linux.ioctl(tty.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&win_size));
    if (std.posix.errno(err) != .SUCCESS) {
        return std.posix.unexpectedErrno(@as(std.posix.E, @enumFromInt(err)));
    }
    return Size{ .height = win_size.row, .width = win_size.col };
}
