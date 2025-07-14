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

pub fn jjcall(args: []const []const u8, alloc: std.mem.Allocator) ![]u8 {
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

pub const LineIterator = struct {
    buf: []const u8,
    index: usize = 0,

    pub fn next(self: *LineIterator) ?[]const u8 {
        if (self.index >= self.buf.len) return null;

        const start = self.index;
        const end = std.mem.indexOfAnyPos(u8, self.buf, self.index, "\r\n") orelse {
            self.index = self.buf.len;
            return self.buf[start..];
        };

        self.index = end;
        self.consume_nl();
        self.consume_cr();
        return self.buf[start..end];
    }

    // consumes \n
    fn consume_nl(self: *LineIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\n') self.index += 1;
    }

    // consumes \r
    fn consume_cr(self: *LineIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\r') self.index += 1;
    }
};
