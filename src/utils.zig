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

const PtrFollow = enum { disabled, ptr_as_usize, follow };
const AutoHashArgs = struct {
    pointer_hashing: PtrFollow = .disabled,
};
pub fn hash_update(hasher: anytype, val: anytype, comptime v: AutoHashArgs) void {
    if (comptime std.meta.activeTag(@typeInfo(@TypeOf(hasher))) != .pointer) @compileError("you prob want to pass a pointer to a hasher in hash_update() :/");

    const T = @TypeOf(val);
    const Ti = @typeInfo(T);
    switch (Ti) {
        inline .float, .int, .bool => hasher.update(&std.mem.toBytes(val)),
        .array => for (val) |e| hash_update(hasher, e, v),
        .@"struct" => |e| {
            inline for (e.fields) |field| {
                hash_update(hasher, @field(val, field.name), v);
            }
        },
        .@"enum" => hash_update(hasher, @intFromEnum(val), v),
        .@"union" => |e| {
            hash_update(hasher, std.meta.activeTag(val), v);
            inline for (e.fields) |field| {
                if (std.meta.activeTag(val) == std.meta.stringToEnum(std.meta.Tag(T), field.name)) {
                    hash_update(hasher, @field(val, field.name), v);
                }
            }
        },
        .void => {},
        .optional => if (val) |e| hash_update(hasher, e, v),
        .pointer => |p| switch (p.size) {
            .one => switch (comptime v.pointer_hashing) {
                .disabled => @compileError("pointer hashing is disabled"),
                .follow => hash_update(hasher, val.*, v),
                .ptr_as_usize => hash_update(hasher, @intFromPtr(val), v),
            },
            .slice => switch (comptime v.pointer_hashing) {
                .disabled => @compileError("pointer hashing is disabled"),
                .follow => for (val) |e| hash_update(hasher, e, v),
                .ptr_as_usize => {
                    hash_update(hasher, val.len, v);
                    hash_update(hasher, val.ptr, v);
                },
            },
            .many, .c => @compileError("hash_update() for type '" ++ @typeName(T) ++ "' not supported"),
        },
        else => @compileError("hash_update() for type '" ++ @typeName(T) ++ "' not supported"),
    }
}

const AutoEqArgs = struct {
    pointer_eq: PtrFollow = .disabled,
};
pub fn auto_eql(a: anytype, b: @TypeOf(a), comptime v: AutoEqArgs) bool {
    const T = @TypeOf(a);
    const Ti = @typeInfo(T);
    switch (Ti) {
        inline .@"enum", .float, .int, .bool => return std.meta.eql(a, b),
        .array => {
            if (a.len != b.len) return false;
            for (0..a.len) |i| {
                if (!auto_eql(a[i], b[i], v)) {
                    return false;
                }
            }
            return true;
        },
        .@"struct" => |e| {
            inline for (e.fields) |field| {
                if (!auto_eql(@field(a, field.name), @field(b, field.name), v)) return false;
            }
            return true;
        },
        .@"union" => |e| {
            if (!std.meta.eql(std.meta.activeTag(a), std.meta.activeTag(b))) return false;
            inline for (e.fields) |field| {
                if (!auto_eql(@field(a, field.name), @field(b, field.name), v)) return false;
            }
            return true;
        },
        .void => return true,
        .optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return auto_eql(a.?, b.?, .{});
        },
        .pointer => |p| switch (p.size) {
            .one => switch (comptime v.pointer_hashing) {
                .disabled => @compileError("pointer hashing is disabled"),
                .follow => return auto_eql(a.*, b.*, v),
                .ptr_as_usize => return auto_eql(@intFromPtr(a), @intFromPtr(b), v),
            },
            .slice => switch (comptime v.pointer_hashing) {
                .disabled => @compileError("pointer hashing is disabled"),
                .follow => {
                    if (a.len != b.len) return false;
                    for (a, b) |ae, be| {
                        if (!auto_eql(ae, be, v)) return false;
                    }
                    return true;
                },
                .ptr_as_usize => return auto_eql(a.len, b.len, v) and auto_eql(a.ptr, b.ptr, v),
            },
            .many, .c => @compileError("auto_eql() for type '" ++ @typeName(T) ++ "' not supported"),
        },
        else => @compileError("auto_eql() for type '" ++ @typeName(T) ++ "' not supported"),
    }
}

