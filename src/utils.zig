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

pub fn CliParser(comptime T: type) type {
    return struct {
        pub const Error = error{
            MissingArgument,
            UnknownArgument,
            InvalidArgument,
            MissingSubcommand,
            UnknownSubcommand,
            UnexpectedArgument,
        } || std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error;

        pub const Parsed = struct {
            arena: *std.heap.ArenaAllocator,
            value: T,

            pub fn deinit(self: @This()) void {
                const allocator = self.arena.child_allocator;
                self.arena.deinit();
                allocator.destroy(self.arena);
            }
        };

        pub fn parse(allocator: std.mem.Allocator) !Parsed {
            var arena = try allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(allocator);
            errdefer {
                arena.deinit();
                allocator.destroy(arena);
            }

            const args = try std.process.argsAlloc(arena.allocator());
            var it = ArgsIterator{ .args = args[1..] };

            const value = try parseStruct(T, arena.allocator(), &it);

            if (it.peek()) |_| return Error.UnexpectedArgument;

            return .{
                .arena = arena,
                .value = value,
            };
        }

        const ArgsIterator = struct {
            args: []const []const u8,
            index: usize = 0,

            fn next(self: *@This()) ?[]const u8 {
                if (self.index >= self.args.len) return null;
                const arg = self.args[self.index];
                self.index += 1;
                return arg;
            }

            fn peek(self: @This()) ?[]const u8 {
                if (self.index >= self.args.len) return null;
                return self.args[self.index];
            }
        };

        fn parseStruct(comptime S: type, allocator: std.mem.Allocator, it: *ArgsIterator) Error!S {
            var result: S = undefined;
            const fields = std.meta.fields(S);

            // Init defaults
            inline for (fields) |field| {
                if (field.default_value_ptr) |ptr| {
                    const default = @as(*const field.type, @ptrCast(@alignCast(ptr))).*;
                    @field(result, field.name) = default;
                } else {
                    const info = @typeInfo(field.type);
                    if (info == .optional) {
                        @field(result, field.name) = null;
                    } else if (info == .@"union") {
                        // Subcommand placeholder, will be filled later
                    } else if (info == .bool) {
                        @field(result, field.name) = false;
                    } else {
                        // Required field, but we'll check later
                    }
                }
            }

            var seen_fields = [_]bool{false} ** fields.len;
            while (it.peek()) |arg| {
                if (std.mem.startsWith(u8, arg, "--")) {
                    _ = it.next();
                    const full_name = arg[2..];
                    if (std.mem.eql(u8, full_name, "help")) {
                        // TODO: help
                        continue;
                    }

                    var name = full_name;
                    var val_str: ?[]const u8 = null;
                    if (std.mem.indexOfScalar(u8, full_name, '=')) |eq_idx| {
                        name = full_name[0..eq_idx];
                        val_str = full_name[eq_idx + 1 ..];
                    }

                    var matched = false;
                    inline for (fields, 0..) |field, i| {
                        if (comptime @typeInfo(field.type) == .@"union") continue;
                        if (std.mem.eql(u8, field.name, name)) {
                            matched = true;
                            seen_fields[i] = true;
                            try parseField(field.type, allocator, it, &@field(result, field.name), val_str);
                            break;
                        }
                    }
                    if (!matched) return Error.UnknownArgument;
                } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                    _ = it.next();
                    const shorts = arg[1..];

                    // Check if this contains '=' for standalone value flags
                    const has_equals = std.mem.indexOfScalar(u8, shorts, '=');
                    if (has_equals) |eq_idx| if (eq_idx != 1) return Error.InvalidArgument;

                    var i_sh: usize = 0;
                    while (i_sh < shorts.len) : (i_sh += 1) {
                        const sh = shorts[i_sh];
                        var matched = false;
                        inline for (fields, 0..) |field, i| {
                            // options not supported on unions yet.
                            if (comptime @typeInfo(field.type) == .@"union") continue;
                            if (comptime !@hasDecl(S, "options")) continue;
                            if (comptime !@hasField(@TypeOf(S.options), field.name)) continue;
                            const opt = @field(S.options, field.name);
                            if (comptime !@hasField(@TypeOf(opt), "sh")) continue;

                            if (opt.sh == sh) {
                                matched = true;
                                seen_fields[i] = true;

                                if (@typeInfo(field.type) == .bool) {
                                    @field(result, field.name) = true;
                                } else {
                                    // Non-boolean flag: must be standalone
                                    if (i_sh != 0) return Error.InvalidArgument;

                                    const p = &@field(result, field.name);
                                    if (has_equals) |_| {
                                        try parseField(field.type, allocator, it, p, shorts[2..]);
                                        i_sh = shorts.len; // done
                                    } else {
                                        if (shorts.len != 1) return Error.InvalidArgument;
                                        try parseField(field.type, allocator, it, p, null);
                                    }
                                }
                                break;
                            }
                        }
                        if (!matched) return Error.UnknownArgument;
                    }
                } else {
                    // Try to match subcommand
                    var found_subcommand = false;
                    inline for (fields, 0..) |field, i| {
                        const info = @typeInfo(field.type);
                        if (!(info == .@"union" and info.@"union".tag_type != null)) continue;
                        const Tag = info.@"union".tag_type.?;
                        inline for (std.meta.fields(Tag)) |tag_field| {
                            if (std.mem.eql(u8, tag_field.name, arg)) {
                                _ = it.next();
                                found_subcommand = true;
                                seen_fields[i] = true;
                                const InnterT = std.meta.TagPayload(field.type, @field(Tag, tag_field.name));
                                const sub_val = try parseStruct(InnterT, allocator, it);
                                @field(result, field.name) = @unionInit(field.type, tag_field.name, sub_val);
                                break;
                            }
                        }
                    }

                    if (!found_subcommand) {
                        // Positional?
                        var found_positional = false;
                        inline for (fields, 0..) |field, i| {
                            // Skip fields that are explicitly configured as options/flags?
                            // Actually, let's just take the next un-seen field that isn't a union (subcommand)
                            const info = @typeInfo(field.type);
                            if (comptime info == .@"union") continue;

                            if (!found_positional and !seen_fields[i]) {
                                _ = it.next();
                                found_positional = true;
                                seen_fields[i] = true;
                                try parseField(field.type, allocator, it, &@field(result, field.name), arg);
                                break;
                            }
                        }

                        if (!found_positional) {
                            return Error.UnknownSubcommand;
                        }
                    }
                }
            }

            // check required
            inline for (fields, 0..) |field, i| {
                if (field.default_value_ptr != null) continue;
                const info = @typeInfo(field.type);
                if (!(info != .optional and info != .bool and info != .@"union")) continue;

                if (!seen_fields[i]) {
                    return Error.MissingArgument;
                }
            }

            return result;
        }

        fn parseField(comptime FieldType: type, allocator: std.mem.Allocator, it: *ArgsIterator, ptr: *FieldType, val_str: ?[]const u8) Error!void {
            const info = @typeInfo(FieldType);
            switch (info) {
                .bool => {
                    if (val_str) |s| {
                        if (std.mem.eql(u8, s, "true")) {
                            ptr.* = true;
                        } else if (std.mem.eql(u8, s, "false")) {
                            ptr.* = false;
                        } else {
                            return Error.InvalidArgument;
                        }
                    } else {
                        ptr.* = true;
                    }
                },
                .int => {
                    const arg = val_str orelse it.next() orelse return Error.MissingArgument;
                    ptr.* = try std.fmt.parseInt(FieldType, arg, 0);
                },
                .float => {
                    const arg = val_str orelse it.next() orelse return Error.MissingArgument;
                    ptr.* = try std.fmt.parseFloat(FieldType, arg);
                },
                .pointer => |ptr_info| {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        const arg = val_str orelse it.next() orelse return Error.MissingArgument;
                        ptr.* = try allocator.dupe(u8, arg);
                    } else {
                        @compileError("Unsupported pointer type: " ++ @typeName(FieldType));
                    }
                },
                .optional => |opt_info| {
                    var val: opt_info.child = undefined;
                    try parseField(opt_info.child, allocator, it, &val, val_str);
                    ptr.* = val;
                },
                else => @compileError("Unsupported type: " ++ @typeName(FieldType)),
            }
        }
    };
}

