const std = @import("std");

const utils_mod = @import("utils.zig");

const term_mod = @import("term.zig");

const main_mod = @import("main.zig");
const App = main_mod.App;

pub const Schema = struct {
    pub const Author = struct {
        name: []const u8,
        email: []const u8,
        timestamp: []const u8,
    };

    pub const Committer = Author;

    pub const Change = struct {
        commit_id: []const u8,
        change_id: []const u8,
        parents: []const []const u8,
        description: []const u8,
        author: Author,
        committer: Committer,
    };

    pub const TimestampRange = struct {
        start: []const u8,
        end: []const u8,
    };

    pub const Tags = struct {
        args: ?[]const u8 = null,
    };

    pub const Operation = struct {
        id: []const u8,
        parents: []const []const u8,
        time: TimestampRange,
        description: []const u8,
        hostname: []const u8,
        username: []const u8,
        is_snapshot: bool,
        tags: Tags,
    };
};

pub const JujutsuServer = struct {
    alloc: std.mem.Allocator,
    quit: utils_mod.Fuse = .{},
    thread: std.Thread,
    requests: utils_mod.Channel(Request),

    // not owned
    events: utils_mod.Channel(App.Event),

    pub const Request = union(enum) {
        log,
        oplog,
        diff: Change,
    };

    pub const Result = union(enum) {
        ok: []u8,
        err: []u8,
    };

    pub const Response = struct {
        req: Request,
        res: Result,
    };

    pub fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(App.Event)) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        self.* = .{
            .events = events,
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

    pub fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.requests.deinit();
        defer self.thread.join();
        _ = self.quit.fuse();
        _ = self.requests.close();
    }

    fn _start(self: *@This()) void {
        self.start() catch |e| utils_mod.dump_error(e);
    }

    fn start(self: *@This()) !void {
        // - [Templating language - Jujutsu docs](https://jj-vcs.github.io/jj/latest/templates/)
        //   - [default templates](https://github.com/jj-vcs/jj/blob/main/cli/src/config/templates.toml)

        while (self.requests.wait_recv()) |req| {
            if (self.quit.check()) return;
            switch (req) {
                .log => {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "log",
                        "--template",
                        Change.Parsed.template,
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = res } } });
                },
                .oplog => {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "op",
                        "log",
                        "--template",
                        Operation.Parsed.template,
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = res } } });
                },
                .diff => |change| {
                    const stat = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "show",
                        "--stat",
                        "-r",
                        change.hash[0..],
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    defer self.alloc.free(stat);
                    const diff = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "diff",
                        "--tool",
                        "delta",
                        "-r",
                        change.hash[0..],
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    defer self.alloc.free(diff);

                    var output = std.ArrayList(u8).init(self.alloc);
                    errdefer output.deinit();
                    try output.appendSlice(stat);
                    try output.appendSlice(diff);

                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = try output.toOwnedSlice() } } });
                },
            }
        }
    }

    fn jjcall(self: *@This(), args: []const []const u8) ![]u8 {
        const alloc = self.alloc;

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
        const max_output_bytes = 1000 * 1000 * 10;
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
};

pub const Formatted = struct {
    height: u32,
    buf: []const u8,
};

const template_sep = struct {
    const sep = "-JJAZY1-";
    const escaped = escape(sep);

    fn escape(comptime str: []const u8) [str.len * 4]u8 {
        comptime {
            var buf = std.mem.zeroes([str.len * 4]u8);
            for (str, 0..) |c, i| {
                _ = std.fmt.bufPrint(buf[i * 4 ..], "\\x{x}", .{c}) catch unreachable;
            }
            return buf;
        }
    }
};

fn Template(typ: type, _template: []const u8, _sep: []const u8) type {
    return struct {
        parsed: typ,
        formatted: Formatted,
        json: []const u8,
        raw: []const u8,

        const Self = @This();
        const sep = _sep;
        const template = _template;

        pub const Iterator = struct {
            state: utils_mod.LineIterator,

            temp: std.heap.ArenaAllocator,
            scratch: std.ArrayList(u8),

            pub fn init(alloc: std.mem.Allocator, buf: []const u8) @This() {
                return .{ .temp = .init(alloc), .state = .init(buf), .scratch = .init(alloc) };
            }

            pub fn deinit(self: *@This()) void {
                self.scratch.deinit();
                self.temp.deinit();
            }

            pub fn reset(self: *@This(), buf: []const u8) void {
                self.scratch.clearRetainingCapacity();
                _ = self.temp.reset(.retain_capacity);
                self.state = .init(buf);
            }

            // .reset() invalidates all memory returned
            pub fn next(self: *@This()) !?Self {
                const start = self.state.index;

                while (self.state.next()) |line| {
                    self.scratch.clearRetainingCapacity();

                    var components = std.mem.splitScalar(u8, line, '{');
                    const node = components.next() orelse return error.ExpectedJjNode;
                    const rest = components.buffer[components.index.? - 1 ..];

                    var chunks = std.mem.splitSequence(u8, rest, sep);
                    const json = chunks.next() orelse return error.ExpectedJjazyDelim;

                    const change = std.json.parseFromSliceLeaky(typ, self.temp.allocator(), json, .{
                        .ignore_unknown_fields = true,
                        .allocate = .alloc_if_needed,
                    }) catch |e| {
                        std.log.err("{s}", .{json});
                        return e;
                    };

                    var height: u32 = 1;
                    try self.scratch.appendSlice(node);
                    try self.scratch.appendSlice(chunks.rest());
                    while (self.state.peek()) |nextline| {
                        const contains_sep = std.mem.containsAtLeast(
                            u8,
                            nextline,
                            1,
                            sep,
                        );
                        if (contains_sep) {
                            break;
                        }
                        try self.scratch.append('\n');
                        try self.scratch.appendSlice(self.state.next().?);
                        height += 1;
                    }

                    return Self{
                        .parsed = change,
                        .formatted = .{
                            .height = height,
                            .buf = try self.temp.allocator().dupe(u8, self.scratch.items),
                        },
                        .json = json,
                        .raw = self.state.buf[start..self.state.index],
                    };
                }

                return null;
            }

            pub fn ended(self: *@This()) bool {
                return self.state.ended();
            }
        };
    };
}

pub const Change = struct {
    id: Hash = [1]u8{'z'} ** 8,
    hash: Hash = [1]u8{'0'} ** 8,

    pub const Hash = [8]u8;

    pub const Parsed = Template(
        Schema.Change,
        "json(self) ++ \"" ++ template_sep.escaped ++ "\" ++ builtin_log_compact",
        template_sep.sep,
    );

    pub fn from_parsed(parsed: *const Parsed) @This() {
        var self: @This() = .{};
        @memcpy(self.id[0..], parsed.parsed.change_id[0..self.id.len]);
        @memcpy(self.hash[0..], parsed.parsed.commit_id[0..self.id.len]);
        return self;
    }

    pub fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.id, 'z');
    }
};

pub const Operation = struct {
    id: Hash = [1]u8{'0'} ** 12,

    pub const Hash = [12]u8;

    pub const Parsed = Template(
        Schema.Operation,
        "json(self) ++ \"" ++ template_sep.escaped ++ "\" ++ builtin_op_log_compact",
        template_sep.sep,
    );

    pub fn from_parsed(parsed: *const Parsed) @This() {
        var self: @This() = .{};
        @memcpy(self.id[0..], parsed.parsed.id[0..self.id.len]);
        return self;
    }

    pub fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.id, '0');
    }
};
