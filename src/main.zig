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
    region: lay_mod.Region,

    y: i32 = 0,
    x: i32 = 0,

    y_scroll: i32 = 0,
    border: bool = false,

    id: u32,
    screen: *term_mod.Screen,

    const Split = enum {
        none,
        gap,
        border,
    };

    fn init(screen: *term_mod.Screen, v: struct { origin: ?Vec2 = null, size: ?Vec2 = null }) !@This() {
        return .{
            .id = try screen.get_surface_id(),
            .screen = screen,
            .region = .{
                .origin = v.origin orelse screen.term.screen.origin,
                .size = v.size orelse screen.term.screen.size,
            },
        };
    }

    fn size(self: *const @This()) Vec2 {
        return self.region.size;
    }

    fn clear(self: *@This()) !void {
        try self.screen.clear_region(self.id, self.region);
    }

    fn is_y_out(self: *@This()) bool {
        return !self.region.contains_y(self.region.origin.y + self.y);
    }

    fn is_x_out(self: *@This()) bool {
        return !self.region.contains_x(self.region.origin.x + self.x);
    }

    fn is_full(self: *@This()) bool {
        const x_full = self.region.size.y - 1 == self.y and self.is_x_out();
        return x_full or self.is_y_out();
    }

    fn new_line(self: *@This()) !void {
        try self.draw_buf("\n\n");
    }

    fn draw_border(self: *@This(), borders: anytype) !void {
        self.border = true;
        try self.screen.draw_border(self.id, self.region, borders);
    }

    fn apply_style(self: *@This(), style: term_mod.TermStyledGraphemeIterator.Style) !void {
        try style.write_to(self.screen.writer(self.id));
    }

    fn draw_border_heading(self: *@This(), heading: []const u8) !void {
        _ = try self.screen.draw_buf(self.id, heading, .{
            .origin = .{
                .x = @min(self.region.end().x, self.region.origin.x + 1),
                .y = self.region.origin.y,
            },
            .size = .{
                .x = @max(0, self.region.size.x - 2),
                .y = 1,
            },
        }, 0, 0, 0);
    }

    fn draw_bufln(self: *@This(), buf: []const u8) !void {
        try self.draw_buf(buf);
        try self.new_line();
    }

    fn draw_buf(self: *@This(), buf: []const u8) !void {
        if (self.is_full()) return;

        self.y = @max(0, self.y);
        self.y_scroll = @max(0, self.y_scroll);
        const res = try self.screen.draw_buf(
            self.id,
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
            try self.screen.draw_split(self.id, self.region, regions.split, null, self.border);
        }

        const other = @This(){
            .id = try self.screen.get_surface_id(),
            .screen = self.screen,
            .region = regions.right,
        };

        self.* = @This(){
            .id = self.id,
            .screen = self.screen,
            .region = regions.left,
        };

        return other;
    }

    fn split_y(self: *@This(), y: i32, split: Split) !@This() {
        const regions = self.region.border_sub(.splat(@intFromBool(self.border))).split_y(y, split != .none);

        if (split == .border) {
            try self.screen.draw_split(self.id, self.region, null, regions.split, self.border);
        }

        const other = @This(){
            .id = try self.screen.get_surface_id(),
            .screen = self.screen,
            .region = regions.bottom,
        };

        self.* = @This(){
            .id = self.id,
            .screen = self.screen,
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

const LogSlate = struct {
    y: i32 = 0,
    skip_y: i32 = 0,
    status: []const u8,
    changes: jj_mod.ChangeIterator,
    focused_change: jj_mod.Change = .{},
    alloc: std.mem.Allocator,
    // arrayhashmap to preserve insertion order
    selected_changes: std.AutoArrayHashMap(jj_mod.Change, void),

    fn deinit(self: *@This()) void {
        self.alloc.free(self.status);
        self.changes.deinit();
        self.selected_changes.deinit();
    }

    fn render(self: *@This(), surface: *Surface, events: *utils_mod.Channel(App.Event), state: App.State) !void {
        self.y = @max(0, self.y);
        if (self.skip_y > self.y) {
            self.skip_y = self.y;
        }

        var gutter = try surface.split_x(3, .none);
        std.mem.swap(Surface, surface, &gutter);

        var i: i32 = 0;
        self.changes.reset(self.status);
        while (try self.changes.next()) |change| {
            defer i += 1;
            if (self.skip_y > i) {
                continue;
            }

            const is_selected = self.selected_changes.contains(change.change);
            if (i == self.y) {
                if (state == .rebase) {
                    try gutter.apply_style(.{ .background_color = .from_theme(.success) });

                    switch (state.rebase) {
                        .onto => {
                            if (is_selected) {
                                try gutter.draw_bufln("#>");
                            } else {
                                try gutter.draw_bufln("->");
                            }
                            try gutter.draw_bufln("  ");

                            try surface.draw_bufln(change.buf);
                        },
                        .after => {
                            try gutter.draw_bufln("->");
                            try surface.new_line();

                            if (is_selected) {
                                try gutter.draw_bufln("# ");
                            } else {
                                try gutter.draw_bufln("  ");
                            }
                            try gutter.draw_bufln("  ");

                            try surface.draw_bufln(change.buf);
                        },
                        .before => {
                            if (is_selected) {
                                try gutter.draw_bufln("# ");
                            } else {
                                try gutter.draw_bufln("  ");
                            }
                            try gutter.draw_bufln("  ");
                            try surface.draw_bufln(change.buf);

                            try gutter.draw_bufln("->");
                            try surface.new_line();
                        },
                    }

                    try gutter.apply_style(.reset);
                } else {
                    try gutter.draw_bufln("->");
                    try surface.draw_bufln(change.buf);
                }
            } else {
                if (is_selected) {
                    try gutter.draw_buf("#");
                }
                try gutter.new_line();
                try gutter.new_line();

                try surface.draw_bufln(change.buf);
            }

            if (surface.is_full()) break;
        }

        if (self.changes.ended() and self.y >= i and i > 0) {
            self.y = i - 1;
        }

        if (self.y >= i and !self.changes.ended()) {
            self.skip_y += 1;
            try events.send(.rerender);
        }
    }
};

const DiffSlate = struct {
    alloc: std.mem.Allocator,
    diffcache: DiffCache,

    const Hash = jj_mod.Change.Hash;
    const CachedDiff = struct {
        y: i32 = 0,
        diff: ?[]const u8 = null,
    };
    const DiffCache = std.HashMap(Hash, CachedDiff, struct {
        pub fn hash(self: @This(), s: Hash) u64 {
            _ = self;
            return std.hash_map.StringContext.hash(.{}, s[0..]);
        }
        pub fn eql(self: @This(), a: Hash, b: Hash) bool {
            _ = self;
            return std.hash_map.StringContext.eql(.{}, a[0..], b[0..]);
        }
    }, std.hash_map.default_max_load_percentage);

    fn deinit(self: *@This()) void {
        var it = self.diffcache.iterator();
        while (it.next()) |e| if (e.value_ptr.diff) |diff| {
            self.alloc.free(diff);
        };
        self.diffcache.deinit();
    }

    fn render(self: *@This(), surface: *Surface, focused: jj_mod.Change) !void {
        if (self.diffcache.getPtr(focused.hash)) |cdiff| if (cdiff.diff) |diff| {
            cdiff.y = @max(0, cdiff.y);
            surface.y_scroll = cdiff.y;
            try surface.draw_buf(diff);
        } else {
            try surface.draw_buf(" loading ... ");
        };
    }
};

pub const App = struct {
    screen: term_mod.Screen,

    quit_input_loop: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),

    jj: *jj_mod.JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    x_split: f32 = 0.55,
    command_text: TextInput,

    diff: DiffSlate,
    log: LogSlate,

    state: State = .status,
    render_count: u64 = 0,
    last_hash: u64 = 0,

    pub const State = union(enum(u8)) {
        status,
        oplog,
        evlog: jj_mod.Change,
        command,
        rebase: Rebase,
        new,
        squash,
        abandon,
    };

    pub const Rebase = enum(u8) {
        onto,
        after,
        before,
    };

    pub const Event = union(enum) {
        sigwinch,
        rerender,
        diff_update,
        quit,
        input: term_mod.TermInputIterator.Input,
        jj: jj_mod.JujutsuServer.Response,
        err: anyerror,
    };

    var app: *@This() = undefined;

    fn init(alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();

        const term = try term_mod.Term.init();
        var screen = term_mod.Screen.init(alloc, term);
        errdefer screen.deinit();

        screen.term.register_signal_handlers(@This());
        errdefer screen.term.unregister_signal_handlers();

        try screen.term.uncook();
        errdefer screen.term.cook_restore() catch |e| utils_mod.dump_error(e);

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        const jj = try jj_mod.JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        try jj.requests.send(.status);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .screen = screen,
            .input_iterator = .{ .input = try .init(alloc) },
            .events = events,
            .jj = jj,
            .diff = .{
                .alloc = alloc,
                .diffcache = .init(alloc),
            },
            .log = .{
                .alloc = alloc,
                .status = &.{},
                .changes = .init(alloc, &[_]u8{}),
                .selected_changes = .init(alloc),
            },
            .command_text = .init(alloc),
            .input_thread = undefined,
        };

        const input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        errdefer {
            _ = self.quit_input_loop.fuse();
            input_thread.join();
        }

        try self.diff.diffcache.put(self.log.focused_change.hash, .{ .diff = &.{} });

        self.input_thread = input_thread;
        app = self;
        return self;
    }

    fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.log.deinit();
        defer self.diff.deinit();
        defer self.command_text.deinit();
        defer self.arena.deinit();
        defer self.screen.deinit();
        defer self.screen.term.unregister_signal_handlers();
        defer self.screen.term.cook_restore() catch |e| utils_mod.dump_error(e);
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
        _ = self.quit_input_loop.fuse();
    }

    pub fn winch(_: c_int) callconv(.C) void {
        app.events.send(.sigwinch) catch |e| utils_mod.dump_error(e);
    }

    fn _input_loop(self: *@This()) void {
        self.input_loop() catch |e| utils_mod.dump_error(e);
    }

    fn input_loop(self: *@This()) !void {
        while (true) {
            var fds = [1]std.posix.pollfd{.{ .fd = self.screen.term.tty.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            if (try std.posix.poll(&fds, 20) > 0) {
                var buf = std.mem.zeroes([32]u8);
                const n = try self.screen.term.tty.read(&buf);
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

            if (self.quit_input_loop.check()) {
                break;
            }
        }
    }

    fn restore_terminal_for_command(self: *@This()) !void {
        self.screen.term.unregister_signal_handlers();
        try self.screen.term.cook_restore();
        _ = self.quit_input_loop.fuse();
        defer _ = self.quit_input_loop.unfuse();
        self.input_thread.join();
    }

    fn uncook_terminal(self: *@This()) !void {
        self.input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        self.screen.term.register_signal_handlers(@This());
        try self.screen.term.uncook();
        try self.events.send(.rerender);
        try self.jj.requests.send(.status);
    }

    fn event_loop(self: *@This()) !void {
        try self.events.send(.rerender);

        if (comptime builtin.mode == .Debug) {
            // try self.screen.term.fancy_features_that_break_gdb(.disable, .{});
        }

        while (self.events.wait_recv()) |event| {
            defer _ = self.arena.reset(.retain_capacity);
            const temp = self.arena.allocator();
            var hasher = std.hash.Wyhash.init(0);
            defer {
                hasher.update(&std.mem.toBytes(self.state));
                hasher.update(&std.mem.toBytes(self.x_split));
                hasher.update(&std.mem.toBytes(self.log.y));
                if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                    hasher.update(&std.mem.toBytes(diff.y));
                }
                var it = self.log.selected_changes.iterator();
                while (it.next()) |e| {
                    hasher.update(&e.key_ptr.id);
                }
                hasher.update(&std.mem.toBytes(self.command_text.text.items.len));
                hasher.update(&std.mem.toBytes(self.command_text.cursor));
                // hasher.update(self.log.status); // too much text for hashing on every event

                const final_hash = hasher.final();
                if (final_hash != self.last_hash) {
                    self.events.send(.rerender) catch |e| utils_mod.dump_error(e);
                }
                self.last_hash = final_hash;
            }

            const tropes: struct {
                global: bool = true,
                scroll_log: bool = false,
                scroll_diff: bool = false,
                resize_master: bool = false,
                escape_to_status: bool = false,
                space_select: bool = false,
            } = switch (self.state) {
                .status => .{
                    .scroll_log = true,
                    .scroll_diff = true,
                    .resize_master = true,
                },
                .new, .squash, .abandon, .rebase => .{
                    .scroll_log = true,
                    .scroll_diff = true,
                    .resize_master = true,
                    .escape_to_status = true,
                    .space_select = true,
                },
                .command => .{
                    .escape_to_status = true,
                },
                .oplog, .evlog => .{},
            };

            event_blk: switch (event) {
                .quit => return,
                .err => |err| return err,
                .rerender => try self.render(),
                .sigwinch => try self.events.send(.rerender),
                .diff_update => try self.request_jj(),
                .input => |input| {
                    if (tropes.global) switch (input) {
                        .key => |key| {
                            // _ = key;
                            // std.log.debug("got input event: {any}", .{key});

                            if (comptime builtin.mode == .Debug) {
                                if (key.action.just_pressed() and key.mod.eq(.{ .ctrl = true })) switch (key.key) {
                                    '1' => try self.screen.term.fancy_features_that_break_gdb(.disable, .{
                                        .input = true,
                                        .focus = false,
                                        .mouse = false,
                                    }),
                                    '2' => try self.screen.term.fancy_features_that_break_gdb(.disable, .{
                                        .input = false,
                                        .focus = true,
                                        .mouse = false,
                                    }),
                                    '3' => try self.screen.term.fancy_features_that_break_gdb(.disable, .{
                                        .input = false,
                                        .focus = false,
                                        .mouse = true,
                                    }),
                                    else => {},
                                };
                                if (key.action.just_pressed() and key.mod.eq(.{})) switch (key.key) {
                                    '1' => try self.screen.term.fancy_features_that_break_gdb(.enable, .{
                                        .input = true,
                                        .focus = false,
                                        .mouse = false,
                                    }),
                                    '2' => try self.screen.term.fancy_features_that_break_gdb(.enable, .{
                                        .input = false,
                                        .focus = true,
                                        .mouse = false,
                                    }),
                                    '3' => try self.screen.term.fancy_features_that_break_gdb(.enable, .{
                                        .input = false,
                                        .focus = false,
                                        .mouse = true,
                                    }),
                                    else => {},
                                };
                            }
                        },
                        .functional => |key| {
                            // _ = key;
                            // std.log.debug("got input event: {any}", .{key});

                            if (comptime builtin.mode == .Debug) if (key.key == .escape and
                                key.action.just_pressed() and
                                key.mod.eq(.{ .ctrl = true }))
                            {
                                try self.screen.term.fancy_features_that_break_gdb(.disable, .{});
                                @breakpoint();
                                break :event_blk;
                            };
                        },
                        .mouse => |key| {
                            _ = key;
                            // std.log.debug("got mouse input event: {any}", .{key});
                        },
                        .focus => |e| {
                            // _ = e;
                            // std.log.debug("got focus event: {any}", .{e});

                            switch (e) {
                                .out => {},
                                .in => try self.jj.requests.send(.status),
                            }
                        },
                        .unsupported => {},
                    };
                    if (tropes.scroll_log) switch (input) {
                        .key => |key| {
                            if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{})) {
                                self.log.y += 1;
                                try self.events.send(.diff_update);
                            }
                            if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{})) {
                                self.log.y -= 1;
                                try self.events.send(.diff_update);
                            }
                        },
                        .mouse => |key| {
                            if (key.key == .scroll_down and key.action.pressed() and key.mod.eq(.{})) {
                                self.log.y += 1;
                                try self.events.send(.diff_update);
                            }
                            if (key.key == .scroll_up and key.action.pressed() and key.mod.eq(.{})) {
                                self.log.y -= 1;
                                try self.events.send(.diff_update);
                            }
                        },
                        else => {},
                    };
                    if (tropes.scroll_diff) switch (input) {
                        .key => |key| {
                            if (key.key == 'j' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                                    diff.y += 10;
                                }
                            }
                            if (key.key == 'k' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                                    diff.y -= 10;
                                }
                            }
                        },
                        else => {},
                    };
                    if (tropes.resize_master) switch (input) {
                        .key => |key| {
                            if (key.key == 'h' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                self.x_split -= 0.05;
                            }
                            if (key.key == 'l' and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                self.x_split += 0.05;
                            }
                        },
                        else => {},
                    };
                    if (tropes.escape_to_status) switch (input) {
                        .functional => |key| {
                            if (key.key == .escape and key.action.pressed() and key.mod.eq(.{})) {
                                self.log.selected_changes.clearRetainingCapacity();
                                self.state = .status;
                                break :event_blk;
                            }
                        },
                        else => {},
                    };
                    if (tropes.space_select) switch (input) {
                        .key => |key| {
                            if (key.key == ' ' and key.action.pressed() and key.mod.eq(.{})) {
                                if (self.log.selected_changes.fetchOrderedRemove(self.log.focused_change) == null) {
                                    try self.log.selected_changes.put(self.log.focused_change, {});
                                }
                            }
                        },
                        else => {},
                    };

                    switch (self.state) {
                        .status => switch (input) {
                            .key => |key| {
                                if (key.key == 'q') {
                                    try self.events.send(.quit);
                                }
                                if (key.key == 'n' and key.action.pressed() and key.mod.eq(.{})) {
                                    self.state = .new;
                                    break :event_blk;
                                }
                                if (key.key == 'e' and key.action.pressed() and key.mod.eq(.{})) {
                                    try self.execute_non_interactive_command(&[_][]const u8{
                                        "jj",
                                        "edit",
                                        self.log.focused_change.id[0..],
                                    });
                                    try self.jj.requests.send(.status);
                                }
                                if (key.key == 'r' and key.action.pressed() and key.mod.eq(.{})) {
                                    self.state = .{ .rebase = .onto };
                                    try self.log.selected_changes.put(self.log.focused_change, {});
                                    break :event_blk;
                                }
                                if (key.key == 'S' and key.action.pressed() and key.mod.eq(.{ .shift = true })) {
                                    self.state = .squash;
                                    try self.log.selected_changes.put(self.log.focused_change, {});
                                    break :event_blk;
                                }
                                if (key.key == 'a' and key.action.pressed() and key.mod.eq(.{})) {
                                    self.state = .abandon;
                                    try self.log.selected_changes.put(self.log.focused_change, {});
                                    break :event_blk;
                                }
                                if (key.key == 's' and key.action.pressed() and key.mod.eq(.{})) {
                                    try self.execute_interactive_command(&[_][]const u8{
                                        "jj",
                                        "split",
                                        "-r",
                                        self.log.focused_change.id[0..],
                                    });
                                }
                                if (key.key == 'D' and key.action.pressed() and key.mod.eq(.{ .shift = true })) {
                                    try self.execute_interactive_command(&[_][]const u8{
                                        "jj",
                                        "describe",
                                        "-r",
                                        self.log.focused_change.id[0..],
                                    });
                                }

                                if (key.key == ':' and key.action.just_pressed() and key.mod.eq(.{ .shift = true })) {
                                    self.state = .command;
                                    self.command_text.reset();
                                    break :event_blk;
                                }
                            },
                            else => {},
                        },
                        .rebase => |rebase| switch (input) {
                            .key => |key| {
                                if (std.mem.indexOfScalar(u8, "abo", cast(u8, key.key)) != null and
                                    key.action.pressed() and
                                    key.mod.eq(.{}))
                                {
                                    switch (key.key) {
                                        'o' => self.state = .{ .rebase = .onto },
                                        'a' => self.state = .{ .rebase = .after },
                                        'b' => self.state = .{ .rebase = .before },
                                        else => {
                                            self.log.selected_changes.clearRetainingCapacity();
                                            self.state = .status;
                                        },
                                    }
                                    break :event_blk;
                                }
                            },
                            .functional => |key| {
                                if (key.key == .enter and key.action.pressed() and key.mod.eq(.{})) {
                                    defer {
                                        self.log.selected_changes.clearRetainingCapacity();
                                        self.state = .status;
                                    }

                                    var args = std.ArrayList([]const u8).init(temp);
                                    try args.append("jj");
                                    try args.append("rebase");

                                    var it = self.log.selected_changes.iterator();
                                    while (it.next()) |e| {
                                        try args.append("-r");
                                        try args.append(e.key_ptr.id[0..]);

                                        if (std.meta.eql(e.key_ptr.*, self.log.focused_change)) {
                                            break :event_blk;
                                        }
                                    }

                                    switch (rebase) {
                                        .onto => try args.append("-d"),
                                        .after => try args.append("-A"),
                                        .before => try args.append("-B"),
                                    }

                                    try args.append(self.log.focused_change.id[0..]);

                                    try self.execute_non_interactive_command(args.items);

                                    try self.jj.requests.send(.status);
                                    break :event_blk;
                                }
                            },
                            else => {},
                        },
                        .abandon => switch (input) {
                            .functional => |key| {
                                if (key.key == .enter and key.action.pressed() and key.mod.eq(.{})) {
                                    defer {
                                        self.log.selected_changes.clearRetainingCapacity();
                                        self.state = .status;
                                    }

                                    // TODO:
                                    break :event_blk;
                                }
                            },
                            else => {},
                        },
                        .squash => switch (input) {
                            .functional => |key| {
                                if (key.key == .enter and key.action.pressed() and key.mod.eq(.{})) {
                                    defer {
                                        self.log.selected_changes.clearRetainingCapacity();
                                        self.state = .status;
                                    }

                                    // TODO:
                                    break :event_blk;
                                }
                            },
                            else => {},
                        },
                        .new => switch (input) {
                            .functional => |key| {
                                if (key.key == .enter and key.action.pressed() and key.mod.eq(.{})) {
                                    defer {
                                        self.log.selected_changes.clearRetainingCapacity();
                                        self.state = .status;
                                    }

                                    var args = std.ArrayList([]const u8).init(temp);
                                    try args.append("jj");
                                    try args.append("new");

                                    var it = self.log.selected_changes.iterator();
                                    while (it.next()) |e| {
                                        try args.append(e.key_ptr.id[0..]);

                                        if (std.meta.eql(e.key_ptr.*, self.log.focused_change)) {
                                            break :event_blk;
                                        }
                                    }

                                    try args.append(self.log.focused_change.id[0..]);

                                    try self.execute_non_interactive_command(args.items);

                                    try self.jj.requests.send(.status);
                                    self.log.y = 0;
                                    break :event_blk;
                                }
                            },
                            else => {},
                        },
                        .command => switch (input) {
                            .key => |key| {
                                if (key.action.pressed() and (key.mod.eq(.{ .shift = true }) or key.mod.eq(.{}))) {
                                    try self.command_text.write(cast(u8, key.key));
                                }
                            },
                            .functional => |key| {
                                if (key.key == .enter and key.action.pressed() and key.mod.eq(.{})) {
                                    var args = std.ArrayList([]const u8).init(temp);

                                    // TODO: support parsing and passing "string" and 'string' with \" \' and spaces properly
                                    var arg_it = std.mem.splitAny(u8, self.command_text.text.items, &std.ascii.whitespace);
                                    while (arg_it.next()) |arg| {
                                        try args.append(arg);
                                    }

                                    try self.execute_interactive_command(args.items);
                                    self.command_text.reset();
                                    self.state = .status;
                                }
                                if (key.key == .left and key.action.pressed() and key.mod.eq(.{})) {
                                    self.command_text.left();
                                }
                                if (key.key == .right and key.action.pressed() and key.mod.eq(.{})) {
                                    self.command_text.right();
                                }
                                if (key.key == .left and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                    self.command_text.left_word();
                                }
                                if (key.key == .right and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                                    self.command_text.right_word();
                                }
                                if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{})) {
                                    _ = self.command_text.back();
                                }
                                if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{ .alt = true })) {
                                    _ = self.command_text.back();
                                    while (true) {
                                        if (' ' == self.command_text.peek_back() orelse break) {
                                            break;
                                        }
                                        _ = self.command_text.back();
                                    }
                                }
                            },
                            else => {},
                        },
                        .oplog, .evlog => unreachable,
                    }
                },
                .jj => |res| switch (res.req) {
                    .status => {
                        self.alloc.free(self.log.status);
                        switch (res.res) {
                            .ok => |buf| {
                                self.log.status = buf;
                                self.log.changes.reset(buf);
                                try self.events.send(.diff_update);
                            },
                            .err => |buf| {
                                self.log.status = buf;
                            },
                        }

                        try self.events.send(.rerender);
                    },
                    .diff => |req| {
                        switch (res.res) {
                            .ok, .err => |buf| {
                                self.diff.diffcache.getPtr(req.hash).?.diff = buf;
                            },
                        }
                        try self.events.send(.rerender);
                    },
                },
            }
        }
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
        self.log.changes.reset(self.log.status);
        var i: i32 = 0;
        while (try self.log.changes.next()) |change| {
            // const n: i32 = 3;
            const n: i32 = 0;
            if (self.log.y == i) {
                self.log.focused_change = change.change;
            } else if (@abs(self.log.y - i) < n) {
                if (self.diff.diffcache.get(change.change.hash) == null) {
                    try self.diff.diffcache.put(change.change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change.change });
                }
            } else if (self.log.y + n < i) {
                break;
            }
            i += 1;
        }

        if (self.diff.diffcache.get(self.log.focused_change.hash)) |_| {
            try self.events.send(.rerender);
        } else {
            try self.diff.diffcache.put(self.log.focused_change.hash, .{});
            // somehow debounce diff requests
            try self.jj.requests.send(.{ .diff = self.log.focused_change });
        }
    }

    fn render_status_bar(self: *@This(), surface: *Surface) !void {
        const temp = self.arena.allocator();

        {
            var colors = try surface.split_x(-32, .none);

            try colors.apply_style(.{ .foreground_color = .from_theme(.default_background) });
            var j: u8 = 0;
            while (!colors.is_full()) {
                if (j < 16) {
                    try colors.apply_style(.{ .background_color = .{ .bit8 = j } });
                } else if (j == 16) {
                    try colors.apply_style(.{ .background_color = .from_theme(.default_background) });
                }
                try colors.draw_buf(try std.fmt.allocPrint(temp, "{d:0>2}", .{j}));
                j += 1;
            }
            try colors.apply_style(.reset);
        }

        {
            try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
            try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
            try surface.apply_style(.bold);
            try surface.draw_buf(" NORMAL ");
            try surface.apply_style(.reset);

            try surface.draw_buf(" ");

            try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
            try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
            try surface.apply_style(.bold);
            try surface.draw_buf(try std.fmt.allocPrint(temp, " frame: {d} ", .{self.render_count}));
            try surface.apply_style(.reset);
        }
    }

    fn render_command_input(self: *@This()) !void {
        const screen = self.screen.term.screen;
        const popup_size = Vec2{ .x = 60, .y = 20 };
        const origin = screen.origin.add(screen.size.mul(0.5)).sub(popup_size.mul(0.5));
        const region = self.screen.term.screen.clamp(.{ .origin = origin, .size = popup_size });
        var command = try Surface.init(&self.screen, .{ .origin = region.origin, .size = region.size });
        try command.clear();
        try command.draw_border(term_mod.border.rounded);
        try command.draw_border_heading(" Command ");

        try self.command_text.draw(&command);
    }

    fn render(self: *@This()) !void {
        defer self.render_count += 1;

        self.x_split = @min(@max(0.0, self.x_split), 1.0);

        try self.screen.term.update_size();
        {
            var status = try Surface.init(&self.screen, .{});
            try status.clear();
            // try status.draw_border(border.rounded);

            var bar = try status.split_y(-1, .none);
            try self.render_status_bar(&bar);

            var diffs = try status.split_x(cast(i32, cast(f32, status.size().x) * self.x_split), .border);

            try self.log.render(&status, &self.events, self.state);
            try self.diff.render(&diffs, self.log.focused_change);

            if (self.state == .command) {
                try self.render_command_input();
            }
        }
        try self.screen.flush_writes();
    }

    fn execute_non_interactive_command(self: *@This(), args: []const []const u8) !void {
        // TODO: popup error window
        self._execute_non_interactive_command(args) catch |e| switch (e) {
            error.SomeErrorMan => {},
            else => return e,
        };
    }

    fn _execute_non_interactive_command(self: *@This(), args: []const []const u8) !void {
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
        switch (err) {
            .Exited => |e| {
                if (e != 0) {
                    std.log.err("exited with code: {}", .{e});
                }
                return error.SomeErrorMan;
            },
            // .Signal => |code| {},
            // .Stopped => |code| {},
            // .Unknown => |code| {},
            else => |e| {
                std.log.err("exited with code: {}", .{e});
                return error.SomeErrorMan;
            },
        }

        const err_fifo = poller.fifo(.stderr);
        if (err_fifo.count > 0) {
            std.log.err("{s}", .{err_fifo.buf[err_fifo.head..][0..err_fifo.count]});
        }

        const out_fifo = poller.fifo(.stdout);
        if (out_fifo.count > 0) {
            std.log.debug("{s}", .{out_fifo.buf[out_fifo.head..][0..out_fifo.count]});
        }
    }

    fn execute_interactive_command(self: *@This(), args: []const []const u8) !void {
        try self.restore_terminal_for_command();

        // TODO: popup error window
        self._execute_command(args) catch |e| switch (e) {
            error.SomeErrorMan => {},
            error.FileNotFound => {},
            else => return e,
        };
        try self.uncook_terminal();
    }

    fn _execute_command(self: *@This(), args: []const []const u8) !void {
        var child = std.process.Child.init(args, self.alloc);
        try child.spawn();
        const err = try child.wait();
        switch (err) {
            .Exited => |e| {
                if (e != 0) {
                    std.log.err("exited with code: {}", .{e});
                }
                return error.SomeErrorMan;
            },
            // .Signal => |code| {},
            // .Stopped => |code| {},
            // .Unknown => |code| {},
            else => |e| {
                std.log.err("exited with code: {}", .{e});
                return error.SomeErrorMan;
            },
        }
    }
};

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = utils_mod.FileLogger.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    try utils_mod.FileLogger.logger.init(alloc, .{ .allow_fail = true });
    defer utils_mod.FileLogger.logger.deinit();

    defer _ = gpa.deinit();

    const app = try App.init(alloc);
    defer app.deinit();

    app.event_loop() catch |e| utils_mod.dump_error(e);
}