const PtrFollow = enum { disabled, ptr_as_usize, follow };
const AutoHashArgs = struct {
    pointer_hashing: PtrFollow = .disabled,
};

// TODO: maybe this function is not required. std has something similar std.hash.autoHashStrat(&hasher, k, .DeepRecursive)
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
                if (std.mem.eql(u8, @tagName(std.meta.activeTag(a)), field.name)) {
                    if (!auto_eql(@field(a, field.name), @field(b, field.name), v)) return false;
                }
            }
            return true;
        },
        .void => return true,
        .optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return auto_eql(a.?, b.?, v);
        },
        .pointer => |p| switch (p.size) {
            .one => switch (comptime v.pointer_eq) {
                .disabled => @compileError("pointer eq is disabled"),
                .follow => return auto_eql(a.*, b.*, v),
                .ptr_as_usize => return auto_eql(@intFromPtr(a), @intFromPtr(b), v),
            },
            .slice => switch (comptime v.pointer_eq) {
                .disabled => @compileError("pointer eq is disabled"),
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
    file_logs: bool = false,
    console_logs: bool = true,

    pub const Writer = std.io.Writer(*const @This(), anyerror, @This().write);

    pub var logger = @This(){};
    pub var writer = Writer{ .context = &logger };

    pub fn init(self: *@This(), v: struct {
        path: ?[]const u8 = null,
        allow_fail: bool = false,
        console_logs: bool = true,
    }) !void {
        if (v.path) |path| self.path = path;
        const file = std.fs.cwd().createFile(self.path, .{}) catch |e| {
            if (v.allow_fail) {
                self.file_logs = false;
                return;
            }
            return e;
        };
        errdefer file.close();

        const stat = try file.stat();
        try file.seekTo(stat.size);

        self.file = file;
        self.file_logs = true;
        self.console_logs = v.console_logs;
    }

    pub fn deinit(self: *@This()) void {
        if (self.file) |file| file.close();
        self.file = null;
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
        if (self.console_logs) {
            std.debug.print(format, args);
        }

        if (!self.file_logs) {
            return;
        }
        if (self.file == null) {
            std.debug.print("File is closed\n", .{});
            std.debug.print(format, args);
            return;
        }

        self.file.?.writer().print(format, args) catch |err| {
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

pub fn DllLruCache(K: type, V: type, comptime v: struct { ptr: PtrFollow = .disabled }) type {
    return struct {
        first: ?K,
        last: ?K,
        map: Map,

        const Entry = struct {
            val: V,
            next: ?K,
            prev: ?K,
        };
        const Map = std.HashMap(K, Entry, struct {
            pub fn hash(self: @This(), s: K) u64 {
                _ = self;
                var hasher = std.hash.Wyhash.init(0);
                hash_update(&hasher, s, .{ .pointer_hashing = v.ptr });
                return hasher.final();
            }
            pub fn eql(self: @This(), a: K, b: K) bool {
                _ = self;
                return auto_eql(a, b, .{ .pointer_eq = v.ptr });
            }
        }, std.hash_map.default_max_load_percentage);

        const PopEntry = struct { key: K, val: V };
        pub const GetOrPutEntry = struct { found_existing: bool, key: *const K, val: *V };

        pub const Op = enum { touch, peek };

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .first = null,
                .last = null,
                .map = Map.init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.map.deinit();
        }

        pub fn pop(self: *@This()) ?PopEntry {
            if (self.first) |first| {
                const val = self.remove(first).?;
                return .{ .key = first, .val = val };
            } else {
                return null;
            }
        }

        pub fn retaining_pop(self: *@This(), n: u32) ?PopEntry {
            if (self.map.count() > n) {
                return self.pop();
            } else {
                return null;
            }
        }

        pub fn remove(self: *@This(), key: K) ?V {
            const curr = self.map.fetchRemove(key) orelse return null;
            const entry = curr.value;

            if (entry.prev) |prev_key| {
                const prev = self.map.getPtr(prev_key).?;
                prev.next = entry.next;
            } else {
                self.first = entry.next;
            }
            if (entry.next) |next_key| {
                const next = self.map.getPtr(next_key).?;
                next.prev = entry.prev;
            } else {
                self.last = entry.prev;
            }

            return entry.val;
        }

        fn touch(self: *@This(), key: K, entry: *Entry) void {
            // if this is the last element, we don't need to change anything
            if (self.last) |last_key| if (auto_eql(key, last_key, .{ .pointer_eq = v.ptr })) {
                return;
            };

            if (entry.prev) |prev_key| {
                const prev = self.map.getPtr(prev_key).?;
                prev.next = entry.next;
            } else {
                self.first = entry.next;
            }
            if (entry.next) |next_key| {
                const next = self.map.getPtr(next_key).?;
                next.prev = entry.prev;
            }
            if (self.last) |last_key| {
                const last = self.map.getPtr(last_key).?;
                last.next = key;
            }

            entry.prev = self.last;
            entry.next = null;
            self.last = key;
        }

        pub fn get(self: *@This(), key: K, op: Op) ?*V {
            switch (op) {
                .touch => {
                    const entry = self.map.getEntry(key) orelse return null;
                    self.touch(entry.key_ptr.*, entry.value_ptr);
                    return &entry.value_ptr.val;
                },
                .peek => {
                    const entry = self.map.getPtr(key) orelse return null;
                    return &entry.val;
                },
            }
        }

        pub fn getOrPut(self: *@This(), key: K) !GetOrPutEntry {
            const result = try self.map.getOrPut(key);

            if (result.found_existing) {
                self.touch(result.key_ptr.*, result.value_ptr);
            } else {
                if (self.last) |last_key| {
                    self.map.getPtr(last_key).?.next = key;
                } else {
                    self.first = key;
                }
                result.value_ptr.prev = self.last;
                result.value_ptr.next = null;
                self.last = key;
            }

            return .{ .found_existing = result.found_existing, .key = result.key_ptr, .val = &result.value_ptr.val };
        }

        pub fn put(self: *@This(), key: K, val: V) !void {
            const e = try self.getOrPut(key);
            if (e.found_existing) {
                return error.FoundExisting;
            } else {
                e.val.* = val;
            }
        }
    };
}

pub fn MaxHeap(T: type, Ctx: type) type {
    return struct {
        alloc: std.mem.Allocator,
        ctx: Ctx,
        buf: []T,
        capacity: usize,

        pub fn init(alloc: std.mem.Allocator, ctx: Ctx) @This() {
            return .{
                .alloc = alloc,
                .ctx = ctx,
                .buf = &.{},
                .capacity = 0,
            };
        }

        pub fn from(alloc: std.mem.Allocator, ctx: Ctx, buf: []T) @This() {
            var self = @This(){ .alloc = alloc, .ctx = ctx, .buf = buf, .capacity = buf.len };
            if (self.buf.len == 0) return self;
            const n = (self.buf.len - 1) / 2;
            for (0..n + 1) |i| {
                self.heapify(n - i);
            }
        }

        pub fn deinit(self: *@This()) void {
            defer self.buf = &.{};
            defer self.capacity = 0;
            var buf = self.buf;
            buf.len = self.capacity;
            self.alloc.free(buf);
        }

        fn heapify(self: *@This(), i: usize) void {
            var index = i;
            while (true) {
                var largest = index;
                const left = 2 * index + 1;
                const right = 2 * index + 2;

                if (left < self.buf.len and self.ctx.lessThan(&self.buf[largest], &self.buf[left])) {
                    largest = left;
                }
                if (right < self.buf.len and self.ctx.lessThan(&self.buf[largest], &self.buf[right])) {
                    largest = right;
                }

                if (largest == index) {
                    break;
                }

                std.mem.swap(T, &self.buf[index], &self.buf[largest]);
                index = largest;
            }
        }

        fn grow(self: *@This(), num: usize) !void {
            std.debug.assert(self.capacity < num);
            const old = self.buf;
            const buf = try self.alloc.alloc(T, num);
            @memcpy(buf[0..old.len], old);
            self.buf = buf[0..old.len];
            self.capacity = buf.len;
            self.alloc.free(old);
        }

        fn addOne(self: *@This()) !*T {
            if (self.buf.len == self.capacity) {
                const new_cap = if (self.capacity == 0) 16 else self.capacity * 2;
                try self.grow(new_cap);
            }
            self.buf.len += 1;
            return &self.buf[self.buf.len - 1];
        }

        pub fn push(self: *@This(), t: T) !void {
            const last = try self.addOne();
            last.* = t;

            var index = self.buf.len - 1;
            while (true) {
                const parent = (index -| 1) / 2;
                if (index == 0 or self.ctx.lessThan(&self.buf[parent], &self.buf[index])) {
                    break;
                }
                std.mem.swap(T, &self.buf[index], &self.buf[parent]);
                index = parent;
            }
        }

        // caller is not allowed to modify it in a way that changes it's 'max-ness'
        pub fn peek(self: *@This()) ?*T {
            if (self.buf.len == 0) return null;
            return &self.buf[0];
        }

        pub fn pop(self: *@This()) ?T {
            if (self.buf.len == 0) return null;
            if (self.buf.len == 1) {
                defer self.buf.len -= 1;
                return self.buf[self.buf.len - 1];
            } else {
                const t = self.buf[0];
                self.buf[0] = self.buf[self.buf.len - 1];
                self.buf.len -= 1;
                self.heapify(0);
                return t;
            }
        }
    };
}

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

            while (self.pinned.waiting.fetchAdd(0, .monotonic) > 0) {
                self.pinned.notify.signal();
                // timeouts are fine here.
                self.pinned.notify.timedWait(&self.pinned.lock, std.time.ns_per_us * 100) catch {};
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

        pub fn swap_remove(self: *@This(), index: usize) ?T {
            if (self.size > index) {
                if (index == self.size - 1) {
                    return self.pop();
                } else {
                    defer self.size -= 1;
                    const last = self.getPtr(self.size - 1).?;
                    const curr = self.getPtr(index).?;
                    defer curr.* = last.*;
                    return curr.*;
                }
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

pub const Command = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    args: std.ArrayList([]const u8),

    pub const Result = struct {
        errored: bool,
        err: []u8,
        out: []u8,

        pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
            alloc.free(self.err);
            alloc.free(self.out);
        }
    };

    pub fn init(alloc: std.mem.Allocator) Command {
        return .{
            .alloc = alloc,
            .arena = std.heap.ArenaAllocator.init(alloc),
            .args = std.ArrayList([]const u8).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.args.deinit();
        self.arena.deinit();
    }

    pub fn arg(self: *@This(), val: []const u8) !*@This() {
        const dupe = try self.arena.allocator().dupe(u8, val);
        try self.args.append(dupe);
        return self;
    }

    pub fn add_args(self: *@This(), args: []const []const u8) !*@This() {
        for (args) |a| {
            _ = try self.arg(a);
        }
        return self;
    }

    pub fn exec_status(self: *@This(), alloc: std.mem.Allocator) !Result {
        var child = std.process.Child.init(self.args.items, self.alloc);
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
        var poller = std.io.poll(self.alloc, enum { stdout, stderr }, .{
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

        const err_fifo = poller.fifo(.stderr);
        const err_out = err_fifo.buf[err_fifo.head..][0..err_fifo.count];

        var err_buf = std.ArrayList(u8).init(alloc);
        errdefer err_buf.deinit();
        var errored: bool = false;
        if (err_fifo.count > 0) {
            std.log.err("{s}", .{err_out});
            try err_buf.writer().print("{s}\n", .{err_out});
        }

        switch (err) {
            .Exited => |e| {
                if (e != 0) {
                    std.log.err("exited with code: {}", .{e});
                    try err_buf.writer().print("exited with code: {}\n", .{e});
                    errored = true;
                }
            },
            // .Signal => |code| {},
            // .Stopped => |code| {},
            // .Unknown => |code| {},
            else => |e| {
                std.log.err("exited with code: {}", .{e});
                try err_buf.writer().print("exited with code: {}\n", .{e});
                errored = true;
            },
        }

        const out_fifo = poller.fifo(.stdout);
        const out_out = out_fifo.buf[out_fifo.head..][0..out_fifo.count];

        var out_buf = std.ArrayList(u8).init(alloc);
        errdefer out_buf.deinit();
        if (out_fifo.count > 0) {
            std.log.debug("{s}", .{out_out});
            try out_buf.appendSlice(out_out);
        }

        return .{
            .errored = errored,
            .err = try err_buf.toOwnedSlice(),
            .out = try out_buf.toOwnedSlice(),
        };
    }

    pub fn exec_capture(self: *@This(), alloc: std.mem.Allocator, temp: std.mem.Allocator) ![]u8 {
        var child = std.process.Child.init(self.args.items, temp);
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
        const max_output_bytes = 1000 * 1000 * 10;
        var poller = std.io.poll(temp, enum { stdout, stderr }, .{
            .stdout = stdout,
            .stderr = stderr,
        });
        defer poller.deinit();

        // TODO: maybe get a small threadpool + channels + arrays to capture this output
        //  asynchronously and use it on the renderer
        // TODO: also cache the parsed output instead of parsing it every time we want to use (where possible)
        while (try poller.poll()) {
            if (poller.fifo(.stdout).count > max_output_bytes)
                return error.StdoutStreamTooLong;
            if (poller.fifo(.stderr).count > max_output_bytes)
                return error.StderrStreamTooLong;
        }

        const err = try child.wait();
        blk: {
            var err_buf = std.ArrayList(u8).init(temp);
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
            return error.ExternalCommandError;
        }

        const out_fifo = poller.fifo(.stdout);
        return try alloc.dupe(u8, out_fifo.buf[out_fifo.head..][0..out_fifo.count]);
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

test "basic insertion and ordering" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(u32, u32, .{});
    var cache = Cache.init(alloc);
    defer cache.deinit();

    // Insert elements
    {
        const r1 = try cache.getOrPut(1);
        r1.val.* = 10;
        const r2 = try cache.getOrPut(2);
        r2.val.* = 20;
        const r3 = try cache.getOrPut(3);
        r3.val.* = 30;
    }

    try std.testing.expectEqual(@as(?u32, 1), cache.first);
    try std.testing.expectEqual(@as(?u32, 3), cache.last);

    // Check values
    try std.testing.expectEqual(10, (cache.get(1, .peek).?).*);
    try std.testing.expectEqual(20, (cache.get(2, .peek).?).*);
    try std.testing.expectEqual(30, (cache.get(3, .peek).?).*);
}

test "touch reorders entries (LRU behavior)" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(u32, []const u8, .{});
    var cache = Cache.init(alloc);
    defer cache.deinit();

    // insert 1,2,3
    _ = try cache.getOrPut(1);
    _ = try cache.getOrPut(2);
    _ = try cache.getOrPut(3);

    // Initially: first=1, last=3
    try std.testing.expectEqual(@as(?u32, 1), cache.first);
    try std.testing.expectEqual(@as(?u32, 3), cache.last);

    // touch(1) should move 1 to last
    _ = cache.get(1, .touch);
    try std.testing.expectEqual(@as(?u32, 2), cache.first);
    try std.testing.expectEqual(@as(?u32, 1), cache.last);
}

test "remove maintains linked list integrity" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(u32, u32, .{});
    var cache = Cache.init(alloc);
    defer cache.deinit();

    _ = try cache.getOrPut(1);
    _ = try cache.getOrPut(2);
    _ = try cache.getOrPut(3);

    // Remove middle element
    const removed = cache.remove(2);
    try std.testing.expect(removed != null);
    try std.testing.expectEqual(@as(?u32, 1), cache.first);
    try std.testing.expectEqual(@as(?u32, 3), cache.last);

    // Removing first
    _ = cache.remove(1);
    try std.testing.expectEqual(@as(?u32, 3), cache.first);

    // Removing last (remaining one)
    _ = cache.remove(3);
    try std.testing.expectEqual(@as(?u32, null), cache.first);
    try std.testing.expectEqual(@as(?u32, null), cache.last);
}

test "pop removes from head" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(u32, []const u8, .{});
    var cache = Cache.init(alloc);
    defer cache.deinit();

    {
        _ = try cache.getOrPut(1);
        _ = try cache.getOrPut(2);
        _ = try cache.getOrPut(3);
    }

    const popped1 = cache.pop().?;
    try std.testing.expectEqual(@as(u32, 1), popped1.key);
    try std.testing.expectEqual(@as(?u32, 2), cache.first);

    const popped2 = cache.pop().?;
    try std.testing.expectEqual(@as(u32, 2), popped2.key);
    try std.testing.expectEqual(@as(?u32, 3), cache.first);

    const popped3 = cache.pop().?;
    try std.testing.expectEqual(@as(u32, 3), popped3.key);
    try std.testing.expectEqual(@as(?u32, null), cache.first);
}

test "retaining_pop keeps only n newest" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(u32, u32, .{});
    var cache = Cache.init(alloc);
    defer cache.deinit();

    _ = try cache.getOrPut(1);
    _ = try cache.getOrPut(2);
    _ = try cache.getOrPut(3);
    _ = try cache.getOrPut(4);

    // retain 2 newest → should pop oldest until count == 2
    while (cache.retaining_pop(2)) |_| {}
    try std.testing.expectEqual(@as(usize, 2), cache.map.count());

    // first should be 3, last should be 4
    try std.testing.expectEqual(@as(?u32, 3), cache.first);
    try std.testing.expectEqual(@as(?u32, 4), cache.last);
}

test "pointer equality variant works" {
    const alloc = std.testing.allocator;

    const Cache = DllLruCache(*u32, u32, .{ .ptr = .follow });
    var cache = Cache.init(alloc);
    defer cache.deinit();

    var a: u32 = 42;
    var b: u32 = 43;
    var c: u32 = 44;

    {
        const r = try cache.getOrPut(&a);
        r.val.* = 1;
        _ = try cache.getOrPut(&b);
        _ = try cache.getOrPut(&c);
    }

    // Touching &a moves it to tail
    _ = cache.get(&a, .touch);
    try std.testing.expectEqual(@as(?*u32, &b), cache.first);
    try std.testing.expectEqual(@as(?*u32, &a), cache.last);
}

test "Clap basic flag and option" {
    const Cli = struct {
        verbose: bool = false,
        port: u16 = 8080,
        name: []const u8 = "default",

        pub const options = .{
            .verbose = .{ .sh = 'v' },
            .port = .{ .sh = 'p' },
        };
    };

    const alloc = std.testing.allocator;

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "--verbose", "--port", "9090", "--name", "foo" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        defer alloc.free(res.name);
        try std.testing.expect(res.verbose);
        try std.testing.expectEqual(@as(u16, 9090), res.port);
        try std.testing.expectEqualStrings("foo", res.name);
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "-p", "7070" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expect(res.verbose);
        try std.testing.expectEqual(@as(u16, 7070), res.port);
        try std.testing.expectEqualStrings("default", res.name);
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-vp", "7070" } };
        try std.testing.expectError(CliParser(Cli).Error.InvalidArgument, CliParser(Cli).parseStruct(Cli, alloc, &it));
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{"-p=7070"} };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expectEqual(@as(u16, 7070), res.port);
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{"-p7070"} };
        try std.testing.expectError(CliParser(Cli).Error.InvalidArgument, CliParser(Cli).parseStruct(Cli, alloc, &it));
    }
}

test "Clap subcommands" {
    const Cli = struct {
        verbose: bool = false,
        command: union(enum) {
            init: struct {
                force: bool = false,
                pub const options = .{ .force = .{ .sh = 'f' } };
            },
            run: struct {
                port: u16 = 8080,
            },
        },

        pub const options = .{
            .verbose = .{ .sh = 'v' },
        };
    };

    const alloc = std.testing.allocator;

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "init", "-f" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expect(res.verbose);
        switch (res.command) {
            .init => |s| try std.testing.expect(s.force),
            else => return error.TestFailed,
        }
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "run", "--port", "1234" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expect(!res.verbose);
        switch (res.command) {
            .run => |s| try std.testing.expectEqual(@as(u16, 1234), s.port),
            else => return error.TestFailed,
        }
    }
}

