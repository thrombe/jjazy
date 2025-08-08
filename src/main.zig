const std = @import("std");
const builtin = @import("builtin");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const lay_mod = @import("lay.zig");
const Vec2 = lay_mod.Vec2;

const term_mod = @import("term.zig");
const codes = term_mod.codes;
const symbols = term_mod.border;

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
            .id = try screen.get_cmdbuf_id(),
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
        const region = self.region.border_sub(.splat(@intFromBool(self.border)));
        return !region.contains_y(region.origin.y + self.y);
    }

    fn is_x_out(self: *@This()) bool {
        const region = self.region.border_sub(.splat(@intFromBool(self.border)));
        return !region.contains_x(region.origin.x + self.x);
    }

    fn is_full(self: *@This()) bool {
        const region = self.region.border_sub(.splat(@intFromBool(self.border)));
        const x_full = region.size.y - 1 == self.y and self.is_x_out();
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
            try self.screen.draw_split(
                self.id,
                self.region,
                regions.split,
                null,
                self.border,
                symbols.thin.square,
            );
        }

        const other = @This(){
            .id = try self.screen.get_cmdbuf_id(),
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
            try self.screen.draw_split(
                self.id,
                self.region,
                null,
                regions.split,
                self.border,
                symbols.thin.square,
            );
        }

        const other = @This(){
            .id = try self.screen.get_cmdbuf_id(),
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
    changes: jj_mod.Change.Parsed.Iterator,
    focused_change: jj_mod.Change = .{},
    alloc: std.mem.Allocator,
    // arrayhashmap to preserve insertion order
    selected_changes: std.AutoArrayHashMap(jj_mod.Change, void),

    fn deinit(self: *@This()) void {
        self.alloc.free(self.status);
        self.changes.deinit();
        self.selected_changes.deinit();
    }

    fn render(
        self: *@This(),
        surface: *Surface,
        app: *App,
        state: App.State,
        tropes: anytype,
    ) !void {
        self.y = @max(0, self.y);
        if (self.skip_y > self.y) {
            self.skip_y = self.y;
        }

        var gutter = try surface.split_x(3, .none);
        std.mem.swap(Surface, surface, &gutter);

        var i: i32 = 0;
        self.changes.reset(self.status);
        while (try self.changes.next()) |parsed| {
            defer i += 1;
            if (self.skip_y > i) {
                continue;
            }

            const change = jj_mod.Change.from_parsed(&parsed);
            const is_selected = self.selected_changes.contains(change);
            if (i == self.y) {
                if (tropes.colored_gutter_cursor) {
                    try gutter.apply_style(.{ .background_color = .from_theme(.dim_text) });
                    try gutter.apply_style(.{ .foreground_color = .from_theme(.default_background) });
                    try gutter.apply_style(.bold);
                }

                switch (state) {
                    .duplicate, .rebase => |where| switch (where) {
                        .onto => {
                            if (is_selected) {
                                try gutter.draw_bufln("#>");
                            } else {
                                try gutter.draw_bufln("->");
                            }
                            for (0..parsed.formatted.height - 1) |_| {
                                try gutter.draw_bufln("  ");
                            }

                            try surface.draw_bufln(parsed.formatted.buf);
                        },
                        .after => {
                            try gutter.draw_bufln("->");
                            try surface.new_line();

                            if (is_selected) {
                                try gutter.draw_bufln("# ");
                            } else {
                                try gutter.draw_bufln("  ");
                            }
                            for (0..parsed.formatted.height - 1) |_| {
                                try gutter.draw_bufln("  ");
                            }

                            try surface.draw_bufln(parsed.formatted.buf);
                        },
                        .before => {
                            if (is_selected) {
                                try gutter.draw_bufln("# ");
                            } else {
                                try gutter.draw_bufln("  ");
                            }
                            for (0..parsed.formatted.height - 1) |_| {
                                try gutter.draw_bufln("  ");
                            }
                            try surface.draw_bufln(parsed.formatted.buf);

                            try gutter.draw_bufln("->");
                            try surface.new_line();
                        },
                    },
                    else => {
                        if (is_selected) {
                            try gutter.draw_bufln("#>");
                        } else {
                            try gutter.draw_bufln("->");
                        }
                        for (0..parsed.formatted.height - 1) |_| {
                            try gutter.draw_bufln("  ");
                        }
                        try surface.draw_bufln(parsed.formatted.buf);
                    },
                }

                if (tropes.colored_gutter_cursor) {
                    try gutter.apply_style(.reset);
                }
            } else {
                if (is_selected) {
                    try gutter.draw_buf("#");
                }
                for (0..parsed.formatted.height) |_| {
                    try gutter.draw_bufln("  ");
                }

                try surface.draw_bufln(parsed.formatted.buf);
            }

            if (surface.is_full()) break;
        }

        if (self.changes.ended() and self.y >= i and i > 0) {
            self.y = i - 1;
        }

        if (self.y >= i and !self.changes.ended()) {
            self.skip_y += 1;
            try app._send_event(.rerender);
        }
    }
};

