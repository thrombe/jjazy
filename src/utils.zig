const std = @import("std");
const builtin = @import("builtin");

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

pub const Log = struct {
    path: []const u8 = "./zig-out/log.log",
    file: ?std.fs.File = null,
    alloc: ?std.mem.Allocator = null,

    pub const Writer = std.io.Writer(*const @This(), anyerror, @This().write);

    pub var logger = @This(){};
    pub var writer = Writer{ .context = &logger };

    pub fn init(self: *@This(), alloc: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile(self.path, .{});
        errdefer file.close();

        const stat = try file.stat();
        try file.seekTo(stat.size);

        self.file = file;
        self.alloc = alloc;
    }

    pub fn deinit(self: *@This()) void {
        if (self.file) |file| file.close();
        self.file = null;
        self.alloc = null;
    }

    pub fn log(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const prefix = "[" ++ comptime level.asText() ++ "] " ++ "(" ++ @tagName(scope) ++ ") ";
        logger.log_write(prefix ++ format ++ "\n", args);
    }

    fn write(self: *const @This(), bytes: []const u8) anyerror!usize {
        self.log_write("{s}", .{bytes});
        return bytes.len;
    }

    fn log_write(
        self: *const @This(),
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (self.file == null) {
            std.debug.print("File is cloded\n", .{});
            std.debug.print(format, args);
            return;
        }

        // TODO: don't alloc here. maybe cache buffers in threadlocals or just use a statically sized buf + bufprint
        const message = std.fmt.allocPrint(self.alloc.?, format, args) catch |err| {
            std.debug.print("Failed to format log message with args: {}\n", .{err});
            return;
        };
        defer self.alloc.?.free(message);

        self.file.?.writeAll(message) catch |err| {
            std.debug.print("Failed to write to log file: {}\n", .{err});
        };
    }
};

