const std = @import("std");
const builtin = @import("builtin");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const lay_mod = @import("lay.zig");
const Vec2 = lay_mod.Vec2;

const term_mod = @import("term.zig");
const codes = term_mod.codes;

const jj_mod = @import("jj.zig");

const Surface = struct {
    border: bool = false,
    y: i32 = 0,
    x: i32 = 0,
    y_scroll: i32 = 0,
    region: lay_mod.Region,
    term: *term_mod.Term,

    const Split = enum {
        none,
        gap,
        border,
    };

    fn init(term: *term_mod.Term, v: struct { origin: ?Vec2 = null, size: ?Vec2 = null }) @This() {
        return .{
            .term = term,
            .region = .{
                .origin = v.origin orelse term.screen.origin,
                .size = v.size orelse term.screen.size,
            },
        };
    }

    fn size(self: *const @This()) Vec2 {
        return self.region.size;
    }

    fn clear(self: *@This()) !void {
        try self.term.clear_region(self.region);
    }

    fn is_full(self: *@This()) bool {
        return !self.region.contains_y(self.region.origin.y + self.y);
    }

    fn new_line(self: *@This()) !void {
        try self.draw_buf("\n\n");
    }

    fn draw_border(self: *@This(), borders: anytype) !void {
        self.border = true;
        try self.term.draw_border(self.region, borders);
    }

    fn apply_style(self: *@This(), style: term_mod.TermStyledGraphemeIterator.Style) !void {
        try style.write_to(self.term.writer());
    }

    fn draw_border_heading(self: *@This(), heading: []const u8) !void {
        _ = try self.term.draw_buf(heading, self.region.clamp(.{
            .origin = .{
                .x = self.region.origin.x + 1,
                .y = self.region.origin.y,
            },
            .size = .{
                .x = self.region.size.x - 2,
                .y = self.region.size.y,
            },
        }), 0, 0, 0);
    }

    fn draw_buf(self: *@This(), buf: []const u8) !void {
        if (self.is_full()) return;

        self.y = @max(0, self.y);
        self.y_scroll = @max(0, self.y_scroll);
        const res = try self.term.draw_buf(
            buf,
            self.region.border_sub(.splat(@intFromBool(self.border))),
            self.y,
            self.x,
            cast(u32, self.y_scroll),
        );
        self.y = res.y;
        self.x = res.x;
        self.y_scroll -= res.skipped;
    }

    fn split_x(self: *@This(), x: i32, split: Split) !@This() {
        const regions = self.region.border_sub(.splat(@intFromBool(self.border))).split_x(x, split != .none);

        if (split == .border) {
            try self.term.draw_split(self.region, regions.split, null, self.border);
        }

        const other = @This(){
            .term = self.term,
            .region = regions.right,
        };

        self.* = @This(){
            .term = self.term,
            .region = regions.left,
        };

        return other;
    }

    fn split_y(self: *@This(), y: i32, split: Split) !@This() {
        const regions = self.region.border_sub(.splat(@intFromBool(self.border))).split_y(y, split != .none);

        if (split == .border) {
            try self.term.draw_split(self.region, null, regions.split, self.border);
        }

        const other = @This(){
            .term = self.term,
            .region = regions.bottom,
        };

        self.* = @This(){
            .term = self.term,
            .region = regions.top,
        };

        return other;
    }
};

pub const TextInput = struct {
    cursor: u32 = 0,
    text: std.ArrayList(u8),

    fn init(alloc: std.mem.Allocator) @This() {
        return .{ .text = .init(alloc) };
    }

    fn deinit(self: *@This()) void {
        self.text.deinit();
    }

    fn reset(self: *@This()) void {
        self.cursor = 0;
        self.text.clearRetainingCapacity();
    }

    fn left(self: *@This()) void {
        self.cursor -|= 1;
    }

    fn right(self: *@This()) void {
        self.cursor += 1;
        if (self.cursor > self.text.items.len) {
            self.cursor = cast(u32, self.text.items.len);
        }
    }

    fn left_word(self: *@This()) void {
        self.left();
        while (true) {
            if (' ' == self.peek_back() orelse return) {
                return;
            } else {
                self.left();
            }
        }
    }

    fn right_word(self: *@This()) void {
        self.right();
        while (true) {
            if (' ' == self.peek() orelse return) {
                return;
            } else {
                self.right();
            }
        }
    }

    fn write(self: *@This(), byte: u8) !void {
        try self.text.insert(self.cursor, byte);
        self.cursor += 1;
    }

    fn peek(self: *@This()) ?u8 {
        if (self.text.items.len > self.cursor) {
            return self.text.items[self.cursor];
        } else {
            return null;
        }
    }

    fn peek_back(self: *@This()) ?u8 {
        if (self.text.items.len >= self.cursor and self.cursor > 0) {
            return self.text.items[self.cursor - 1];
        } else {
            return null;
        }
    }

    fn back(self: *@This()) ?u8 {
        if (self.text.items.len >= self.cursor and self.cursor > 0) {
            defer self.cursor -= 1;
            return self.text.orderedRemove(self.cursor - 1);
        } else {
            return null;
        }
    }

    fn draw(self: *const @This(), surf: *Surface) !void {
        try surf.draw_buf(self.text.items[0..self.cursor]);
        try surf.apply_style(.invert);
        if (self.text.items.len > self.cursor) {
            try surf.draw_buf(self.text.items[self.cursor..][0..1]);
        } else {
            try surf.draw_buf(" ");
        }
        try surf.apply_style(.reset);
        if (self.text.items.len > self.cursor + 1) {
            try surf.draw_buf(self.text.items[self.cursor + 1 ..]);
        }
    }
};