test "Clap user Cli struct" {
    const Cli = struct {
        verbose: bool = false,
        extra_verbose: bool = false,
        config: ?[]const u8 = null,
        command: union(enum) {
            init: struct {
                force: bool = false,
                pub const options = .{ .force = .{ .sh = 'f' } };
            },
            run: struct {
                port: u16 = 8080,
            },
        },

        pub const description = "App description";
        pub const options = .{
            .verbose = .{ .sh = 'v', .desc = "Verbose mode" },
            .extra_verbose = .{ .sh = 'e', .desc = "extra verbose mode" },
            .config = .{ .sh = 'c', .desc = "Config path" },
        };
    };

    const alloc = std.testing.allocator;

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-ve", "init" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expect(res.verbose);
        try std.testing.expect(res.extra_verbose);
        try std.testing.expect(res.config == null);
        switch (res.command) {
            .init => |s| try std.testing.expect(!s.force),
            else => return error.TestFailed,
        }
    }
    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "init", "-f" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        try std.testing.expect(res.verbose);
        try std.testing.expect(res.config == null);
        switch (res.command) {
            .init => |s| try std.testing.expect(s.force),
            else => return error.TestFailed,
        }
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "--config=test.json", "run", "--port", "9000" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        defer if (res.config) |c| alloc.free(c);
        try std.testing.expect(!res.verbose);
        try std.testing.expectEqualStrings("test.json", res.config.?);
        switch (res.command) {
            .run => |s| try std.testing.expectEqual(@as(u16, 9000), s.port),
            else => return error.TestFailed,
        }
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-vc=config.json", "init" } };
        try std.testing.expectError(CliParser(Cli).Error.InvalidArgument, CliParser(Cli).parseStruct(Cli, alloc, &it));
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-vcconfig.json", "init" } };
        try std.testing.expectError(CliParser(Cli).Error.InvalidArgument, CliParser(Cli).parseStruct(Cli, alloc, &it));
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "-cconfig.json" } };
        try std.testing.expectError(CliParser(Cli).Error.InvalidArgument, CliParser(Cli).parseStruct(Cli, alloc, &it));
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "-c=config.json", "init" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        defer if (res.config) |c| alloc.free(c);
        try std.testing.expect(res.verbose);
        try std.testing.expectEqualStrings("config.json", res.config.?);
        switch (res.command) {
            .init => |s| try std.testing.expect(!s.force),
            else => return error.TestFailed,
        }
    }

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "-v", "-c", "config.json", "init" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        defer if (res.config) |c| alloc.free(c);
        try std.testing.expect(res.verbose);
        try std.testing.expectEqualStrings("config.json", res.config.?);
        switch (res.command) {
            .init => |s| try std.testing.expect(!s.force),
            else => return error.TestFailed,
        }
    }
}

test "Clap positional arguments" {
    const Cli = struct {
        input: []const u8,
        output: []const u8,
        verbose: bool = false,
        pub const options = .{ .verbose = .{ .sh = 'v' } };
    };

    const alloc = std.testing.allocator;

    {
        var it = CliParser(Cli).ArgsIterator{ .args = &[_][]const u8{ "in.txt", "out.txt", "-v" } };
        const res = try CliParser(Cli).parseStruct(Cli, alloc, &it);
        defer alloc.free(res.input);
        defer alloc.free(res.output);
        try std.testing.expectEqualStrings("in.txt", res.input);
        try std.testing.expectEqualStrings("out.txt", res.output);
        try std.testing.expect(res.verbose);
    }
}