pub fn AutoHashContext(typ: type, comptime v: AutoHashArgs) type {
    return struct {
        pub fn hash(_: @This(), a: typ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hash_update(&hasher, a, v);
            return hasher.final();
        }
        pub fn eql(_: @This(), a: typ, b: typ) bool {
            return auto_eql(a, b, .{ .pointer_eq = v.pointer_hashing });
        }
    };
}

pub fn AutoHashMap(key: type, val: type, v: AutoHashArgs) type {
    return std.HashMap(key, val, AutoHashContext(key, v), std.hash_map.default_max_load_percentage);
}

pub const FileLogger = struct {
    path: []const u8 = "./zig-out/log.log",
    file: ?std.fs.File = null,
    alloc: ?std.mem.Allocator = null,
    enabled: bool = true,

    pub const Writer = std.io.Writer(*const @This(), anyerror, @This().write);

    pub var logger = @This(){};
    pub var writer = Writer{ .context = &logger };

    pub fn init(self: *@This(), alloc: std.mem.Allocator, v: struct {
        path: ?[]const u8 = null,
        allow_fail: bool = false,
    }) !void {
        if (v.path) |path| self.path = path;
        const file = std.fs.cwd().createFile(self.path, .{}) catch |e| {
            if (v.allow_fail) {
                self.enabled = false;
                return;
            }
            return e;
        };
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
        if (!self.enabled) {
            return;
        }
        if (self.file == null) {
            std.debug.print("File is closed\n", .{});
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
            std.debug.writeStackTrace(trace.*, FileLogger.writer, debug_info, std.io.tty.detectConfig(std.io.getStdErr())) catch |e| {
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

    pub fn peek(self: *@This()) ?[]const u8 {
        var this = self.*;
        return this.next();
    }

    pub fn next(self: *@This()) ?[]const u8 {
        if (self.ended()) return null;

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

    pub fn ended(self: *@This()) bool {
        return self.index >= self.buf.len;
    }

    pub fn count_height(self: @This()) i32 {
        var it = self;
        var height: i32 = 0;
        while (it.next()) |_| {
            height += 1;
        }
        return height;
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

        pub fn count(self: *@This()) usize {
            self.pinned.lock.lock();
            defer self.pinned.lock.unlock();
            return self.pinned.dq.size;
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

pub fn ArrayXar(T: type, base_chunk_size_log2: comptime_int) type {
    if (base_chunk_size_log2 == 0 or base_chunk_size_log2 >= 48) {
        @compileError("comptime assertion failed 48 > chunk_len_log2 > 0");
    }

    const base_chunk_size = 1 << base_chunk_size_log2;
    const chunks = 48 + 1 - base_chunk_size_log2;
    return struct {
        chunks: [chunks]?[*]T,
        size: usize = 0,
        alloc: std.mem.Allocator,
        // index chunk_size total_size
        // 0-1 2^1 2^1
        // 2-3 2^1 2^2
        // 4-7 2^2 2^3
        // 8-15 2^3 2^4
        // 16-31 2^4 2^5
        // 32-63 2^5 2^6

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .alloc = alloc,
                .chunks = std.mem.zeroes([chunks]?[*]T),
            };
        }

        pub fn clearRetainingCapacity(self: *@This()) void {
            self.size = 0;
        }

        pub fn deinit(self: *@This()) void {
            self.size = 0;
            for (&self.chunks, 0..) |*_chunk, i| if (_chunk.*) |chunk| {
                const pow: u6 = @intCast(i);
                const size = chunkSize(pow);
                self.alloc.free(chunk[0..size]);
                _chunk.* = null;
            };
        }

        inline fn chunkIndex(index: usize) u6 {
            const lim_log2: u6 = @intCast(64 - @clz(index));
            std.debug.assert(lim_log2 <= 48);
            const is_greater_than_base = @intFromBool(lim_log2 > base_chunk_size_log2);
            const chunk_index: u6 = is_greater_than_base * (lim_log2 - base_chunk_size_log2 * @as(u6, is_greater_than_base));
            return chunk_index;
        }

        inline fn chunkSize(chunk_index: u6) usize {
            const size: usize = @as(usize, base_chunk_size) << @max(chunk_index, 1) - 1;
            return size;
        }

        pub fn getPtr(self: *@This(), index: usize) ?*T {
            if (self.size <= index) return null;

            const chunk_index = chunkIndex(index);
            const chunk_size = chunkSize(chunk_index);

            if (self.chunks[chunk_index]) |chunk| {
                return &chunk[0..chunk_size][index - chunk_size * @intFromBool(chunk_index > 0)];
            } else {
                return null;
            }
        }

        pub fn get(self: *@This(), index: usize) ?T {
            const t = self.getPtr(index) orelse return null;
            return t.*;
        }

        pub fn addOne(self: *@This()) !*T {
            const chunk_index = chunkIndex(self.size);
            const chunk_size = chunkSize(chunk_index);

            if (self.chunks[chunk_index] == null) {
                const chunk = try self.alloc.alloc(T, chunk_size);
                self.chunks[chunk_index] = chunk.ptr;
            }

            defer self.size += 1;
            return &self.chunks[chunk_index].?[0..chunk_size][self.size - chunk_size * @intFromBool(chunk_index > 0)];
        }

        pub fn append(self: *@This(), val: T) !void {
            const new = try self.addOne();
            new.* = val;
        }

        pub fn pop(self: *@This()) ?T {
            if (self.size > 0) {
                defer self.size -|= 1;
                return self.get(self.size - 1);
            } else {
                return null;
            }
        }

        pub fn ownedSlice(self: *@This(), v: struct {
            alloc: ?std.mem.Allocator = null,
            reset: enum { none, deinit, clear_retaining_capacity } = .none,
        }) ![]T {
            const alloc = v.alloc orelse self.alloc;
            const buffer = try alloc.alloc(T, self.size);
            errdefer alloc.free(buffer);

            var it = self.chunkIterator(.{});
            while (it.next()) |e| {
                @memcpy(buffer[e.offset..][0..e.chunk.len], e.chunk);
            }

            switch (v.reset) {
                .none => {},
                .deinit => self.deinit(),
                .clear_retaining_capacity => self.clearRetainingCapacity(),
            }
            return buffer;
        }

        pub fn chunkIterator(self: *const @This(), v: struct { start: ?usize = null, size: ?usize = null }) ChunkIterator {
            const start = v.start orelse 0;
            const chunk_index = chunkIndex(start);

            const size = if (v.size) |size| @min(self.size, start + size) else self.size;
            return .{
                .chunks = self.chunks,
                .size = size,
                .remaining = size -| start,
                .index = chunk_index,
            };
        }

        pub fn iterator(self: *const @This(), v: struct { start: ?usize = null, size: ?usize = null }) Iterator {
            var it = self.chunkIterator(.{ .start = v.start, .size = v.size });
            const start = v.start orelse 0;
            const chunk_index = chunkIndex(start);
            const chunk_size = chunkSize(chunk_index);
            const index_in_chunk = start - chunk_size * @intFromBool(chunk_index > 0);

            const chunk = it.next();
            return .{
                .it = it,
                .chunk = if (chunk) |e| e.chunk else null,
                .index = index_in_chunk,
            };
        }

        const ChunkIterator = struct {
            chunks: [chunks]?[*]T,
            size: usize,
            remaining: usize,
            index: u6 = 0,

            pub fn reset(self: *@This()) void {
                self.index = 0;
                self.remaining = self.size;
            }

            pub fn next(self: *@This()) ?struct { chunk: []T, offset: usize } {
                if (self.remaining == 0) return null;
                if (self.chunks.len == self.index) return null;

                const chunk_size = chunkSize(self.index);
                if (self.chunks[self.index]) |chunk| {
                    defer self.index += 1;
                    defer self.remaining -|= chunk_size;
                    return .{
                        .chunk = chunk[0..@min(chunk_size, self.remaining)],
                        .offset = self.size - self.remaining,
                    };
                } else {
                    return null;
                }
            }

            pub fn ended(self: *@This()) bool {
                return self.remaining == 0;
            }
        };

        const Iterator = struct {
            it: ChunkIterator,
            chunk: ?[]T,
            index: usize = 0,

            pub fn reset(self: *@This()) void {
                self.it.reset();
                self.chunk = if (self.it.next()) |e| e.chunk else null;
                self.index = 0;
            }

            pub fn next(self: *@This()) ?*T {
                const chunk = self.chunk orelse return null;
                defer {
                    self.index += 1;
                    if (self.index == chunk.len) {
                        self.index -= chunk.len;
                        self.chunk = if (self.it.next()) |e| e.chunk else null;
                    }
                }
                return &chunk[self.index];
            }

            pub fn ended(self: *@This()) bool {
                return self.it.ended() and self.chunk == null;
            }
        };
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

test "Xar test base 1" {
    const alloc = std.testing.allocator;

    var bytes = ArrayXar(u8, 1).init(alloc);
    defer bytes.deinit();

    try bytes.append(0);
    try bytes.append(1);
    try bytes.append(2);
    try bytes.append(3);
    try bytes.append(4);
    try std.testing.expectEqual(5, bytes.size);
    try std.testing.expectEqual(4, bytes.pop());
    try std.testing.expectEqual(3, bytes.pop());
    try std.testing.expectEqual(3, bytes.size);
    try bytes.append(3);
    try bytes.append(4);

    try std.testing.expectEqual(0, bytes.get(0));
    try std.testing.expectEqual(1, bytes.get(1));
    try std.testing.expectEqual(2, bytes.get(2));
    try std.testing.expectEqual(3, bytes.get(3));
    try std.testing.expectEqual(4, bytes.get(4));
    try std.testing.expectEqual(null, bytes.get(5));

    var it = bytes.iterator(.{});
    try std.testing.expectEqual(2, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(3, it.it.remaining);
    try std.testing.expectEqual(0, it.next().?.*);
    try std.testing.expectEqual(1, it.next().?.*);
    try std.testing.expectEqual(2, it.chunk.?.len);
    try std.testing.expectEqual(2, it.it.index);
    try std.testing.expectEqual(1, it.it.remaining);
    try std.testing.expectEqual(2, it.next().?.*);
    try std.testing.expectEqual(3, it.next().?.*);
    try std.testing.expectEqual(1, it.chunk.?.len);
    try std.testing.expectEqual(3, it.it.index);
    try std.testing.expectEqual(0, it.it.remaining);
    try std.testing.expectEqual(0, it.index);
    try std.testing.expectEqual(4, it.next().?.*);
    try std.testing.expectEqual(null, it.chunk);
    try std.testing.expectEqual(null, it.next());

    it.reset();
    try std.testing.expectEqual(2, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(3, it.it.remaining);
    try std.testing.expectEqual(0, it.next().?.*);

    try std.testing.expectEqual(4, bytes.pop());
    try std.testing.expectEqual(3, bytes.pop());
    try std.testing.expectEqual(2, bytes.pop());
    try std.testing.expectEqual(1, bytes.pop());
    try std.testing.expectEqual(0, bytes.pop());
    try std.testing.expectEqual(null, bytes.pop());

    try bytes.append(0);
    try bytes.append(1);
    try bytes.append(2);
    try bytes.append(3);
    try bytes.append(4);
    try std.testing.expectEqual(5, bytes.size);
    it = bytes.iterator(.{ .start = 2, .size = 2 });
    try std.testing.expectEqual(0, it.index);
    try std.testing.expectEqual(4, it.it.size);
    try std.testing.expectEqual(0, it.it.remaining);
    try std.testing.expectEqual(2, it.it.index);
    try std.testing.expectEqual(2, it.next().?.*);
    try std.testing.expectEqual(3, it.next().?.*);
    try std.testing.expectEqual(null, it.next());
}

test "Xar test base 2" {
    const alloc = std.testing.allocator;

    var bytes = ArrayXar(u8, 2).init(alloc);
    defer bytes.deinit();

    try bytes.append(0);
    try bytes.append(1);
    try bytes.append(2);
    try bytes.append(3);
    try bytes.append(4);
    try std.testing.expectEqual(4, bytes.pop());
    try std.testing.expectEqual(3, bytes.pop());
    try bytes.append(3);
    try bytes.append(4);

    try std.testing.expectEqual(0, bytes.get(0));
    try std.testing.expectEqual(1, bytes.get(1));
    try std.testing.expectEqual(2, bytes.get(2));
    try std.testing.expectEqual(3, bytes.get(3));
    try std.testing.expectEqual(4, bytes.get(4));
    try std.testing.expectEqual(null, bytes.get(5));

    var it = bytes.iterator(.{});
    try std.testing.expectEqual(4, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(1, it.it.remaining);
    try std.testing.expectEqual(0, it.next().?.*);
    try std.testing.expectEqual(1, it.next().?.*);
    try std.testing.expectEqual(2, it.next().?.*);
    try std.testing.expectEqual(3, it.next().?.*);
    try std.testing.expectEqual(1, it.chunk.?.len);
    try std.testing.expectEqual(2, it.it.index);
    try std.testing.expectEqual(0, it.it.remaining);
    try std.testing.expectEqual(0, it.index);
    try std.testing.expectEqual(4, it.next().?.*);
    try std.testing.expectEqual(null, it.chunk);
    try std.testing.expectEqual(null, it.next());

    it.reset();
    try std.testing.expectEqual(4, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(1, it.it.remaining);
    try std.testing.expectEqual(0, it.next().?.*);

    try std.testing.expectEqual(4, bytes.pop());
    try std.testing.expectEqual(3, bytes.pop());
    try std.testing.expectEqual(2, bytes.pop());
    try std.testing.expectEqual(1, bytes.pop());
    try std.testing.expectEqual(0, bytes.pop());
    try std.testing.expectEqual(null, bytes.pop());
}

test "Xar test base 5" {
    const alloc = std.testing.allocator;

    var bytes = ArrayXar(usize, 5).init(alloc);
    defer bytes.deinit();

    for (0..33) |i| {
        try bytes.append(i);
    }
    try std.testing.expectEqual(32, bytes.pop());
    try std.testing.expectEqual(31, bytes.pop());
    try bytes.append(31);
    try bytes.append(32);

    for (0..33) |i| {
        try std.testing.expectEqual(i, bytes.get(i));
    }
    try std.testing.expectEqual(null, bytes.get(33));

    var it = bytes.iterator(.{});
    try std.testing.expectEqual(32, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(1, it.it.remaining);
    for (0..32) |i| {
        try std.testing.expectEqual(i, it.next().?.*);
    }
    try std.testing.expectEqual(1, it.chunk.?.len);
    try std.testing.expectEqual(2, it.it.index);
    try std.testing.expectEqual(0, it.it.remaining);
    try std.testing.expectEqual(0, it.index);
    try std.testing.expectEqual(32, it.next().?.*);
    try std.testing.expectEqual(null, it.chunk);
    try std.testing.expectEqual(null, it.next());

    it.reset();
    try std.testing.expectEqual(32, it.chunk.?.len);
    try std.testing.expectEqual(1, it.it.index);
    try std.testing.expectEqual(1, it.it.remaining);
    try std.testing.expectEqual(0, it.next().?.*);

    const buf = try bytes.ownedSlice(.{});
    defer alloc.free(buf);

    for (0..33) |i| {
        const b = bytes.pop();
        try std.testing.expectEqual(32 - i, b);
        try std.testing.expectEqual(buf[32 - i], b);
    }
    try std.testing.expectEqual(null, bytes.pop());
}