pub const App = struct {
    term: term_mod.Term,

    quit: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),

    jj: *jj_mod.JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    x_split: f32 = 0.55,
    y: i32 = 0,
    status: []const u8,
    changes: jj_mod.ChangeIterator,
    diffcache: DiffCache,
    focused_change: jj_mod.Change = .{},
    command_text: TextInput,

    focus: enum {
        status,
        diff,
        command,
    } = .status,

    pub const Event = union(enum) {
        sigwinch,
        rerender,
        quit,
        input: term_mod.TermInputIterator.Input,
        jj: jj_mod.JujutsuServer.Response,
        err: anyerror,
    };

    const CachedDiff = struct {
        y: i32 = 0,
        diff: ?[]const u8 = null,
    };
    const DiffCache = std.HashMap([8]u8, CachedDiff, struct {
        pub fn hash(self: @This(), s: [8]u8) u64 {
            _ = self;
            return std.hash_map.StringContext.hash(.{}, s[0..]);
        }
        pub fn eql(self: @This(), a: [8]u8, b: [8]u8) bool {
            _ = self;
            return std.hash_map.StringContext.eql(.{}, a[0..], b[0..]);
        }
    }, std.hash_map.default_max_load_percentage);

    var app: *@This() = undefined;

    fn init(alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();

        var term = try term_mod.Term.init(alloc);
        errdefer term.deinit();

        try term.uncook(@This());
        errdefer term.cook_restore() catch |e| utils_mod.dump_error(e);

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        const jj = try jj_mod.JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        try jj.requests.send(.status);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .term = term,
            .input_iterator = .{ .input = try .init(alloc) },
            .events = events,
            .jj = jj,
            .status = &.{},
            .changes = .init(alloc, &[_]u8{}),
            .diffcache = .init(alloc),
            .command_text = .init(alloc),
            .input_thread = undefined,
        };

        const input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        errdefer {
            _ = self.quit.fuse();
            input_thread.join();
        }

        try self.diffcache.put(self.focused_change.hash, .{ .diff = &.{} });

        self.input_thread = input_thread;
        app = self;
        return self;
    }

    fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.changes.deinit();
        defer {
            var it = self.diffcache.iterator();
            while (it.next()) |e| if (e.value_ptr.diff) |diff| {
                self.alloc.free(diff);
            };
            self.diffcache.deinit();
        }
        defer self.command_text.deinit();
        defer self.arena.deinit();
        defer self.term.deinit();
        defer self.term.cook_restore() catch |e| utils_mod.dump_error(e);
        defer self.input_iterator.input.deinit();
        defer {
            while (self.events.try_recv()) |e| switch (e) {
                .jj => |res| switch (res.res) {
                    .ok, .err => |buf| self.alloc.free(buf),
                },
                else => {},
            };
            self.events.deinit();
        }
        defer self.jj.deinit();
        defer self.input_thread.join();
        _ = self.quit.fuse();
    }

    pub fn winch(_: c_int) callconv(.C) void {
        app.events.send(.sigwinch) catch |e| utils_mod.dump_error(e);
    }

    fn _input_loop(self: *@This()) void {
        self.input_loop() catch |e| utils_mod.dump_error(e);
    }

    fn input_loop(self: *@This()) !void {
        while (true) {
            var fds = [1]std.posix.pollfd{.{ .fd = self.term.tty.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            if (try std.posix.poll(&fds, 20) > 0) {
                var buf = std.mem.zeroes([32]u8);
                const n = try self.term.tty.read(&buf);
                for (buf[0..n]) |c| try self.input_iterator.input.push_back(c);

                while (self.input_iterator.next() catch |e| switch (e) {
                    error.ExpectedByte => null,
                    else => {
                        try self.events.send(.{ .err = e });
                        return;
                    },
                }) |input| {
                    try self.events.send(.{ .input = input });
                }
            }

            if (self.quit.check()) {
                break;
            }
        }
    }

    fn event_loop(self: *@This()) !void {
        try self.events.send(.rerender);

        if (comptime builtin.mode == .Debug) {
            try self.term.tty.writeAll(codes.kitty.disable_input_protocol);
            try self.term.tty.writeAll(codes.focus.disable);
            try self.term.tty.writeAll(codes.mouse.disable_any_event ++ codes.mouse.disable_sgr_mouse_mode);
        }

        while (self.events.wait_recv()) |event| switch (event) {
            .quit => return,
            .err => |err| return err,
            .rerender => try self.render(),
            .sigwinch => try self.events.send(.rerender),
            .input => |input| {
                switch (input) {
                    .key => |key| {
                        // _ = key;
                        // std.log.debug("got input event: {any}", .{key});

                        if (comptime builtin.mode == .Debug) {
                            if (key.action.just_pressed() and key.mod.eq(.{ .ctrl = true })) switch (key.key) {
                                '1' => try self.term.tty.writeAll(codes.kitty.disable_input_protocol),
                                '2' => try self.term.tty.writeAll(codes.focus.disable),
                                '3' => try self.term.tty.writeAll(codes.mouse.disable_any_event ++ codes.mouse.disable_sgr_mouse_mode),
                                else => {},
                            };
                            if (key.action.just_pressed() and key.mod.eq(.{})) switch (key.key) {
                                '1' => try self.term.tty.writeAll(codes.kitty.enable_input_protocol),
                                '2' => try self.term.tty.writeAll(codes.focus.enable),
                                '3' => try self.term.tty.writeAll(codes.mouse.enable_any_event ++ codes.mouse.enable_sgr_mouse_mode),
                                else => {},
                            };
                        }
                    },
                    .functional => |key| {
                        // _ = key;
                        // std.log.debug("got input event: {any}", .{key});

                        if (key.key == .escape and key.action.just_pressed() and key.mod.eq(.{})) {
                            self.focus = .status;
                            try self.events.send(.rerender);
                        }
                    },
                    .mouse => |key| {
                        _ = key;
                        // std.log.debug("got mouse input event: {any}", .{key});
                    },
                    .focus => |e| {
                        _ = e;
                        // std.log.debug("got focus event: {any}", .{e});
                    },
                    .unsupported => {},
                }

                if (self.focus == .status) switch (input) {
                    .key => |key| {
                        if (key.key == 'q') {
                            try self.events.send(.quit);
                        }
                        if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{})) {
                            self.y += 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{})) {
                            self.y -= 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            if (self.diffcache.getPtr(self.focused_change.hash)) |diff| {
                                diff.y += 10;
                            }
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            if (self.diffcache.getPtr(self.focused_change.hash)) |diff| {
                                diff.y -= 10;
                            }
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'h' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.x_split -= 0.05;
                            try self.events.send(.rerender);
                        }
                        if (key.key == 'l' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.x_split += 0.05;
                            try self.events.send(.rerender);
                        }

                        if (key.key == ':' and key.action.just_pressed() and key.mod.eq(.{ .shift = true })) {
                            self.focus = .command;
                            try self.events.send(.rerender);
                            self.command_text.reset();
                            continue;
                        }
                    },
                    .mouse => |key| {
                        if (key.key == .scroll_down and key.action.pressed() and key.mod.eq(.{})) {
                            self.y += 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                        if (key.key == .scroll_up and key.action.pressed() and key.mod.eq(.{})) {
                            self.y -= 1;
                            try self.events.send(.rerender);

                            try self.request_jj();
                        }
                    },
                    else => {},
                };

                if (self.focus == .command) switch (input) {
                    .key => |key| {
                        if (key.action.pressed() and (key.mod.eq(.{ .shift = true }) or key.mod.eq(.{}))) {
                            try self.command_text.write(cast(u8, key.key));
                            try self.events.send(.rerender);
                        }
                    },
                    .functional => |key| {
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{})) {
                            self.command_text.left();
                            try self.events.send(.rerender);
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{})) {
                            self.command_text.right();
                            try self.events.send(.rerender);
                        }
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.command_text.left_word();
                            try self.events.send(.rerender);
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.command_text.right_word();
                            try self.events.send(.rerender);
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{})) {
                            _ = self.command_text.back();
                            try self.events.send(.rerender);
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{ .alt = true })) {
                            _ = self.command_text.back();
                            while (true) {
                                if (' ' == self.command_text.peek_back() orelse break) {
                                    break;
                                }
                                _ = self.command_text.back();
                            }
                            try self.events.send(.rerender);
                        }
                    },
                    else => {},
                };
            },
            .jj => |res| switch (res.req) {
                .status => {
                    self.alloc.free(self.status);
                    switch (res.res) {
                        .ok => |buf| {
                            self.status = buf;
                            self.changes.reset(buf);

                            try self.request_jj();
                        },
                        .err => |buf| {
                            self.status = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
                .diff => |req| {
                    switch (res.res) {
                        .ok, .err => |buf| {
                            self.diffcache.getPtr(req.hash).?.diff = buf;
                        },
                    }
                    try self.events.send(.rerender);
                },
            },
        };
    }

    fn save_diff(self: *@This(), change: *const jj_mod.Change, diff: []const u8) !void {
        try self.diffcache.put(try self.alloc.dupe(u8, change.hash[0..]), diff);
    }

    fn maybe_request_diff(self: *@This(), change: *const jj_mod.Change) !void {
        if (self.diffcache.get(change.hash) == null) {
            try self.jj.requests.send(.{ .diff = change });
        }
    }

    fn request_jj(self: *@This()) !void {
        self.changes.reset(self.status);
        var i: i32 = 0;
        while (try self.changes.next()) |change| {
            // const n: i32 = 3;
            const n: i32 = 0;
            if (self.y == i) {
                self.focused_change = change.change;
            } else if (@abs(self.y - i) < n) {
                if (self.diffcache.get(change.change.hash) == null) {
                    try self.diffcache.put(change.change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change.change });
                }
            } else if (self.y + n < i) {
                break;
            }
            i += 1;
        }

        if (self.diffcache.get(self.focused_change.hash)) |_| {
            try self.events.send(.rerender);
        } else {
            try self.diffcache.put(self.focused_change.hash, .{});
            try self.jj.requests.send(.{ .diff = self.focused_change });
        }
    }

    fn render(self: *@This()) !void {
        defer _ = self.arena.reset(.retain_capacity);
        self.y = @max(0, self.y);
        self.x_split = @min(@max(0.0, self.x_split), 1.0);

        try self.term.update_size();
        {
            var status = Surface.init(&self.term, .{});
            try status.clear();
            // try status.draw_border(border.rounded);

            var bar = try status.split_y(-1, .none);
            try bar.draw_buf(try std.fmt.allocPrint(self.arena.allocator(), " huh does this work?  ", .{}));

            var diffs = try status.split_x(cast(i32, cast(f32, status.size().x) * self.x_split), .border);
            var skip = self.y;
            self.changes.reset(self.status);
            while (try self.changes.next()) |change| {
                if (skip > 0) {
                    skip -= 1;
                    continue;
                }
                try status.draw_buf(change.buf);
                try status.new_line();
                if (status.is_full()) break;
            }

            if (self.diffcache.getPtr(self.focused_change.hash)) |cdiff| if (cdiff.diff) |diff| {
                cdiff.y = @max(0, cdiff.y);
                diffs.y_scroll = cdiff.y;
                try diffs.draw_buf(diff);
            } else {
                try diffs.draw_buf(" loading ... ");
            };

            if (self.focus == .command) {
                const screen = self.term.screen;
                const popup_size = Vec2{ .x = 60, .y = 20 };
                const origin = screen.origin.add(screen.size.mul(0.5)).sub(popup_size.mul(0.5));
                var command = Surface.init(&self.term, .{ .origin = origin, .size = popup_size });
                try command.clear();
                try command.draw_border(term_mod.border.rounded);
                try command.draw_border_heading(" Command ");

                try self.command_text.draw(&command);
            }
        }
        try self.term.flush_writes();
    }
};

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = utils_mod.Log.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    try utils_mod.Log.logger.init(alloc);
    defer utils_mod.Log.logger.deinit();

    defer _ = gpa.deinit();

    const app = try App.init(alloc);
    defer app.deinit();

    try app.event_loop();
}

// pub fn main1() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     while (true) {
//         var buf = std.mem.zeroes([1]u8);

//         if (buf[0] == 'q') {
//             return;
//         } else if (buf[0] == '\x1B') {
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 1;
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 0;
//             try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

//             var esc_buf: [8]u8 = undefined;
//             const esc_read = try term.tty.read(&esc_buf);

//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.TIME))] = 0;
//             term.raw.?.cc[@intCast(@intFromEnum(std.posix.V.MIN))] = 1;
//             try std.posix.tcsetattr(term.tty.handle, .NOW, term.raw.?);

//             if (std.mem.eql(u8, esc_buf[0..esc_read], "[A")) {
//                 term.i -|= 1;
//             } else if (std.mem.eql(u8, esc_buf[0..esc_read], "[B")) {
//                 term.i = @min(term.i + 1, 3);
//             }
//         }
//     }
// }