pub inline fn dump_error(err: anyerror) void {
    std.log.err("error: {any}\n", .{err});
    if (@errorReturnTrace()) |trace| {
        nosuspend {
            if (builtin.strip_debug_info) {
                std.log.err("Unable to dump stack trace: debug info stripped\n", .{});
                return;
            }
            const debug_info = std.debug.getSelfDebugInfo() catch |e| {
                std.log.err("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(e)});
                return;
            };
            std.debug.writeStackTrace(trace.*, Log.writer, debug_info, std.io.tty.detectConfig(std.io.getStdErr())) catch |e| {
                std.log.err("Unable to dump stack trace: {s}\n", .{@errorName(e)});
                return;
            };
        }
    }
}

pub const LineIterator = struct {
    buf: []const u8,
    index: usize = 0,

    pub fn init(buf: []const u8) @This() {
        return .{ .buf = buf };
    }

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

pub fn Deque(typ: type) type {
    return struct {
        allocator: std.mem.Allocator,
        buffer: []typ,
        size: usize,

        // fill this index next
        front: usize, // at
        back: usize, // one to the right

        pub fn init(alloc: std.mem.Allocator) !@This() {
            const len = 32;
            const buffer = try alloc.alloc(typ, len);
            return .{
                .allocator = alloc,
                .buffer = buffer,
                .front = 0,
                .back = 0,
                .size = 0,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.buffer);
        }

        pub fn push_front(self: *@This(), value: typ) !void {
            if (self.size == self.buffer.len) {
                try self.resize();
                return self.push_front(value) catch unreachable;
            }
            self.front = (self.front + self.buffer.len - 1) % self.buffer.len;
            self.buffer[self.front] = value;
            self.size += 1;
        }

        pub fn push_back(self: *@This(), value: typ) !void {
            if (self.size == self.buffer.len) {
                try self.resize();
                return self.push_back(value) catch unreachable;
            }
            self.buffer[self.back] = value;
            self.back = (self.back + 1) % self.buffer.len;
            self.size += 1;
        }

        pub fn pop_front(self: *@This()) ?typ {
            if (self.size == 0) {
                return null;
            }
            const value = self.buffer[self.front];
            self.front = (self.front + 1) % self.buffer.len;
            self.size -= 1;
            return value;
        }

        pub fn pop_back(self: *@This()) ?typ {
            if (self.size == 0) {
                return null;
            }
            self.back = (self.back + self.buffer.len - 1) % self.buffer.len;
            const value = self.buffer[self.back];
            self.size -= 1;
            return value;
        }

        pub fn peek_front(self: *@This()) ?*const typ {
            if (self.size == 0) {
                return null;
            }
            return &self.buffer[self.front];
        }

        pub fn peek_back(self: *@This()) ?*const typ {
            if (self.size == 0) {
                return null;
            }
            const back = (self.back + self.buffer.len - 1) % self.buffer.len;
            return &self.buffer[back];
        }

        pub fn is_empty(self: *@This()) bool {
            return self.size == 0;
        }

        fn resize(self: *@This()) !void {
            std.debug.assert(self.size == self.buffer.len);

            const size = self.buffer.len * 2;
            const buffer = try self.allocator.alloc(typ, size);
            @memcpy(buffer[0 .. self.size - self.front], self.buffer[self.front..]);
            @memcpy(buffer[self.size - self.front .. self.size], self.buffer[0..self.front]);
            const new = @This(){
                .allocator = self.allocator,
                .buffer = buffer,
                .front = 0,
                .back = self.size,
                .size = self.size,
            };
            self.allocator.free(self.buffer);
            self.* = new;
        }
    };
}

// MAYBE: condvars + .block_recv()
pub fn Channel(typ: type) type {
    return struct {
        const Dq = Deque(typ);
        const Pinned = struct {
            dq: Dq,
            lock: std.Thread.Mutex = .{},
            notify: std.Thread.Condition = .{},
            closed: Fuse = .{},
            waiting: std.atomic.Value(u32) = .{ .raw = 0 },
        };
        pinned: *Pinned,

        pub fn init(alloc: std.mem.Allocator) !@This() {
            const dq = try Dq.init(alloc);
            const pinned = try alloc.create(Pinned);
            pinned.* = .{
                .dq = dq,
            };
            return .{
                .pinned = pinned,
            };
        }

        pub fn deinit(self: *@This()) void {
            _ = self.pinned.closed.fuse();
            self.pinned.notify.signal();

            self.pinned.lock.lock();
            // defer self.pinned.lock.unlock();

            while (true) {
                // timeouts are fine here.
                self.pinned.notify.timedWait(&self.pinned.lock, std.time.ns_per_us * 100) catch {};
                const waiting = self.pinned.waiting.fetchAdd(0, .monotonic);
                if (waiting == 0) break;
                self.pinned.notify.signal();
            }

            self.pinned.dq.deinit();
            self.pinned.dq.allocator.destroy(self.pinned);
        }

        pub fn send(self: *@This(), val: typ) !void {
            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();
            try self.pinned.dq.push_back(val);

            self.pinned.notify.signal();
        }

        pub fn try_recv(self: *@This()) ?typ {
            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();
            return self.pinned.dq.pop_front();
        }

        pub fn can_recv(self: *@This()) bool {
            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();
            return self.pinned.dq.peek_front() != null;
        }

        pub fn try_pop(self: *@This()) ?typ {
            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();
            return self.pinned.dq.pop_back();
        }

        // only marks the channel closed for .wait_* operations. does not actually prevent recving or sending to the channel
        // this causes the .wait_* methods to not block. they essentially behave like .try_* methods
        pub fn close(self: *@This()) void {
            _ = self.pinned.closed.fuse();
            self.pinned.notify.signal();
        }

        pub fn wait_recv(self: *@This()) ?typ {
            if (self.try_recv()) |t| return t;
            if (self.pinned.closed.check()) return null;

            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();

            _ = self.pinned.waiting.fetchAdd(1, .monotonic);
            defer _ = self.pinned.waiting.fetchSub(1, .monotonic);

            // when returning null, we want to signal atleast the deinit method
            // when returning non-null, we want to signal some thread that might be listening for stuff
            defer self.pinned.notify.signal();

            while (true) {
                if (self.pinned.dq.pop_front()) |t| return t;

                if (self.pinned.closed.check()) return null;

                self.pinned.notify.wait(&self.pinned.lock);
            }
        }

        pub fn wait_pop(self: *@This()) ?typ {
            if (self.try_pop()) |t| return t;
            if (self.pinned.closed.check()) return null;

            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();

            _ = self.pinned.waiting.fetchAdd(1, .monotonic);
            defer _ = self.pinned.waiting.fetchSub(1, .monotonic);

            // when returning null, we want to signal atleast the deinit method
            // when returning non-null, we want to signal some thread that might be listening for stuff
            defer self.pinned.notify.signal();

            while (true) {
                if (self.pinned.dq.pop_back()) |t| return t;

                if (self.pinned.closed.check()) return null;

                self.pinned.notify.wait(&self.pinned.lock);
            }
        }
    };
}

pub const Fuse = struct {
    fused: std.atomic.Value(bool) = .{ .raw = false },

    pub fn fuse(self: *@This()) bool {
        return self.fused.swap(true, .release);
    }
    pub fn unfuse(self: *@This()) bool {
        const res = self.fused.swap(false, .release);
        return res;
    }
    pub fn check(self: *@This()) bool {
        return self.fused.load(.acquire);
    }
};