const OpLogSlate = struct {
    y: i32 = 0,
    skip_y: i32 = 0,
    alloc: std.mem.Allocator,
    oplog: []const u8,
    ops: jj_mod.Operation.Parsed.Iterator,
    focused_op: jj_mod.Operation = .{},

    fn deinit(self: *@This()) void {
        self.alloc.free(self.oplog);
        self.ops.deinit();
    }

    fn render(
        self: *@This(),
        surface: *Surface,
        app: *App,
    ) !void {
        self.y = @max(0, self.y);
        if (self.skip_y > self.y) {
            self.skip_y = self.y;
        }

        var gutter = try surface.split_x(3, .none);
        std.mem.swap(Surface, surface, &gutter);

        var i: i32 = 0;
        self.ops.reset(self.oplog);
        while (try self.ops.next()) |parsed| {
            defer i += 1;
            if (self.skip_y > i) {
                continue;
            }

            if (i == self.y) {
                try gutter.draw_bufln("->");
                for (0..parsed.formatted.height - 1) |_| {
                    try gutter.draw_bufln("  ");
                }

                try surface.draw_bufln(parsed.formatted.buf);
            } else {
                for (0..parsed.formatted.height) |_| {
                    try gutter.draw_bufln("  ");
                }

                try surface.draw_bufln(parsed.formatted.buf);
            }

            if (surface.is_full()) break;
        }

        if (self.ops.ended() and self.y >= i and i > 0) {
            self.y = i - 1;
        }

        if (self.y >= i and !self.ops.ended()) {
            self.skip_y += 1;
            try app._send_event(.rerender);
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

const BookmarkSlate = struct {
    alloc: std.mem.Allocator,
    buf: []const u8,
    it: jj_mod.Bookmark.Parsed.Iterator,
    index: u32 = 0,

    fn deinit(self: *@This()) void {
        self.alloc.free(self.buf);
        self.it.deinit();
    }

    fn reset(self: *@This()) void {
        self.index = 0;
        self.it.reset(self.buf);
    }

    fn get_selected(self: *@This()) !?jj_mod.Bookmark.Parsed {
        var i = self.index;
        self.it.reset(self.buf);
        while (try self.it.next()) |b| {
            if (i == 0) {
                return b;
            }
            i -|= 1;
        }
        return null;
    }

    fn render(self: *@This(), surface: *Surface) !void {
        try surface.clear();

        try surface.apply_style(.bold);
        try surface.draw_border(symbols.thin.rounded);
        try surface.draw_border_heading(" Bookmarks ");
        try surface.apply_style(.reset);

        var gutter = try surface.split_x(2, .gap);
        std.mem.swap(Surface, surface, &gutter);

        var i: u32 = 0;
        self.it.reset(self.buf);
        while (try self.it.next()) |bookmark| {
            try surface.draw_buf(bookmark.parsed.name);
            for (bookmark.parsed.target) |t| {
                try surface.draw_buf(" ");
                try surface.draw_buf(t[0..8]);
            }
            if (bookmark.parsed.remote) |remote| {
                try surface.draw_buf(" @");
                try surface.draw_buf(remote);
            }
            try surface.new_line();

            if (i == self.index) {
                try gutter.draw_bufln("->");
            } else {
                try gutter.new_line();
            }
            i += 1;
        }

        if (self.index >= i) {
            self.index = i -| 1;
        }
    }
};

const HelpSlate = struct {
    fn deinit(self: *@This()) void {
        _ = self;
    }

    fn render(self: *@This(), surface: *Surface, app: *App) !void {
        _ = self;
        _ = app;

        try surface.apply_style(.{ .background_color = .from_theme(.default_background) });
        try surface.apply_style(.{ .foreground_color = .from_theme(.default_foreground) });
        try surface.apply_style(.bold);

        try surface.clear();
        try surface.draw_border(symbols.thin.rounded);
        try surface.draw_border_heading(" Help ");

        try surface.apply_style(.reset);
    }
};

const Toaster = struct {
    alloc: std.mem.Allocator,
    id: Id = 0,
    // toasts need to maintain order even when adding/removing items
    toasts: std.AutoArrayHashMap(Id, Toast),

    const Id = u32;
    const Toast = struct {
        msg: []const u8,
        err: ?anyerror,
    };

    fn deinit(self: *@This()) void {
        var it = self.toasts.iterator();
        while (it.next()) |toast| {
            self.alloc.free(toast.value_ptr.*.msg);
        }
        self.toasts.deinit();
    }

    fn add(self: *@This(), toast: Toast) !Id {
        defer self.id += 1;
        const id = self.id;
        try self.toasts.put(id, toast);
        return id;
    }

    fn remove(self: *@This(), id: Id) void {
        const toast = self.toasts.fetchOrderedRemove(id) orelse return;
        self.alloc.free(toast.value.msg);
    }

    fn render(self: *@This(), surface: *Surface, app: *App) !void {
        const temp = app.arena.allocator();
        var buf = std.ArrayList(Toaster.Toast).init(temp);

        var it = self.toasts.iterator();
        while (it.next()) |e| try buf.append(e.value_ptr.*);

        var toast: Surface = undefined;
        for (buf.items) |e| {
            var height = utils_mod.LineIterator.init(e.msg).count_height();
            height += 2;

            toast = try surface.split_y(-height, .gap);

            try toast.apply_style(.{ .foreground_color = .from_theme(if (e.err != null) .errors else .dim_text) });
            try toast.clear();
            try toast.draw_border(symbols.thin.square);
            if (e.err) |err| {
                try toast.apply_style(.{ .foreground_color = .from_theme(.max_contrast) });
                try toast.apply_style(.bold);
                try toast.draw_border_heading(try std.fmt.allocPrint(temp, " {any} ", .{err}));

                try toast.apply_style(.reset);
                try toast.apply_style(.{ .foreground_color = .from_theme(if (e.err != null) .errors else .dim_text) });
            }
            try toast.apply_style(.reset);
            try toast.draw_buf(e.msg);
        }
    }
};

const JjazyLogs = struct {};

pub const Sleeper = struct {
    alloc: std.mem.Allocator,
    thread: std.Thread,
    quit: utils_mod.Fuse = .{},
    requests: utils_mod.Channel(Request),
    sleeps: std.ArrayList(Request),

    // not owned
    events: utils_mod.Channel(App.Event),

    const Request = struct { target_ts: i128, event: App.Event };

    pub fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(App.Event)) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var requests = try utils_mod.Channel(Request).init(alloc);
        errdefer requests.deinit();

        self.* = .{
            .alloc = alloc,
            .sleeps = .init(alloc),
            .requests = requests,
            .events = events,
            .thread = undefined,
        };

        self.thread = try std.Thread.spawn(.{}, @This()._start, .{self});
        return self;
    }

    pub fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.requests.deinit();
        defer self.sleeps.deinit();
        defer self.thread.join();
        _ = self.quit.fuse();
        _ = self.requests.close();
    }

    pub fn delay_event(self: *@This(), time_ms: i128, event: App.Event) !void {
        const time = std.time.nanoTimestamp();
        const del: i128 = std.time.ns_per_ms * time_ms;
        const target = time + del;
        try self.requests.send(.{
            .target_ts = target,
            .event = event,
        });
    }

    fn _start(self: *@This()) void {
        self.start() catch |e| utils_mod.dump_error(e);
    }

    fn start(self: *@This()) !void {
        while (true) {
            if (self.quit.check()) return;
            if (self.requests.try_recv()) |e| {
                try self.sleeps.append(e);
            }

            const now = std.time.nanoTimestamp();
            var i: usize = 0;
            while (i < self.sleeps.items.len) {
                const e = self.sleeps.items[i];
                if (now >= e.target_ts) {
                    _ = self.sleeps.swapRemove(i);
                    try self.events.send(e.event);
                } else {
                    i += 1;
                }
            }

            std.Thread.sleep(std.time.ns_per_ms * 50);
        }
    }
};

