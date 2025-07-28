const std = @import("std");

const utils_mod = @import("utils.zig");

const term_mod = @import("term.zig");

const main_mod = @import("main.zig");
const App = main_mod.App;

pub const JujutsuServer = struct {
    alloc: std.mem.Allocator,
    quit: utils_mod.Fuse = .{},
    thread: std.Thread,
    requests: utils_mod.Channel(Request),

    // not owned
    events: utils_mod.Channel(App.Event),

    pub const Request = union(enum) {
        status,
        diff: Change,
        new: Change,
        edit: Change,
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
                .status => {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "log",
                        // "--template",
                        // "builtin_log_compact ++ json(self)",
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
                .new => |change| {
                    // TODO: allow more parents
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "new",
                        change.id[0..],
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };

                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = res } } });
                },
                .edit => |change| {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "edit",
                        change.id[0..],
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };

                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = res } } });
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
};

pub const ChangeIterator = struct {
    state: utils_mod.LineIterator,

    temp: std.heap.ArenaAllocator,
    scratch: std.ArrayListUnmanaged(u8) = .{},

    pub fn init(alloc: std.mem.Allocator, buf: []const u8) @This() {
        return .{ .temp = .init(alloc), .state = .init(buf) };
    }

    pub fn deinit(self: *@This()) void {
        self.temp.deinit();
    }

    pub fn reset(self: *@This(), buf: []const u8) void {
        self.scratch.clearRetainingCapacity();
        self.state = .init(buf);
    }

    pub fn next(self: *@This()) !?ChangeEntry {
        const start = self.state.index;
        while (self.state.next()) |line| {
            self.scratch.clearRetainingCapacity();
            var tokens = try term_mod.TermStyledGraphemeIterator.init(line);

            while (try tokens.next()) |token| {
                if (token.codepoint != null) {
                    continue;
                }

                try self.scratch.appendSlice(self.temp.allocator(), token.grapheme);
            }

            const hash = blk: {
                var chunks = std.mem.splitBackwardsScalar(u8, self.scratch.items, ' ');
                while (chunks.next()) |chunk| {
                    if (chunk.len == 8) {
                        break :blk chunk;
                    }
                }
                return error.ErrorParsingChangeHash;
            };
            const id = blk: {
                var chunks = std.mem.splitScalar(u8, self.scratch.items, ' ');
                while (chunks.next()) |chunk| {
                    if (chunk.len == 8) {
                        break :blk chunk;
                    }
                }
                return error.ErrorParsingChangeId;
            };

            var change = std.mem.zeroes(Change);
            @memcpy(change.id[0..], id);
            @memcpy(change.hash[0..], hash);

            // description line
            _ = self.state.next();
            // json line
            // _ = self.state.next();

            return .{ .change = change, .buf = self.state.buf[start..self.state.index] };
        }

        return null;
    }

    pub fn ended(self: *@This()) bool {
        return self.state.ended();
    }

    pub const ChangeEntry = struct {
        buf: []const u8,
        change: Change,
    };
};

pub const Change = struct {
    id: Hash = [1]u8{'z'} ** 8,
    hash: Hash = [1]u8{0} ** 8,

    pub const Hash = [8]u8;

    pub fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.hash, 0);
    }
};
