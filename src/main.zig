const std = @import("std");

pub inline fn cast(typ: type, val: anytype) typ {
    const E = @typeInfo(@TypeOf(val));
    const T = @typeInfo(typ);
    if (comptime (std.meta.activeTag(E) == .int and std.meta.activeTag(T) == .float)) {
        return @floatFromInt(val);
    }
    if (comptime (std.meta.activeTag(E) == .float and std.meta.activeTag(T) == .int)) {
        return @intFromFloat(val);
    }
    if (comptime (std.meta.activeTag(E) == .float and std.meta.activeTag(T) == .float)) {
        return @floatCast(val);
    }
    if (comptime (std.meta.activeTag(E) == .int and std.meta.activeTag(T) == .int)) {
        return @intCast(val);
    }
    if (comptime (std.meta.activeTag(E) == .comptime_int)) {
        return val;
    }
    if (comptime (std.meta.activeTag(E) == .comptime_float)) {
        if (comptime (std.meta.activeTag(T) == .float)) {
            return val;
        }
        if (comptime (std.meta.activeTag(T) == .int)) {
            return @intFromFloat(@as(f32, val));
        }
    }
    @compileError("can't cast from '" ++ @typeName(@TypeOf(val)) ++ "' to '" ++ @typeName(typ) ++ "'");
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