pub const App = struct {
    screen: term_mod.Screen,

    quit_input_loop: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),

    sleeper: *Sleeper,
    jj: *jj_mod.JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    state: State = .log,
    show_help: bool = false,
    x_split: f32 = 0.55,
    text_input: TextInput,

    log: LogSlate,
    oplog: OpLogSlate,
    diff: DiffSlate,
    bookmarks: BookmarkSlate,
    help: HelpSlate,
    toaster: Toaster,

    rerender_pending_since: u64 = 0,
    rerender_pending_count: u64 = 0,
    render_count: u64 = 0,
    last_hash: u64 = 0,

    input_action_map: InputActionMap,

    const InputActionState = struct { state: State, input: term_mod.TermInputIterator.Input };
    const InputActionMap = std.HashMap(InputActionState, Action, struct {
        pub fn hash(self: @This(), input: InputActionState) u64 {
            _ = self;

            var hasher = std.hash.Wyhash.init(0);

            utils_mod.hash_update(&hasher, input);

            switch (input.state) {
                inline .oplog => |_, t| utils_mod.hash_update(&hasher, t),
                else => |t| utils_mod.hash_update(&hasher, t),
            }
            switch (input.input) {
                .mouse => |key| {
                    utils_mod.hash_update(&hasher, key.key);
                    utils_mod.hash_update(&hasher, key.mod);
                    utils_mod.hash_update(&hasher, key.action);
                },
                else => utils_mod.hash_update(&hasher, input.input),
            }

            return hasher.final();
        }
        pub fn eql(self: @This(), a: InputActionState, b: InputActionState) bool {
            _ = self;
            switch (a.state) {
                inline .oplog => return std.meta.activeTag(a.state) == std.meta.activeTag(b.state),
                else => return std.meta.eql(a.state, b.state),
            }
            switch (a.input) {
                .mouse => {
                    if (!std.meta.activeTag(a.input) == std.meta.activeTag(b.input)) return false;
                    if (!std.meta.eql(a.input.mouse.key, b.input.mouse.key)) return false;
                    if (!std.meta.eql(a.input.mouse.mod, b.input.mouse.mod)) return false;
                    if (!std.meta.eql(a.input.mouse.action, b.input.mouse.action)) return false;
                    return true;
                },
                else => std.meta.eql(a.input, b.input),
            }
        }
    }, std.hash_map.default_max_load_percentage);

    pub const State = union(enum(u8)) {
        log,
        oplog,
        evlog: jj_mod.Change,
        bookmark: enum {
            view,
            new,
        },
        git: enum {
            fetch,
            push,
        },
        command,
        rebase: Where,
        duplicate: Where,
        new,
        squash,
        abandon,
    };

    pub const Where = enum(u8) {
        onto,
        after,
        before,
    };

    pub const Event = union(enum) {
        sigwinch,
        rerender,
        diff_update,
        op_update,
        quit,
        input: term_mod.TermInputIterator.Input,
        jj: jj_mod.JujutsuServer.Response,
        err: anyerror,
        toast: Toaster.Toast,
        pop_toast: Toaster.Id,
        action: Action,
    };

    pub const Action = union(enum) {
        fancy_terminal_features_that_break_gdb: enum { enable, disable },
        trigger_breakpoint,
        refresh_master_content,
        scroll: struct { target: enum { log, oplog, diff, bookmarks }, offset: i32 },
        resize_master: f32,
        escape_to_log,
        select_focused_change,
        set_where: Where,
        send_quit_event,
        switch_state_to_new,
        jj_edit,
        switch_state_to_rebase_onto,
        switch_state_to_squash,
        switch_state_to_abandon,
        switch_state_to_oplog,
        switch_state_to_duplicate,
        switch_state_to_bookmarks_view,
        show_help,
        jj_split,
        jj_describe,
        switch_state_to_command,
        apply_jj_rebase,
        apply_jj_abandon,
        apply_jj_squash,
        apply_jj_new,
        execute_command_in_input_buffer,
        apply_jj_op_restore,
        apply_jj_duplicate,
        switch_state_to_bookmark_new,
        new_commit_from_bookmark,
        move_bookmark_to_selected: struct { force: bool },
        apply_jj_bookmark_delete,
        apply_jj_bookmark_forget: struct { include_remotes: bool },
        apply_jj_bookmark_create_from_input_buffer_on_selected_change,
        apply_jj_git_fetch,
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

        var input_action_map = try init_input_action_map(alloc);
        errdefer input_action_map.deinit();

        const sleeper = try Sleeper.init(alloc, events);
        errdefer sleeper.deinit();

        const jj = try jj_mod.JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        try jj.requests.send(.log);
        try jj.requests.send(.bookmark);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .screen = screen,
            .input_iterator = .{ .input = try .init(alloc) },
            .events = events,
            .sleeper = sleeper,
            .jj = jj,
            .log = .{
                .alloc = alloc,
                .status = &.{},
                .changes = .init(alloc, &[_]u8{}),
                .selected_changes = .init(alloc),
            },
            .oplog = .{
                .alloc = alloc,
                .oplog = &.{},
                .ops = .init(alloc, &[_]u8{}),
            },
            .diff = .{
                .alloc = alloc,
                .diffcache = .init(alloc),
            },
            .bookmarks = .{
                .alloc = alloc,
                .buf = &.{},
                .it = .init(alloc, &[_]u8{}),
            },
            .help = .{},
            .toaster = .{
                .alloc = alloc,
                .toasts = .init(alloc),
            },
            .text_input = .init(alloc),
            .input_action_map = input_action_map,
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
        defer self.oplog.deinit();
        defer self.diff.deinit();
        defer self.bookmarks.deinit();
        defer self.help.deinit();
        defer self.text_input.deinit();
        defer self.input_action_map.deinit();
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
        defer self.sleeper.deinit();
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
                var buf = std.mem.zeroes([256]u8);
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
        try self._send_event(.rerender);
        try self.jj.requests.send(.log);
    }

    fn init_input_action_map(alloc: std.mem.Allocator) !InputActionMap {
        var map = InputActionMap.init(alloc);
        errdefer map.deinit();

        var keys = std.ArrayList(term_mod.TermInputIterator.Input).init(alloc);
        defer keys.deinit();

        var states = std.ArrayList(State).init(alloc);
        defer states.deinit();

        {
            defer states.clearRetainingCapacity();
            try states.append(.log);
            try states.append(.oplog);
            try states.append(.{ .evlog = .{} });
            try states.append(.command);
            try states.append(.{ .bookmark = .view });
            try states.append(.{ .bookmark = .new });
            try states.append(.{ .git = .fetch });
            try states.append(.{ .git = .push });
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });
            try states.append(.new);
            try states.append(.squash);
            try states.append(.abandon);

            for (states.items) |state| try map.put(
                .{ .state = state, .input = .{ .functional = .{ .key = .escape, .mod = .{ .ctrl = true } } } },
                .trigger_breakpoint,
            );
            for (states.items) |state| try map.put(
                .{ .state = state, .input = .{ .focus = .in } },
                .refresh_master_content,
            );
            for (states.items) |state| try map.put(
                .{ .state = state, .input = .{ .functional = .{ .key = .escape } } },
                .escape_to_log,
            );
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.log);
            try states.append(.oplog);
            try states.append(.{ .evlog = .{} });
            try states.append(.{ .bookmark = .view });
            try states.append(.{ .git = .fetch });
            try states.append(.{ .git = .push });
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });
            try states.append(.new);
            try states.append(.squash);
            try states.append(.abandon);

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = '1' } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .fancy_terminal_features_that_break_gdb = .enable },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = '1', .mod = .{ .ctrl = true } } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .fancy_terminal_features_that_break_gdb = .disable },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = '?' } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .show_help,
                );
            }
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.log);
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });
            try states.append(.new);
            try states.append(.squash);
            try states.append(.abandon);

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'j', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'j', .action = .repeat } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .log, .offset = 1 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'k', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'k', .action = .repeat } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .log, .offset = -1 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'j', .action = .press, .mod = .{ .ctrl = true } } });
                try keys.append(.{ .key = .{ .key = 'j', .action = .repeat, .mod = .{ .ctrl = true } } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .diff, .offset = 10 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'k', .action = .press, .mod = .{ .ctrl = true } } });
                try keys.append(.{ .key = .{ .key = 'k', .action = .repeat, .mod = .{ .ctrl = true } } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .diff, .offset = -10 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'h', .action = .press, .mod = .{ .ctrl = true } } });
                try keys.append(.{ .key = .{ .key = 'h', .action = .repeat, .mod = .{ .ctrl = true } } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .resize_master = -0.05 },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'l', .action = .press, .mod = .{ .ctrl = true } } });
                try keys.append(.{ .key = .{ .key = 'l', .action = .repeat, .mod = .{ .ctrl = true } } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .resize_master = 0.05 },
                );
            }
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.oplog);

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'j', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'j', .action = .repeat } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .oplog, .offset = 1 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'k', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'k', .action = .repeat } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } });
                try keys.append(.{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .oplog, .offset = -1 } },
                );
            }
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });
            try states.append(.new);
            try states.append(.squash);
            try states.append(.abandon);

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = ' ', .action = .press } });
                try keys.append(.{ .key = .{ .key = ' ', .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .select_focused_change,
                );
            }
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'o' } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .set_where = .onto },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'b' } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .set_where = .before },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'a' } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .set_where = .after },
                );
            }
        }
        {
            defer states.clearRetainingCapacity();
            try states.append(.{ .bookmark = .view });

            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'j', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'j', .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .bookmarks, .offset = 1 } },
                );
            }
            {
                defer keys.clearRetainingCapacity();
                try keys.append(.{ .key = .{ .key = 'k', .action = .press } });
                try keys.append(.{ .key = .{ .key = 'k', .action = .repeat } });
                for (states.items) |state| for (keys.items) |key| try map.put(
                    .{ .state = state, .input = key },
                    .{ .scroll = .{ .target = .bookmarks, .offset = -1 } },
                );
            }
        }
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'q' } },
        }, .send_quit_event);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'n' } },
        }, .switch_state_to_new);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'e' } },
        }, .jj_edit);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'r' } },
        }, .switch_state_to_rebase_onto);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'S', .mod = .{ .shift = true } } },
        }, .switch_state_to_squash);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'a' } },
        }, .switch_state_to_abandon);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'o' } },
        }, .switch_state_to_oplog);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'd' } },
        }, .switch_state_to_duplicate);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'b' } },
        }, .switch_state_to_bookmarks_view);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 's' } },
        }, .jj_split);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = 'D', .mod = .{ .shift = true } } },
        }, .jj_describe);
        try map.put(.{
            .state = .log,
            .input = .{ .key = .{ .key = ':', .mod = .{ .shift = true } } },
        }, .switch_state_to_command);
        {
            defer states.clearRetainingCapacity();
            try states.append(.{ .rebase = .onto });
            try states.append(.{ .rebase = .after });
            try states.append(.{ .rebase = .before });

            for (states.items) |state| try map.put(
                .{ .state = state, .input = .{ .functional = .{ .key = .enter } } },
                .apply_jj_rebase,
            );
        }
        try map.put(.{
            .state = .abandon,
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .apply_jj_abandon);
        try map.put(.{
            .state = .squash,
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .apply_jj_squash);
        try map.put(.{
            .state = .new,
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .apply_jj_new);
        try map.put(.{
            .state = .command,
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .execute_command_in_input_buffer);
        try map.put(.{
            .state = .oplog,
            .input = .{ .key = .{ .key = 'r', .action = .press } },
        }, .apply_jj_op_restore);
        {
            defer states.clearRetainingCapacity();
            try states.append(.{ .duplicate = .onto });
            try states.append(.{ .duplicate = .after });
            try states.append(.{ .duplicate = .before });

            for (states.items) |state| try map.put(
                .{ .state = state, .input = .{ .functional = .{ .key = .enter, .action = .press } } },
                .apply_jj_duplicate,
            );
        }
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'n', .action = .press } },
        }, .switch_state_to_bookmark_new);
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'e', .action = .press } },
        }, .new_commit_from_bookmark);
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'm', .action = .press } },
        }, .{ .move_bookmark_to_selected = .{ .force = false } });
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'M', .action = .press, .mod = .{ .shift = true } } },
        }, .{ .move_bookmark_to_selected = .{ .force = true } });
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'd', .action = .press } },
        }, .apply_jj_bookmark_delete);
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'f', .action = .press } },
        }, .{ .apply_jj_bookmark_forget = .{ .include_remotes = false } });
        try map.put(.{
            .state = .{ .bookmark = .view },
            .input = .{ .key = .{ .key = 'F', .action = .press, .mod = .{ .shift = true } } },
        }, .{ .apply_jj_bookmark_forget = .{ .include_remotes = true } });
        try map.put(.{
            .state = .{ .bookmark = .new },
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .apply_jj_bookmark_create_from_input_buffer_on_selected_change);
        try map.put(.{
            .state = .{ .git = .fetch },
            .input = .{ .functional = .{ .key = .enter, .action = .press } },
        }, .apply_jj_git_fetch);

        return map;
    }

    // thread safety: do not use from other threads
    fn _send_event(self: *@This(), event: Event) !void {
        switch (event) {
            .rerender => {
                self.rerender_pending_count += 1;
            },
            else => {},
        }

        try self.events.send(event);
    }

    fn _wait_recv_event(self: *@This()) ?Event {
        const event = self.events.wait_recv() orelse return null;
        switch (event) {
            .rerender => {
                self.rerender_pending_count -|= 1;
            },
            else => {},
        }
        return event;
    }

    fn _handle_event(self: *@This(), event: Event) !void {
        const temp = self.arena.allocator();

        const tropes: struct {
            global: bool = true,
            escape_to_log: bool = true,
            scroll_log: bool = false,
            scroll_oplog: bool = false,
            scroll_diff: bool = false,
            scroll_bookmarks: bool = false,
            resize_master: bool = false,
            space_select: bool = false,
            colored_gutter_cursor: bool = false,
            where_oba: bool = false,
            input_text: bool = false,
        } = switch (self.state) {
            .log => .{
                .scroll_log = true,
                .scroll_diff = true,
                .resize_master = true,
            },
            .new, .squash, .abandon => .{
                .scroll_log = true,
                .scroll_diff = true,
                .resize_master = true,
                .space_select = true,
                .colored_gutter_cursor = true,
            },
            .duplicate, .rebase => .{
                .scroll_log = true,
                .scroll_diff = true,
                .resize_master = true,
                .space_select = true,
                .colored_gutter_cursor = true,
                .where_oba = true,
            },
            .oplog => .{
                .scroll_oplog = true,
            },
            .command => .{
                .input_text = true,
            },
            .bookmark => |state| switch (state) {
                .view => .{
                    .scroll_bookmarks = true,
                },
                .new => .{
                    .input_text = true,
                },
            },
            .git, .evlog => .{},
        };

        switch (event) {
            .quit => return error.Quit,
            .err => |err| return err,
            .rerender => {
                var should_render = false;
                // should_render = should_render or self.rerender_pending_count == 0;
                should_render = should_render or self.events.count() < 5;
                should_render = should_render or self.rerender_pending_since > 50;

                if (should_render) {
                    self.rerender_pending_since = 0;
                    try self.render(tropes);
                } else {
                    self.rerender_pending_since += 1;
                }
            },
            .sigwinch => {
                try self.screen.term.update_size();
                try self._send_event(.rerender);
            },
            .diff_update => try self.request_jj_diff(),
            .op_update => try self.request_jj_op(),
            .toast => |toast| {
                const id = try self.toaster.add(toast);
                try self.sleeper.delay_event(500, .{ .pop_toast = id });
            },
            .pop_toast => |id| {
                self.toaster.remove(id);
                try self._send_event(.rerender);
            },
            .input => |input| {
                if (tropes.global) switch (input) {
                    .key => |key| {
                        _ = key;
                        // std.log.debug("got input event: {any}", .{key});
                    },
                    .functional => |key| {
                        _ = key;
                        // std.log.debug("got input event: {any}", .{key});
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
                };
                if (tropes.input_text) switch (input) {
                    .key => |key| {
                        if (key.action.pressed() and (key.mod.eq(.{ .shift = true }) or key.mod.eq(.{}))) {
                            try self.text_input.write(cast(u8, key.key));
                        }
                    },
                    .functional => |key| {
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{})) {
                            self.text_input.left();
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{})) {
                            self.text_input.right();
                        }
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.text_input.left_word();
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.text_input.right_word();
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{})) {
                            _ = self.text_input.back();
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{ .alt = true })) {
                            _ = self.text_input.back();
                            while (true) {
                                if (' ' == self.text_input.peek_back() orelse break) {
                                    break;
                                }
                                _ = self.text_input.back();
                            }
                        }
                    },
                    else => {},
                };

                const action = self.input_action_map.get(.{ .state = self.state, .input = input }) orelse return;
                try self._handle_event(.{ .action = action });
            },
            .action => |action| switch (action) {
                .fancy_terminal_features_that_break_gdb => |set| switch (set) {
                    .disable => try self.screen.term.fancy_features_that_break_gdb(.disable, .{}),
                    .enable => try self.screen.term.fancy_features_that_break_gdb(.enable, .{}),
                },
                .trigger_breakpoint => {
                    try self.screen.term.fancy_features_that_break_gdb(.disable, .{});
                    @breakpoint();
                },
                .refresh_master_content => switch (self.state) {
                    .oplog => try self.jj.requests.send(.oplog),
                    else => try self.jj.requests.send(.log),
                },
                .scroll => |target| switch (target.target) {
                    .log => {
                        self.log.y += target.offset;
                        try self._send_event(.diff_update);
                    },
                    .oplog => {
                        self.oplog.y += target.offset;
                        try self._send_event(.op_update);
                    },
                    .diff => {
                        if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                            diff.y += target.offset;
                        }
                    },
                    .bookmarks => {
                        if (target.offset < 0) {
                            self.bookmarks.index -|= cast(u32, -target.offset);
                        } else {
                            self.bookmarks.index += cast(u32, target.offset);
                        }
                    },
                },
                .resize_master => |offset| {
                    self.x_split += offset;
                },
                .escape_to_log => {
                    self.log.selected_changes.clearRetainingCapacity();
                    self.state = .log;
                    self.show_help = false;
                },
                .select_focused_change => {
                    if (self.log.selected_changes.fetchOrderedRemove(self.log.focused_change) == null) {
                        try self.log.selected_changes.put(self.log.focused_change, {});
                    }
                },
                .set_where => |set| {
                    switch (self.state) {
                        .rebase, .duplicate => |*where| {
                            where.* = set;
                        },
                        else => unreachable,
                    }
                },
                .send_quit_event => {
                    try self._send_event(.quit);
                },
                .switch_state_to_new => {
                    self.state = .new;
                    try self.log.selected_changes.put(self.log.focused_change, {});
                },
                .jj_edit => {
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "edit",
                        self.log.focused_change.id[0..],
                    });
                    try self.jj.requests.send(.log);
                },
                .switch_state_to_rebase_onto => {
                    self.state = .{ .rebase = .onto };
                    try self.log.selected_changes.put(self.log.focused_change, {});
                },
                .switch_state_to_squash => {
                    self.state = .squash;
                    try self.log.selected_changes.put(self.log.focused_change, {});
                },
                .switch_state_to_abandon => {
                    self.state = .abandon;
                    try self.log.selected_changes.put(self.log.focused_change, {});
                },
                .switch_state_to_oplog => {
                    self.state = .oplog;
                    self.oplog.y = 0;
                    try self.jj.requests.send(.oplog);
                },
                .switch_state_to_duplicate => {
                    self.state = .{ .duplicate = .onto };
                    try self.log.selected_changes.put(self.log.focused_change, {});
                },
                .switch_state_to_bookmarks_view => {
                    self.state = .{ .bookmark = .view };
                    try self.jj.requests.send(.bookmark);
                },
                .show_help => {
                    self.show_help = true;
                },
                .jj_split => {
                    try self.execute_interactive_command(&[_][]const u8{
                        "jj",
                        "split",
                        "-r",
                        self.log.focused_change.id[0..],
                    });
                },
                .jj_describe => {
                    try self.execute_interactive_command(&[_][]const u8{
                        "jj",
                        "describe",
                        "-r",
                        self.log.focused_change.id[0..],
                    });
                },
                .switch_state_to_command => {
                    self.state = .command;
                    self.text_input.reset();
                },
                .apply_jj_rebase => {
                    defer {
                        self.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("rebase");

                    var it = self.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append("-r");
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.log.focused_change)) {
                            try self._err_toast(error.RebaseOnSelected, try self.alloc.dupe(u8, "Cannot rebase on selected change"));
                            return;
                        }
                    }

                    switch (self.state.rebase) {
                        .onto => try args.append("-d"),
                        .after => try args.append("-A"),
                        .before => try args.append("-B"),
                    }

                    try args.append(self.log.focused_change.id[0..]);

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_abandon => {
                    defer {
                        self.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("abandon");
                    try args.append("--retain-bookmarks");

                    var it = self.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append(e.key_ptr.id[0..]);
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_squash => {
                    defer {
                        self.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("squash");

                    var it = self.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append("--from");
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.log.focused_change)) {
                            try self._err_toast(error.SquashOnSelected, try self.alloc.dupe(u8, "Cannot squash on selected change"));
                            return;
                        }
                    }

                    try args.append("--into");
                    try args.append(self.log.focused_change.id[0..]);

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_new => {
                    defer {
                        self.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("new");

                    var it = self.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append(e.key_ptr.id[0..]);
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                    self.log.y = 0;
                },
                .execute_command_in_input_buffer => {
                    var args = std.ArrayList([]const u8).init(temp);

                    // TODO: support parsing and passing "string" and 'string' with \" \' and spaces properly
                    var arg_it = std.mem.splitAny(u8, self.text_input.text.items, &std.ascii.whitespace);
                    while (arg_it.next()) |arg| {
                        try args.append(arg);
                    }

                    try self.execute_interactive_command(args.items);
                    self.text_input.reset();
                    self.state = .log;
                },
                .apply_jj_op_restore => {
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "op",
                        "restore",
                        self.oplog.focused_op.id[0..],
                    });
                    self.oplog.y = 0;
                    try self.jj.requests.send(.oplog);
                },
                .apply_jj_duplicate => {
                    defer {
                        self.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("duplicate");

                    var it = self.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.log.focused_change)) {
                            try self._err_toast(error.DuplicateOnSelected, try self.alloc.dupe(u8, "Cannot duplicate on selected change"));
                            return;
                        }
                    }

                    switch (self.state.duplicate) {
                        .onto => try args.append("-d"),
                        .after => try args.append("-A"),
                        .before => try args.append("-B"),
                    }

                    try args.append(self.log.focused_change.id[0..]);

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .switch_state_to_bookmark_new => {
                    self.state = .{ .bookmark = .new };
                },
                .new_commit_from_bookmark => {
                    defer {
                        self.text_input.reset();
                        self.state = .log;
                    }

                    const bookmark = try self.bookmarks.get_selected() orelse return;

                    // TODO: why multiple targets?
                    if (bookmark.parsed.target.len != 1) {
                        try self._err_toast(error.MultipleTargetsFound, try self.alloc.dupe(u8, "Error executing command"));
                        return;
                    }

                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "new",
                        "-r",
                        bookmark.parsed.target[0][0..8],
                    });
                    try self.jj.requests.send(.log);
                },
                .move_bookmark_to_selected => |force| {
                    defer self.state = .log;
                    const bookmark = try self.bookmarks.get_selected() orelse return;

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("bookmark");
                    try args.append("move");
                    try args.append(bookmark.parsed.name);
                    try args.append("--to");
                    try args.append(self.log.focused_change.id[0..]);
                    if (force.force) {
                        try args.append("--allow-backwards");
                    }

                    try self.execute_non_interactive_command(args.items);
                    try self.jj.requests.send(.log);
                },
                .apply_jj_bookmark_delete => {
                    defer self.state = .log;
                    const bookmark = try self.bookmarks.get_selected() orelse return;
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "delete",
                        bookmark.parsed.name,
                    });
                },
                .apply_jj_bookmark_forget => |v| {
                    defer self.state = .log;
                    const bookmark = try self.bookmarks.get_selected() orelse return;

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("bookmark");
                    try args.append("forget");
                    try args.append(bookmark.parsed.name);
                    if (v.include_remotes) {
                        try args.append("--include-remotes");
                    }

                    try self.execute_non_interactive_command(args.items);
                },
                .apply_jj_bookmark_create_from_input_buffer_on_selected_change => {
                    defer {
                        self.text_input.reset();
                        self.state = .log;
                    }

                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "create",
                        "-r",
                        self.log.focused_change.id[0..],
                        self.text_input.text.items,
                    });
                    try self.jj.requests.send(.log);
                },
                .apply_jj_git_fetch => {
                    defer self.state = .log;

                    // TODO:
                    //  support --branch
                    //  support --remote
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "git",
                        "fetch",
                    });
                    try self.jj.requests.send(.log);
                },
            },
            // TODO: handle errors better
            .jj => |res| switch (res.req) {
                .log => {
                    self.alloc.free(self.log.status);
                    switch (res.res) {
                        .ok => |buf| {
                            self.log.status = buf;
                            self.log.changes.reset(buf);
                            try self._send_event(.diff_update);
                        },
                        .err => |buf| {
                            self.log.status = buf;
                        },
                    }

                    try self._send_event(.rerender);
                },
                .diff => |req| {
                    switch (res.res) {
                        .ok, .err => |buf| {
                            self.diff.diffcache.getPtr(req.hash).?.diff = buf;
                        },
                    }
                    try self._send_event(.rerender);
                },
                .oplog => {
                    self.alloc.free(self.oplog.oplog);
                    switch (res.res) {
                        .ok, .err => |buf| {
                            self.oplog.oplog = buf;
                            self.oplog.ops.reset(buf);
                            try self._send_event(.rerender);
                        },
                    }
                },
                .evolog => |req| {
                    _ = req;
                    switch (res.res) {
                        .ok, .err => |buf| {
                            self.alloc.free(buf);
                        },
                    }
                },
                .bookmark => {
                    switch (res.res) {
                        .err, .ok => |buf| {
                            self.alloc.free(self.bookmarks.buf);
                            self.bookmarks.buf = buf;
                            self.bookmarks.reset();
                            try self._send_event(.rerender);
                        },
                    }
                },
            },
        }
    }

    fn event_loop(self: *@This()) !void {
        try self._send_event(.rerender);

        if (comptime builtin.mode == .Debug) {
            // try self.screen.term.fancy_features_that_break_gdb(.disable, .{});
        }

        while (self._wait_recv_event()) |event| {
            defer _ = self.arena.reset(.retain_capacity);
            var hasher = std.hash.Wyhash.init(0);
            defer {
                hasher.update(&std.mem.toBytes(self.state));
                hasher.update(&std.mem.toBytes(self.show_help));
                hasher.update(&std.mem.toBytes(self.x_split));
                hasher.update(&std.mem.toBytes(self.log.y));
                if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                    hasher.update(&std.mem.toBytes(diff.y));
                }
                hasher.update(&std.mem.toBytes(self.oplog.y));
                var it = self.log.selected_changes.iterator();
                while (it.next()) |e| {
                    hasher.update(&e.key_ptr.id);
                }
                hasher.update(&std.mem.toBytes(self.text_input.text.items.len));
                hasher.update(&std.mem.toBytes(self.text_input.cursor));
                hasher.update(&std.mem.toBytes(self.bookmarks.index));
                // hasher.update(self.log.status); // too much text for hashing on every event

                const final_hash = hasher.final();
                if (final_hash != self.last_hash) {
                    self._send_event(.rerender) catch |e| utils_mod.dump_error(e);
                }
                self.last_hash = final_hash;
            }

            self._handle_event(event) catch |e| switch (e) {
                error.Quit => return,
                else => return e,
            };
        }
    }

    fn _err_toast(self: *@This(), err: ?anyerror, msg: []const u8) !void {
        const id = try self.toaster.add(.{ .err = err, .msg = msg });
        try self.sleeper.delay_event(5000, .{ .pop_toast = id });
    }

    fn request_jj_diff(self: *@This()) !void {
        self.log.changes.reset(self.log.status);
        var i: i32 = 0;
        while (try self.log.changes.next()) |parsed| {
            const change = jj_mod.Change.from_parsed(&parsed);

            // const n: i32 = 3;
            const n: i32 = 0;
            if (self.log.y == i) {
                self.log.focused_change = change;
            } else if (@abs(self.log.y - i) < n) {
                if (self.diff.diffcache.get(change.hash) == null) {
                    try self.diff.diffcache.put(change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change });
                }
            } else if (self.log.y + n < i) {
                break;
            }
            i += 1;
        }

        if (self.diff.diffcache.get(self.log.focused_change.hash)) |_| {
            try self._send_event(.rerender);
        } else {
            try self.diff.diffcache.put(self.log.focused_change.hash, .{});
            // somehow debounce diff requests
            try self.jj.requests.send(.{ .diff = self.log.focused_change });
        }
    }

    fn request_jj_op(self: *@This()) !void {
        self.oplog.ops.reset(self.oplog.oplog);
        var i: i32 = 0;
        while (try self.oplog.ops.next()) |parsed| {
            const op = jj_mod.Operation.from_parsed(&parsed);

            if (self.oplog.y == i) {
                self.oplog.focused_op = op;
            } else if (self.log.y < i) {
                break;
            }
            i += 1;
        }

        // TODO: jj op show in diff area + cache for it
    }

    fn render_status_bar(self: *@This(), surface: *Surface) !void {
        const temp = self.arena.allocator();

        if (builtin.mode == .Debug) {
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
            try surface.draw_buf(switch (self.state) {
                inline .rebase, .git, .duplicate => |_p, t| switch (_p) {
                    inline else => |p| " " ++ @tagName(t) ++ "." ++ @tagName(p) ++ " ",
                },
                inline .bookmark => |_p, t| switch (_p) {
                    inline .view => " " ++ @tagName(t) ++ " ",
                    inline else => |p| " " ++ @tagName(t) ++ "." ++ @tagName(p) ++ " ",
                },
                inline else => |_, t| " " ++ @tagName(t) ++ " ",
            });
            try surface.apply_style(.reset);

            if (builtin.mode == .Debug) {
                try surface.draw_buf(" ");

                try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
                try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
                try surface.apply_style(.bold);
                try surface.draw_buf(try std.fmt.allocPrint(temp, " frame: {d} ", .{self.render_count}));
                try surface.apply_style(.reset);
            }
        }
    }

    fn render(self: *@This(), tropes: anytype) !void {
        defer self.render_count += 1;

        self.x_split = @min(@max(0.0, self.x_split), 1.0);

        {
            var status = try Surface.init(&self.screen, .{});
            try status.clear();
            // try status.draw_border(symbols.thin.rounded);

            var bar = try status.split_y(-1, .none);
            try self.render_status_bar(&bar);

            var diffs = try status.split_x(cast(i32, cast(f32, status.size().x) * self.x_split), .border);

            switch (self.state) {
                .oplog => try self.oplog.render(&status, self),
                else => try self.log.render(&status, self, self.state, tropes),
            }
            try self.diff.render(&diffs, self.log.focused_change);

            const max_popup_region = self.screen.term.screen
                .split_y(-2, false).top
                .split_y(1, false).bottom
                .border_sub(.{ .x = 2 });

            if (self.state == .bookmark) {
                const popup_size = Vec2{ .x = 60, .y = 30 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var surface = try Surface.init(&self.screen, .{ .origin = region.origin, .size = region.size });

                try self.bookmarks.render(&surface);
            }

            if (self.state == .command or (self.state == .bookmark and self.state.bookmark == .new)) {
                const popup_size = Vec2{ .x = 55, .y = 5 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var input_box = try Surface.init(&self.screen, .{ .origin = region.origin, .size = region.size });
                try input_box.clear();
                try input_box.draw_border(symbols.thin.rounded);

                if (self.state == .command) {
                    try input_box.draw_border_heading(" Command ");
                } else {
                    try input_box.draw_border_heading(" Enter new bookmark name ");
                }

                try self.text_input.draw(&input_box);
            }

            {
                const region = max_popup_region.split_x(-100, false).right;
                var surface = try Surface.init(&self.screen, .{ .origin = region.origin, .size = region.size });
                try self.toaster.render(&surface, self);
            }

            if (self.show_help) {
                const screen = self.screen.term.screen;
                const r0 = screen.border_sub(.{ .x = 3, .y = 2 });
                const r1 = r0.split_x(-50, false).right;
                const r2 = r1.split_y(-25, false).bottom;
                var help = try Surface.init(&self.screen, .{
                    .origin = r2.origin,
                    .size = r2.size,
                });
                try self.help.render(&help, self);
            }
        }
        try self.screen.flush_writes();
    }

    fn execute_non_interactive_command(self: *@This(), args: []const []const u8) !void {
        // const _err_buf = try self._execute_non_interactive_command(args);
        // if (_err_buf) |err_buf| try self._err_toast(error.CommandExecutionError, err_buf);

        // better error messages. nothing bad. so i just do this for now :|
        try self.execute_interactive_command(args);
    }

    fn _execute_non_interactive_command(self: *@This(), args: []const []const u8) !?[]const u8 {
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

        if (errored) {
            return try err_buf.toOwnedSlice();
        }

        const out_fifo = poller.fifo(.stdout);
        if (out_fifo.count > 0) {
            std.log.debug("{s}", .{out_fifo.buf[out_fifo.head..][0..out_fifo.count]});
        }

        err_buf.deinit();
        return null;
    }

    fn execute_interactive_command(self: *@This(), args: []const []const u8) !void {
        // sync_set just so commands that immediately terminate do not flash the screen :P
        try self.screen.term.tty.writeAll(codes.sync_set);
        try self.restore_terminal_for_command();

        const _err_buf = self._execute_command(args) catch |e| switch (e) {
            error.FileNotFound => try std.fmt.allocPrint(self.alloc, "Executable not found", .{}),
            else => return e,
        };
        if (_err_buf) |err_buf| try self._err_toast(error.CommandExecutionError, err_buf);

        try self.uncook_terminal();
    }

    fn _execute_command(self: *@This(), args: []const []const u8) !?[]const u8 {
        const alloc = self.alloc;
        var child = std.process.Child.init(args, alloc);
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stderr = child.stderr orelse return error.NoStderr;
        child.stderr = null;
        defer stderr.close();

        // similar to child.collectOutput
        const max_output_bytes = 1000 * 1000;
        var poller = std.io.poll(alloc, enum { stderr }, .{
            .stderr = stderr,
        });
        defer poller.deinit();

        while (try poller.poll()) {
            if (poller.fifo(.stderr).count > max_output_bytes)
                return error.StderrStreamTooLong;
        }

        const err = try child.wait();

        const err_fifo = poller.fifo(.stderr);
        const err_out = err_fifo.buf[err_fifo.head..][0..err_fifo.count];

        var err_buf = std.ArrayList(u8).init(self.alloc);
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

        if (errored) {
            return try err_buf.toOwnedSlice();
        }

        err_buf.deinit();
        return null;
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
