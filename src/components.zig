const std = @import("std");
const options = @import("options");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const search_mod = @import("search.zig");

const lay_mod = @import("lay.zig");
const Vec2 = lay_mod.Vec2;

const term_mod = @import("term.zig");
const codes = term_mod.codes;
const symbols = term_mod.border;

const jj_mod = @import("jj.zig");

const event_mod = @import("event.zig");
const State = event_mod.State;
const App = event_mod.App;
const Action = event_mod.Action;

pub const Surface = struct {
    region: lay_mod.Region,

    y: i32 = 0,
    x: i32 = 0,

    y_scroll: i32 = 0,
    x_scroll: i32 = 0,
    border: bool = false,

    id: u32,
    depth: f32,
    screen: *term_mod.Screen,

    const Split = enum {
        none,
        gap,
        border,
    };

    fn init(screen: *term_mod.Screen, depth: f32, v: struct { origin: ?Vec2 = null, size: ?Vec2 = null }) !@This() {
        return .{
            .id = try screen.get_cmdbuf_id(depth),
            .depth = depth,
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
        }, 0, 0, 0, @intCast(self.x_scroll + @max(0, -self.region.origin.x)));
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
            @intCast(self.x_scroll + @max(0, -self.region.origin.x)),
        );
        self.y = res.y;
        self.x = res.x;
        self.y_scroll -= res.skipped;
    }

    fn split_x(self: *@This(), x: i32, split: Split, keep: enum { left, right }) !@This() {
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

        var other = @This(){
            .id = try self.screen.get_cmdbuf_id(self.depth),
            .depth = self.depth,
            .screen = self.screen,
            .region = regions.right,
        };

        self.* = @This(){
            .id = self.id,
            .depth = self.depth,
            .screen = self.screen,
            .region = regions.left,
        };

        switch (keep) {
            .left => {},
            .right => std.mem.swap(@This(), self, &other),
        }

        return other;
    }

    fn split_y(self: *@This(), y: i32, split: Split, keep: enum { top, bottom }) !@This() {
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

        var other = @This(){
            .id = try self.screen.get_cmdbuf_id(self.depth),
            .depth = self.depth,
            .screen = self.screen,
            .region = regions.bottom,
        };

        self.* = @This(){
            .id = self.id,
            .depth = self.depth,
            .screen = self.screen,
            .region = regions.top,
        };

        switch (keep) {
            .top => {},
            .bottom => std.mem.swap(@This(), self, &other),
        }

        return other;
    }
};

pub const TextInput = struct {
    hash: u64 = 0,
    cursor: u32 = 0,
    text: std.ArrayList(u8),

    fn init(alloc: std.mem.Allocator) @This() {
        var self = @This(){ .text = .init(alloc) };
        self.update_hash();
        return self;
    }

    fn deinit(self: *@This()) void {
        self.text.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.hash = 0;
        self.cursor = 0;
        self.text.clearRetainingCapacity();
        self.update_hash();
    }

    pub fn left(self: *@This()) void {
        self.cursor -|= 1;
    }

    pub fn right(self: *@This()) void {
        self.cursor += 1;
        if (self.cursor > self.text.items.len) {
            self.cursor = cast(u32, self.text.items.len);
        }
    }

    pub fn left_word(self: *@This()) void {
        self.left();
        while (true) {
            if (' ' == self.peek_back() orelse return) {
                return;
            } else {
                self.left();
            }
        }
    }

    pub fn right_word(self: *@This()) void {
        self.right();
        while (true) {
            if (' ' == self.peek() orelse return) {
                return;
            } else {
                self.right();
            }
        }
    }

    fn update_hash(self: *@This()) void {
        var hasher = std.hash.Wyhash.init(0);
        // we don't want it to be 0 ever
        hasher.update(&.{42});
        hasher.update(self.text.items);
        self.hash = hasher.final();
    }

    pub fn write(self: *@This(), byte: u8) !void {
        defer self.update_hash();
        try self.text.insert(self.cursor, byte);
        self.cursor += 1;
    }

    pub fn peek(self: *@This()) ?u8 {
        if (self.text.items.len > self.cursor) {
            return self.text.items[self.cursor];
        } else {
            return null;
        }
    }

    pub fn peek_back(self: *@This()) ?u8 {
        if (self.text.items.len >= self.cursor and self.cursor > 0) {
            return self.text.items[self.cursor - 1];
        } else {
            return null;
        }
    }

    pub fn back(self: *@This()) ?u8 {
        defer self.update_hash();
        if (self.text.items.len >= self.cursor and self.cursor > 0) {
            defer self.cursor -= 1;
            return self.text.orderedRemove(self.cursor - 1);
        } else {
            return null;
        }
    }

    fn draw(self: *const @This(), surf: *Surface, cursor: bool) !void {
        try surf.draw_buf(self.text.items[0..self.cursor]);
        if (cursor) try surf.apply_style(.invert);
        if (self.text.items.len > self.cursor) {
            try surf.draw_buf(self.text.items[self.cursor..][0..1]);
        } else {
            try surf.draw_buf(" ");
        }
        if (cursor) try surf.apply_style(.reset);
        if (self.text.items.len > self.cursor + 1) {
            try surf.draw_buf(self.text.items[self.cursor + 1 ..]);
        }
    }
};

pub const Toaster = struct {
    alloc: std.mem.Allocator,
    id: Id = 0,
    // toasts need to maintain order even when adding/removing items
    toasts: std.AutoArrayHashMap(Id, Toast),

    pub const Id = u32;
    pub const Toast = struct {
        msg: []const u8,
        mode: Mode,

        pub const Mode = union(enum) {
            err: anyerror,
            success,
            info,
            warn,
            none,
        };
    };

    pub fn deinit(self: *@This()) void {
        var it = self.toasts.iterator();
        while (it.next()) |toast| {
            self.alloc.free(toast.value_ptr.*.msg);
        }
        self.toasts.deinit();
    }

    pub fn add(self: *@This(), toast: Toast) !Id {
        defer self.id += 1;
        const id = self.id;
        try self.toasts.put(id, toast);
        return id;
    }

    pub fn remove(self: *@This(), id: Id) void {
        const toast = self.toasts.fetchOrderedRemove(id) orelse return;
        self.alloc.free(toast.value.msg);
    }

    fn render(self: *@This(), surface: *Surface, app: *App, dir: enum { down, up }) !void {
        const temp = app.arena.allocator();
        var buf = std.ArrayList(Toaster.Toast).init(temp);

        var it = self.toasts.iterator();
        while (it.next()) |e| try buf.append(e.value_ptr.*);

        var toast: Surface = undefined;
        for (buf.items) |e| {
            var height = utils_mod.LineIterator.init(e.msg).count_height();
            height += 2;

            switch (dir) {
                .up => {
                    toast = try surface.split_y(height, .gap, .bottom);
                },
                .down => {
                    toast = try surface.split_y(-height, .gap, .top);
                },
            }

            try toast.apply_style(.{ .foreground_color = switch (e.mode) {
                .err => .from_theme(.errors),
                .warn => .from_theme(.warnings),
                .info => .from_theme(.info),
                .success => .from_theme(.success),
                .none => .from_theme(.dim_text),
            } });
            try toast.clear();
            try toast.draw_border(symbols.thin.square);
            if (e.mode == .err) {
                try toast.apply_style(.{ .foreground_color = .from_theme(.max_contrast) });
                try toast.apply_style(.bold);
                try toast.draw_border_heading(try std.fmt.allocPrint(temp, " {any} ", .{e.mode.err}));
            }
            try toast.apply_style(.reset);

            try toast.draw_buf(e.msg);
        }
    }
};

pub const HelpSlate = struct {
    alloc: std.mem.Allocator,
    action_help_map: ActionHelpMap,

    const ActionHelpMap = std.AutoHashMap(Action, []const u8);

    pub fn init(alloc: std.mem.Allocator) !@This() {
        var map = ActionHelpMap.init(alloc);
        errdefer map.deinit();

        for (event_mod.action_help) |help| {
            try map.put(help.action, help.help);
        }

        return .{
            .alloc = alloc,
            .action_help_map = map,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.action_help_map.deinit();
    }

    // TODO: make window width dynamic with a min size
    pub fn render(self: *@This(), surface: *Surface, app: *App) !void {
        const temp = app.arena.allocator();
        const cmp = event_mod.InputActionMap.Input.HashCtx{};

        const HelpItem = struct {
            key: []const u8,
            desc: []const u8,
        };
        var help_items = std.ArrayList(HelpItem).init(temp);
        var scratch = std.ArrayList(u8).init(temp);

        var it = app.input_action_map.map.iterator();
        while (it.next()) |iam| {
            if (!cmp.eql_state(iam.key_ptr.state, app.state)) continue;
            const help = self.action_help_map.get(iam.value_ptr.*) orelse {
                std.log.debug("missing help entry for: {any}", .{iam.value_ptr.*});
                return error.MissingHelpEntry;
            };
            switch (iam.key_ptr.input) {
                inline .key, .functional, .mouse => |key| if (key.action == .repeat) continue,
                else => continue,
            }
            switch (iam.value_ptr.*) {
                // .toggle_help => continue,
                else => {},
            }
            switch (iam.key_ptr.input) {
                .key => |key| {
                    // NOTE: key + shift is usually a different key. ('k' vs 'K')
                    //  BUT, here we usually want it to work with/without kitty kb protocol
                    //  so we add keys with and without .shift
                    if (key.mod.shift) continue;
                },
                else => {},
            }

            switch (iam.key_ptr.input) {
                inline .key, .functional, .mouse => |key| switch (key.action) {
                    .release => try scratch.writer().print("release ", .{}),
                    .repeat, .none, .press => {},
                },
                else => {},
            }
            switch (iam.key_ptr.input) {
                .key => |key| {
                    inline for (std.meta.fields(@TypeOf(key.mod))) |field| {
                        if (comptime std.mem.eql(u8, field.name, "shift")) continue;
                        if (@field(key.mod, field.name)) {
                            try scratch.writer().print("{s} + ", .{field.name});
                        }
                    }
                },
                .functional => |key| {
                    inline for (std.meta.fields(@TypeOf(key.mod))) |field| {
                        if (@field(key.mod, field.name)) {
                            try scratch.writer().print("{s} + ", .{field.name});
                        }
                    }
                },
                else => {},
            }
            switch (iam.key_ptr.input) {
                .key => |key| {
                    switch (key.key) {
                        ' ' => try scratch.writer().print("space", .{}),
                        else => try scratch.writer().print("{c}", .{key.key}),
                    }
                },
                .functional => |key| {
                    try scratch.writer().print("{s}", .{@tagName(key.key)});
                },
                .mouse => |key| {
                    try scratch.writer().print("mouse {s}", .{@tagName(key.key)});
                },
                else => {},
            }

            try help_items.append(.{ .key = try scratch.toOwnedSlice(), .desc = help });
        }

        const SortCtx = struct {
            fn lessThan(_: @This(), lhs: HelpItem, rhs: HelpItem) bool {
                if (std.mem.eql(u8, lhs.desc, rhs.desc)) {
                    return std.mem.lessThan(u8, lhs.key, rhs.key);
                }
                return std.mem.lessThan(u8, lhs.desc, rhs.desc);
            }
        };
        std.mem.sort(HelpItem, help_items.items, SortCtx{}, SortCtx.lessThan);

        // +2 for border :|
        surface.region = surface.region.split_y(-cast(i32, help_items.items.len + 2), false).bottom;

        try surface.clear();
        try surface.apply_style(.bold);
        try surface.apply_style(.{ .foreground_color = .from_theme(.bright_info) });
        try surface.draw_border(symbols.thin.rounded);
        try surface.apply_style(.{ .foreground_color = .from_theme(.default_foreground) });
        try scratch.writer().print(" Help: {s} ", .{app.state.short_display()});
        try surface.draw_border_heading(scratch.items);
        try surface.apply_style(.reset);

        const desc = surface;
        var keys = try desc.split_x(20, .gap, .right);

        var i: u32 = 0;
        while (!desc.is_full()) {
            defer i += 1;
            if (i >= help_items.items.len) {
                break;
            }
            const item = help_items.items[i];

            const pad = keys.region.size.x - @as(i32, @intCast(item.key.len));
            for (0..@intCast(@max(0, pad))) |_| {
                try keys.draw_buf(" ");
            }
            try keys.apply_style(.bold);
            try keys.apply_style(.{ .foreground_color = .from_theme(.alt_info) });
            try keys.draw_bufln(item.key);
            try keys.apply_style(.reset);

            try desc.apply_style(.bold);
            try desc.apply_style(.{ .foreground_color = .from_theme(.info) });
            try desc.draw_bufln(item.desc);
            try desc.apply_style(.reset);
        }
    }
};

const JjazyLogs = struct {};

fn DiffSlate(Op: type) type {
    return struct {
        alloc: std.mem.Allocator,
        cache: Cache,
        context: u32 = 3,

        const Hash = struct {
            hash: Op.Hash,
            context: u32,
        };
        pub const Diff = struct {
            y: i32 = 0,
            buf: jj_mod.Formatted = .{},
            status: jj_mod.Formatted = .{},

            fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
                alloc.free(self.buf.buf);
                alloc.free(self.status.buf);
            }
        };
        const Cache = utils_mod.DllLruCache(Hash, Diff, .{ .ptr = .follow });

        fn deinit(self: *@This()) void {
            while (self.cache.pop()) |e| {
                e.val.deinit(self.alloc);
            }
            self.cache.deinit();
        }

        pub fn put(self: *@This(), hash: Op.Hash, context: u32, val: Diff) !void {
            try self.cache.put(.{ .hash = hash, .context = context }, val);
        }

        pub fn get(self: *@This(), hash: Op.Hash, op: Cache.Op) ?*Diff {
            return self.cache.get(.{ .hash = hash, .context = self.context }, op);
        }

        pub fn getOrPut(self: *@This(), hash: Op.Hash, context: u32) !Cache.GetOrPutEntry {
            return try self.cache.getOrPut(.{ .hash = hash, .context = context });
        }

        fn render(self: *@This(), surface: *Surface, app: *App, focused: Op) !void {
            _ = app;
            defer while (self.cache.retaining_pop(100)) |diff| {
                diff.val.deinit(self.alloc);
            };
            if (self.get(focused.hash, .touch)) |diff| {
                diff.y = @max(0, diff.y);
                // +2 just so it is visually obvious in the UI that the diff has ended
                diff.y = @min(diff.y, cast(i32, diff.buf.height + diff.status.height) - surface.region.size.y + 2);

                var skip_y = diff.y;
                var it = utils_mod.LineIterator.init(diff.status.buf);
                while (it.next()) |line| {
                    if (surface.y < skip_y) {
                        skip_y -= 1;
                        continue;
                    }
                    try surface.draw_bufln(line);

                    if (surface.is_full()) break;
                }
                if (surface.is_full()) return;

                it = utils_mod.LineIterator.init(diff.buf.buf);
                while (it.next()) |line| {
                    if (surface.y < skip_y) {
                        skip_y -= 1;
                        continue;
                    }
                    try surface.draw_bufln(line);

                    if (surface.is_full()) break;
                }
            } else {
                try surface.draw_buf(" loading ... ");
            }
        }
    };
}

const BookmarkSlate = struct {
    alloc: std.mem.Allocator,
    buf: []const u8,
    it: jj_mod.Bookmark.Parsed.Iterator,
    y: i32 = 0,
    skip_y: i32 = 0,

    arena: std.heap.ArenaAllocator,
    bookmarks_order: std.ArrayList([]const u8),
    // ArrayXar prevents memory wastage through realloc in arena allocators
    bookmarks: std.StringHashMap(utils_mod.ArrayXar(jj_mod.Bookmark.Parsed, 2)),
    selected_bookmark: ?jj_mod.Bookmark.Parsed = null,

    input_hash: u64 = 0,
    bookmark_searcher: search_mod.SublimeSearcher,
    bookmark_search_collector: search_mod.SearchCollector,
    searched_bookmarks: []const search_mod.SearchCollector.Match = &.{},

    fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .alloc = alloc,
            .arena = .init(alloc),
            .buf = &.{},
            .it = .init(alloc, &.{}),
            .bookmarks_order = .init(alloc),
            .bookmarks = .init(alloc),
            .bookmark_searcher = .init(alloc, .{}),
            .bookmark_search_collector = .init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        self.alloc.free(self.buf);
        self.it.deinit();
        self.bookmarks_order.deinit();
        self.bookmarks.deinit();
        self.arena.deinit();
        self.selected_bookmark = null;
        self.bookmark_searcher.deinit();
        self.bookmark_search_collector.deinit();
    }

    pub fn update(self: *@This(), buf: jj_mod.Formatted, app: *App) !void {
        self.alloc.free(self.buf);
        self.selected_bookmark = null;
        self.y = 0;
        self.buf = buf.buf;
        self.input_hash = 0;
        try self._update_cache(app);
        try self.maybe_update_search(&app.renderer);
    }

    fn _update_cache(self: *@This(), app: *App) !void {
        _ = self.arena.reset(.retain_capacity);
        self.bookmarks_order.clearRetainingCapacity();
        self.bookmarks.clearRetainingCapacity();
        self.it.reset(self.buf);
        while (try self.it.next()) |bookmark| {
            if (bookmark.parsed.target.len > 1) {
                try app._toast(.{ .err = error.ManyTargets }, try std.fmt.allocPrint(
                    app.alloc,
                    "bookmark {s} has {d} targets. but jjazy can only handle 1 at the moment",
                    .{ bookmark.parsed.name, bookmark.parsed.target.len },
                ));
                continue;
            }

            const b = try self.bookmarks.getOrPut(bookmark.parsed.name);
            if (!b.found_existing) {
                b.value_ptr.* = .init(self.arena.allocator());
                try self.bookmarks_order.append(bookmark.parsed.name);
            }
            try b.value_ptr.append(bookmark);
        }
    }

    fn maybe_update_search(self: *@This(), renderer: *Renderer) !void {
        if (renderer.text_input.hash == self.input_hash) return;
        self.input_hash = renderer.text_input.hash;
        self.searched_bookmarks = try self.bookmark_search_collector.reorder_strings(
            self.bookmarks_order.items,
            renderer.text_input.text.items,
            &self.bookmark_searcher,
            .insensitive,
        );
    }

    fn reset(self: *@This()) void {
        self.y = 0;
        self.it.reset(self.buf);
    }

    // TODO: make window width dynamic with a min size
    fn render(self: *@This(), surface: *Surface, renderer: *Renderer, app: *App, v: struct {
        update_search: bool = true,
    }, include: struct {
        local_only: bool = true,
        remotes: bool = true,
        git_as_remote: bool = false,
    }, show: struct {
        targets: bool = true,
    }) !void {
        if (v.update_search) {
            try self.maybe_update_search(renderer);
        }
        try surface.clear();

        try surface.apply_style(.bold);
        try surface.draw_border(symbols.thin.rounded);
        try surface.draw_border_heading(" Bookmarks ");
        try surface.apply_style(.reset);

        var gutter = try surface.split_x(2, .gap, .right);

        self.y = @max(0, self.y);
        if (self.skip_y > self.y) {
            self.skip_y = self.y;
        }

        var ended = false;
        var i: i32 = 0;
        for (self.searched_bookmarks, 0..) |match, j| {
            var it = self.bookmarks.get(match.string).?.iterator(.{});
            while (it.next()) |bookmark| {
                if (!include.local_only and bookmark.parsed.remote == null) continue;
                if (!include.remotes and bookmark.parsed.remote != null) continue;
                if (!include.git_as_remote and std.mem.eql(u8, bookmark.parsed.remote orelse &.{}, "git")) continue;

                defer i += 1;
                if (self.skip_y > i) {
                    continue;
                }

                try surface.apply_style(.{ .foreground_color = .from_theme(.info) });
                try surface.draw_buf(bookmark.parsed.name);
                try surface.apply_style(.reset);

                if (show.targets) for (bookmark.parsed.target) |t| if (t) |target| {
                    try surface.draw_buf(" ");
                    try surface.apply_style(.{ .foreground_color = .from_theme(.default_foreground) });
                    try surface.draw_buf(target[0..8]);
                    try surface.apply_style(.reset);
                };

                if (bookmark.parsed.remote) |remote| {
                    try surface.apply_style(.{ .foreground_color = .from_theme(.alt_info) });
                    try surface.draw_buf(" @");
                    try surface.draw_buf(remote);
                    try surface.apply_style(.reset);
                }
                try surface.new_line();

                if (i == self.y) {
                    self.selected_bookmark = bookmark.*;
                    try gutter.draw_bufln("->");
                } else {
                    try gutter.new_line();
                }

                if (surface.is_full()) break;
            }
            ended = ended or (it.ended() and self.searched_bookmarks.len == j + 1);
            if (surface.is_full()) break;
        }

        if (ended and self.y >= i and i > 0) {
            self.y = i - 1;
        }

        if (self.y >= i and !ended and i > 0) {
            self.skip_y += 1;
            try app._send_event(.rerender);
        }
    }
};

const LogSlate = struct {
    y: i32 = 0,
    skip_y: i32 = 0,
    limit: u32 = 200,
    request_count: u32 = 0,
    status: jj_mod.Formatted,
    changes: jj_mod.Change.Parsed.Iterator,
    focused_change: jj_mod.Change = .{},
    alloc: std.mem.Allocator,
    // arrayhashmap to preserve insertion order
    selected_changes: std.AutoArrayHashMap(jj_mod.Change, void),

    fn deinit(self: *@This()) void {
        self.alloc.free(self.status.buf);
        self.changes.deinit();
        self.selected_changes.deinit();
    }

    pub fn update(self: *@This(), status: jj_mod.Formatted) !void {
        self.alloc.free(self.status.buf);
        self.status = status;
        self.changes.reset(status.buf);

        if (std.mem.eql(u8, self.focused_change.id[0..], (jj_mod.Change{}).id[0..]) and self.y == 0) {
            return;
        }
        defer self.changes.reset(status.buf);
        var i: i32 = 0;
        while (try self.changes.next()) |parsed| {
            defer i += 1;
            const change = jj_mod.Change.from_parsed(&parsed);
            if (std.mem.eql(u8, self.focused_change.id[0..], change.id[0..])) {
                self.y = i;
                return;
            }
        }
    }

    pub fn focus_commit(self: *@This(), commit_id: []const u8) !void {
        self.changes.reset(self.status.buf);
        var i: i32 = 0;
        while (try self.changes.next()) |parsed| {
            defer i += 1;
            const change = jj_mod.Change.from_parsed(&parsed);
            if (std.mem.eql(u8, parsed.parsed.commit_id, commit_id)) {
                self.y = i;
                self.skip_y = @max(self.y - 2, 0);
                self.focused_change = change;
                break;
            }
        }
    }

    fn render(
        self: *@This(),
        surface: *Surface,
        app: *App,
        state: State,
        tropes: anytype,
    ) !void {
        self.y = @max(0, self.y);
        if (self.skip_y > self.y) {
            self.skip_y = self.y;
        }

        var gutter = try surface.split_x(3, .none, .right);

        var i: i32 = 0;
        self.changes.reset(self.status.buf);
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

        if (self.y >= i and !self.changes.ended() and i > 0) {
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

    pub fn update(self: *@This(), oplog: []const u8) !void {
        self.alloc.free(self.oplog);
        self.oplog = oplog;
        self.ops.reset(oplog);

        if (std.mem.eql(u8, self.focused_op.hash[0..], (jj_mod.Operation{}).hash[0..]) and self.y == 0) {
            return;
        }
        defer self.ops.reset(oplog);
        var i: i32 = 0;
        while (try self.ops.next()) |parsed| {
            defer i += 1;
            const op = jj_mod.Operation.from_parsed(&parsed);
            if (std.mem.eql(u8, self.focused_op.hash[0..], op.hash[0..])) {
                self.y = i;
                return;
            }
        }
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

        var gutter = try surface.split_x(3, .none, .right);

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

        if (self.y >= i and !self.ops.ended() and i > 0) {
            self.skip_y += 1;
            try app._send_event(.rerender);
        }
    }
};

pub const FileTree = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    height: u32 = 0,
    root: Node,

    pub const Node = struct {
        path: []const u8,
        name: []const u8,
        has_conflict_somewhere_inside: bool = false,
        typ: enum { dir, file },
        depth: u32,
        status: ?jj_mod.Schema.FileTreeDiffEntry.Status = null,
        aggregate_statuses: std.EnumSet(jj_mod.Schema.FileTreeDiffEntry.Status) = .initEmpty(),
        original_name: ?[]const u8 = null,

        collapsed: bool = true,
        children_names: std.StringHashMapUnmanaged(u32) = .empty,
        children: std.ArrayListUnmanaged(Node) = .empty,

        pub const root = @This(){ .path = "./", .name = "", .depth = 0, .typ = .dir, .collapsed = false };

        pub fn find_child(self: *@This(), path: []const u8) ?*Node {
            if (std.mem.eql(u8, self.path, path)) return self;
            for (self.children.items) |*child| {
                if (child.find_child(path)) |found| return found;
            }
            return null;
        }
    };

    pub fn init(alloc: std.mem.Allocator) @This() {
        return .{ .alloc = alloc, .arena = .init(alloc), .root = .root };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.arena.reset(.retain_capacity);
        self.root = .root;
    }

    pub fn clear_statuses(self: *@This()) void {
        const Clearer = struct {
            fn clear(node: *Node) void {
                node.status = null;
                node.aggregate_statuses = .initEmpty();
                node.original_name = null;
                for (node.children.items) |*child| {
                    clear(child);
                }
            }
        };
        Clearer.clear(&self.root);
    }

    pub fn consume_file_path(self: *@This(), path: []const u8, conflict: bool) !void {
        const alloc = self.arena.allocator();
        var it = try std.fs.path.componentIterator(path);

        var node = &self.root;
        while (it.next()) |comp| {
            const child_index = node.children_names.get(comp.name) orelse blk: {
                const index: u32 = @intCast(node.children.items.len);
                const duped_name = try alloc.dupe(u8, comp.name);
                try node.children_names.put(alloc, duped_name, index);
                const child = try node.children.addOne(alloc);
                child.* = Node{
                    .path = try alloc.dupe(u8, comp.path),
                    .name = duped_name,
                    .typ = if (it.peekNext() == null) .file else .dir,
                    .depth = node.depth + 1,
                };
                break :blk index;
            };
            const child = &node.children.items[child_index];

            child.has_conflict_somewhere_inside = child.has_conflict_somewhere_inside or conflict;
            self.height = @max(self.height, child.depth);
            node = child;
        }
    }

    pub fn set_node_status(self: *@This(), path: []const u8, status: jj_mod.Schema.FileTreeDiffEntry.Status, original_path: ?[]const u8) !void {
        var it = try std.fs.path.componentIterator(path);
        var node = &self.root;
        while (it.next()) |comp| {
            const child_index = node.children_names.get(comp.name) orelse return;
            const child = &node.children.items[child_index];
            child.aggregate_statuses.insert(status);
            if (it.peekNext() == null) {
                child.status = status;
                if (status == .renamed and original_path != null) {
                    child.original_name = std.fs.path.basename(original_path.?);
                }
            }
            node = child;
        }
    }

    pub fn sort_dirs_first(self: *@This()) void {
        const Sorter = struct {
            const Ctx = struct {
                fn lessThan(_: @This(), lhs: Node, rhs: Node) bool {
                    if (lhs.typ != rhs.typ) return lhs.typ == .dir;
                    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
                }
            };
            fn sort(node: *Node) void {
                std.sort.block(Node, node.children.items, Ctx{}, Ctx.lessThan);
                // Rebuild children_names map because indices changed
                node.children_names.clearRetainingCapacity();
                for (node.children.items, 0..) |*child, i| {
                    node.children_names.putAssumeCapacity(child.name, @intCast(i));
                    sort(child);
                }
            }
        };
        Sorter.sort(&self.root);
    }

    pub fn iterator(self: *@This(), skip_removed: bool) !Iterator {
        var indices = try std.ArrayListUnmanaged(Iterator.IterNode).initCapacity(self.alloc, self.height + 1);
        indices.appendAssumeCapacity(.{ .node = &self.root, .index = 0, .iter_index = 0 });
        return .{
            .alloc = self.alloc,
            .root = &self.root,
            .indices = indices,
            .skip_removed = skip_removed,
        };
    }

    pub fn find_node(self: *@This(), path: []const u8) ?*Node {
        return self.root.find_child(path);
    }

    pub const Iterator = struct {
        index: u32 = 0,
        root: *Node,
        alloc: std.mem.Allocator,
        indices: std.ArrayListUnmanaged(IterNode),
        skip_removed: bool,

        const IterNode = struct {
            node: *Node,
            index: u32,
            iter_index: u32,
        };

        pub fn deinit(self: *@This()) void {
            self.indices.deinit(self.alloc);
        }

        pub fn next(self: *@This()) ?IterNode {
            while (true) {
                // If stack empty → finished
                var frame = if (self.indices.items.len > 0) &self.indices.items[self.indices.items.len - 1] else return null;

                // Otherwise try to descend into children
                if (frame.node.children.items.len > frame.index and !frame.node.collapsed) {
                    // Push next child
                    const child = &frame.node.children.items[frame.index];
                    frame.index += 1;

                    if (self.skip_removed and child.status == .removed) {
                        continue;
                    }

                    self.index += 1;
                    const node = self.indices.addOneAssumeCapacity();
                    node.* = .{
                        .node = child,
                        .index = 0,
                        .iter_index = self.index,
                    };
                    return node.*;
                }

                // Finished this node → pop and continue upward
                _ = self.indices.pop();
            }
        }

        pub fn parent(self: *@This()) ?IterNode {
            // NOTE: > 2 because 0 is always root, and we don't want to return root
            if (self.indices.items.len > 2) {
                return self.indices.items[self.indices.items.len - 2];
            }
            return null;
        }

        pub fn reset(self: *@This()) void {
            self.index = 0;
            self.indices.clearRetainingCapacity();
            self.indices.appendAssumeCapacity(.{ .node = self.root, .index = 0, .iter_index = 0 });
        }

        pub fn ended(self: *@This()) bool {
            return self.indices.getLastOrNull() == null;
        }
    };
};

pub const FileTreeSlate = struct {
    alloc: std.mem.Allocator,
    cache: FileListCache,
    it: jj_mod.FileTreeEntry.Parsed.Iterator,
    diff_it: jj_mod.FileTreeDiffEntry.Parsed.Iterator,

    pub const FileList = struct {
        y: i32 = 0,
        skip_y: i32 = 0,
        focused_node: ?*FileTree.Node = null,
        change_status: jj_mod.Formatted = .{},
        files: jj_mod.Formatted = .{},
        diffs: ?jj_mod.Formatted = .{},
        tree: FileTree,
        it: ?FileTree.Iterator = null,

        pub fn init(
            alloc: std.mem.Allocator,
            it: *jj_mod.FileTreeEntry.Parsed.Iterator,
            change_status: jj_mod.Formatted,
            files: jj_mod.Formatted,
        ) !@This() {
            var tree = FileTree.init(alloc);
            errdefer tree.deinit();

            it.reset(files.buf);
            while (try it.next()) |parsed| {
                switch (parsed.parsed.file_type) {
                    .file => {},
                    .conflict => {},
                    else => continue,
                }
                try tree.consume_file_path(parsed.parsed.path, parsed.parsed.conflict);
            }

            tree.sort_dirs_first();
            return .{
                .change_status = change_status,
                .files = files,
                .tree = tree,
            };
        }

        fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.change_status.buf);
            alloc.free(self.files.buf);
            if (self.diffs) |diff| alloc.free(diff.buf);
            self.tree.deinit();
            if (self.it) |*it| it.deinit();
        }

        pub fn update_focused_node(self: *@This(), skip_removed: bool) !void {
            if (self.it == null) {
                self.it = try self.tree.iterator(skip_removed);
            }
            var it = &self.it.?;
            it.skip_removed = skip_removed;
            it.reset();
            var i: i32 = 0;
            while (it.next()) |e| {
                defer i += 1;
                if (i == self.y) {
                    self.focused_node = e.node;
                    return;
                }
            }
        }

        pub fn focus_parent(self: *@This(), skip_removed: bool) !?*const FileTree.Node {
            if (self.it == null) {
                self.it = try self.tree.iterator(skip_removed);
            }
            var it = &self.it.?;
            it.skip_removed = skip_removed;
            it.reset();
            while (it.next()) |e| {
                if (e.iter_index == self.y) {
                    const p = it.parent() orelse return null;
                    self.y = @intCast(p.iter_index);
                    self.skip_y = @min(self.y -| 2, self.skip_y);
                    return p.node;
                }
            }

            return null;
        }

        pub fn get_focused_file(self: *const @This()) ?[]const u8 {
            if (self.focused_node == null) return null;
            if (self.focused_node.?.typ != .file) return null;
            return self.focused_node.?.path;
        }
    };
    pub const FileListCache = utils_mod.DllLruCache(jj_mod.Change, FileList, .{ .ptr = .follow });

    fn deinit(self: *@This()) void {
        while (self.cache.pop()) |e| {
            var val = e.val;
            val.deinit(self.alloc);
        }
        self.cache.deinit();
        self.it.deinit();
        self.diff_it.deinit();
    }

    pub fn update_list(self: *@This(), change: jj_mod.Change, change_status: jj_mod.Formatted, files: jj_mod.Formatted, diffs: ?jj_mod.Formatted) !*FileList {
        const res = try self.cache.getOrPut(change);
        var list: *FileList = undefined;
        if (res.found_existing) {
            self.alloc.free(res.val.change_status.buf);
            self.alloc.free(res.val.files.buf);
            res.val.change_status = change_status;
            res.val.files = files;
            res.val.tree.clear_statuses();
            list = res.val;
        } else {
            res.val.* = try FileList.init(self.alloc, &self.it, change_status, files);
            list = res.val;
        }

        if (diffs) |d| {
            // Parse diffs and update nodes with status
            res.val.diffs = diffs;
            self.diff_it.reset(d.buf);
            while (try self.diff_it.next()) |parsed| {
                const diff_entry = parsed.parsed;
                // Ensure node exists (needed for removed files)
                try list.tree.consume_file_path(diff_entry.path, false);
                try list.tree.set_node_status(diff_entry.path, diff_entry.status, diff_entry.source.path);
            }
        }

        return list;
    }

    fn render(
        self: *@This(),
        surface: *Surface,
        renderer: *Renderer,
        app: *App,
    ) !void {
        defer while (self.cache.retaining_pop(100)) |e| {
            var val = e.val;
            val.deinit(self.alloc);
        };

        const is_diff_view = switch (app.state) {
            .file_tree => |m| m == .diff,
            else => false,
        };

        const change = renderer.log.focused_change;
        const tree = self.cache.get(change, .touch) orelse return;
        tree.y = @max(0, tree.y);

        if (tree.it == null) {
            tree.it = try tree.tree.iterator(!is_diff_view);
        }
        var it = &tree.it.?;
        it.skip_removed = !is_diff_view;
        it.reset();
        if (tree.skip_y > tree.y) {
            tree.skip_y = tree.y;
        }

        const status_draw_height: i32 = @intCast(@min(tree.change_status.height, 7));

        var gutter = try surface.split_x(3, .none, .right);
        _ = try gutter.split_y(status_draw_height, .gap, .bottom);
        var status = try surface.split_y(status_draw_height, .gap, .bottom);

        try status.draw_buf(tree.change_status.buf);

        it.reset();
        var i: i32 = 0;
        var ended = false;
        while (it.next()) |e| {
            defer i += 1;
            if (tree.skip_y > i) {
                continue;
            }

            const node = e.node;
            if (i == tree.y) {
                try gutter.draw_bufln("->");
                tree.focused_node = node;
            } else {
                try gutter.draw_bufln("  ");
            }

            try surface.apply_style(.faint);
            for (0..node.depth -| 1) |_| {
                try surface.draw_buf("  ");
                try surface.draw_buf(term_mod.symbols.border.thin.edges.vertical);
            }
            try surface.apply_style(.reset);

            const icon = renderer.icons.get_icon(node.path) orelse term_mod.Icons.Icon{
                .icon = if (node.typ == .dir) term_mod.Icons.icons.folder[0..] else term_mod.Icons.icons.file[0..],
                .color = .from_theme(.info),
            };

            try surface.apply_style(.{ .foreground_color = icon.color });
            try surface.draw_buf(icon.icon);
            try surface.apply_style(.reset);
            try surface.draw_buf(" ");

            switch (node.typ) {
                .dir => {
                    try surface.apply_style(.faint);
                    if (node.collapsed) {
                        try surface.draw_buf(term_mod.symbols.arrow.line.small.right);
                    } else {
                        try surface.draw_buf(term_mod.symbols.arrow.line.small.down);
                    }
                    try surface.apply_style(.reset);

                    try surface.apply_style(.bold);
                    try surface.apply_style(.{ .foreground_color = .from_theme(.info) });
                    if (is_diff_view and node.original_name != null) {
                        try surface.draw_buf(node.original_name.?);
                        try surface.draw_buf(" -> ");
                    }
                    try surface.draw_buf(node.name);
                    try surface.apply_style(.reset);

                    if (is_diff_view) {
                        var sit = node.aggregate_statuses.iterator();
                        while (sit.next()) |s| {
                            const char: u8 = switch (s) {
                                .modified => 'M',
                                .added => 'A',
                                .removed => 'D',
                                .copied => 'C',
                                .renamed => 'R',
                            };
                            const color = switch (s) {
                                .modified => term_mod.TermStyledGraphemeIterator.Color.from_theme(.warnings),
                                .added => term_mod.TermStyledGraphemeIterator.Color.from_theme(.success),
                                .removed => term_mod.TermStyledGraphemeIterator.Color.from_theme(.errors),
                                .copied => term_mod.TermStyledGraphemeIterator.Color.from_theme(.info),
                                .renamed => term_mod.TermStyledGraphemeIterator.Color.from_theme(.status),
                            };

                            try surface.draw_buf(" ");
                            try surface.apply_style(.{ .foreground_color = color });
                            try surface.draw_buf(&[_]u8{char});
                            try surface.apply_style(.reset);
                        }
                    }
                },
                .file => {
                    try surface.apply_style(.bold);
                    try surface.apply_style(.{ .foreground_color = .from_theme(.default_foreground) });
                    if (is_diff_view and node.original_name != null) {
                        try surface.draw_buf(node.original_name.?);
                        try surface.draw_buf(" -> ");
                    }
                    try surface.draw_buf(node.name);
                    try surface.apply_style(.reset);

                    if (is_diff_view) {
                        var sit = node.aggregate_statuses.iterator();
                        while (sit.next()) |s| {
                            const char: u8 = switch (s) {
                                .modified => 'M',
                                .added => 'A',
                                .removed => 'D',
                                .copied => 'C',
                                .renamed => 'R',
                            };
                            const color = switch (s) {
                                .modified => term_mod.TermStyledGraphemeIterator.Color.from_theme(.warnings),
                                .added => term_mod.TermStyledGraphemeIterator.Color.from_theme(.success),
                                .removed => term_mod.TermStyledGraphemeIterator.Color.from_theme(.errors),
                                .copied => term_mod.TermStyledGraphemeIterator.Color.from_theme(.info),
                                .renamed => term_mod.TermStyledGraphemeIterator.Color.from_theme(.status),
                            };

                            try surface.draw_buf(" ");
                            try surface.apply_style(.{ .foreground_color = color });
                            try surface.draw_buf(&[_]u8{char});
                            try surface.apply_style(.reset);
                        }
                    }
                },
            }

            if (node.has_conflict_somewhere_inside) {
                try surface.draw_buf(" ");
                try surface.apply_style(.{ .foreground_color = .from_theme(.errors) });
                try surface.draw_buf("conflict");
                try surface.apply_style(.reset);
            }

            try surface.draw_bufln("");

            if (surface.is_full()) break;
        }
        ended = it.ended();

        if (ended and tree.y >= i and i > 0) {
            tree.y = i - 1;
        }

        if (tree.y >= i and !ended and i > 0) {
            tree.skip_y += 1;
            try app._send_event(.rerender);
        }
    }
};

pub const FileShowSlate = struct {
    alloc: std.mem.Allocator,
    filecache: FileCache,

    pub const Key = struct {
        change_hash: jj_mod.Change.Hash,
        path: []const u8,
    };

    pub const CachedFile = struct {
        y: i32 = 0,
        len: i32 = 0,
        content: ?[]const u8 = null,

        diff_len: i32 = 0,
        diff: ?[]const u8 = null,
    };
    const FileCache = utils_mod.DllLruCache(Key, CachedFile, .{ .ptr = .follow });

    fn deinit(self: *@This()) void {
        while (self.filecache.pop()) |e| {
            self.alloc.free(e.key.path);
            if (e.val.content) |content| self.alloc.free(content);
            if (e.val.diff) |diff| self.alloc.free(diff);
        }
        self.filecache.deinit();
    }

    fn render(self: *@This(), surface: *Surface, app: *App, focused_change: jj_mod.Change, focused_file: ?[]const u8) !void {
        if (focused_file == null) {
            try surface.draw_buf(" no file selected ");
            return;
        }
        const key = Key{ .change_hash = focused_change.hash, .path = focused_file.? };

        defer while (self.filecache.retaining_pop(100)) |e| {
            self.alloc.free(e.key.path);
            if (e.val.content) |buf| self.alloc.free(buf);
            if (e.val.diff) |buf| self.alloc.free(buf);
        };

        if (self.filecache.get(key, .touch)) |cfile| {
            const is_diff_view = switch (app.state) {
                .file_tree => |m| m == .diff,
                else => false,
            };

            const content = if (is_diff_view and cfile.diff != null) cfile.diff.? else cfile.content orelse {
                try surface.draw_buf(" loading... ");
                return;
            };
            const len = if (is_diff_view and cfile.diff != null) cfile.diff_len else cfile.len;

            cfile.y = @max(0, cfile.y);
            cfile.y = @min(cfile.y, len - surface.region.size.y + 2);

            var it = utils_mod.LineIterator.init(content);
            var i: i32 = 0;
            while (it.next()) |line| {
                defer i += 1;
                if (i < cfile.y) continue;
                try surface.draw_bufln(line);
                if (surface.is_full()) break;
            }
        } else {
            try surface.draw_buf(" loading... ");
        }
    }
};

pub const Renderer = struct {
    screen: term_mod.Screen,
    icons: term_mod.Icons,

    log: LogSlate,
    evolog: LogSlate,
    oplog: OpLogSlate,
    diff: DiffSlate(jj_mod.Change),
    opshow: DiffSlate(jj_mod.Operation),
    file_tree: FileTreeSlate,
    file_show: FileShowSlate,
    bookmarks: BookmarkSlate,

    help: HelpSlate,
    toaster: Toaster,

    text_input: TextInput,
    mouse_regions: std.ArrayList(MouseRegion),

    x_split: f32 = 0.55,
    show_help: bool = false,

    rerender_pending_since: u64 = 0,
    rerender_pending_count: u64 = 0,
    render_count: u64 = 0,
    last_hash: u64 = 0,

    const MouseRegion = struct {
        region: lay_mod.Region,
        depth: f32,
        surface_id: u32,
        kind: event_mod.MouseRegionKind,
    };

    pub fn init(alloc: std.mem.Allocator, envmap: *const std.process.EnvMap, handler: type) !@This() {
        var icons = try term_mod.Icons.init(alloc);
        errdefer icons.deinit();

        var help = try HelpSlate.init(alloc);
        errdefer help.deinit();

        var screen = blk: {
            var term = try term_mod.Term.init(alloc, envmap);
            errdefer term.deinit();

            break :blk try term_mod.Screen.init(alloc, term);
        };
        errdefer screen.deinit();
        try screen.update_size();

        screen.term.register_signal_handlers(handler);
        errdefer screen.term.unregister_signal_handlers();

        try screen.term.uncook();
        errdefer screen.term.cook_restore() catch |e| utils_mod.dump_error(e);

        var self = @This(){
            .screen = screen,
            .icons = icons,
            .help = help,
            .log = .{
                .alloc = alloc,
                .status = .from(&.{}),
                .changes = .init(alloc, &[_]u8{}),
                .selected_changes = .init(alloc),
            },
            .evolog = .{
                .alloc = alloc,
                .status = .from(&.{}),
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
                .cache = .init(alloc),
            },
            .opshow = .{
                .alloc = alloc,
                .cache = .init(alloc),
            },
            .file_tree = .{
                .alloc = alloc,
                .cache = .init(alloc),
                .it = .init(alloc, &.{}),
                .diff_it = .init(alloc, &.{}),
            },
            .file_show = .{
                .alloc = alloc,
                .filecache = .init(alloc),
            },
            .bookmarks = .init(alloc),
            .toaster = .{
                .alloc = alloc,
                .toasts = .init(alloc),
            },
            .text_input = .init(alloc),
            .mouse_regions = .init(alloc),
        };

        try self.diff.put(self.log.focused_change.hash, self.diff.context, .{});
        try self.opshow.put(self.oplog.focused_op.hash, self.opshow.context, .{});

        return self;
    }

    pub fn deinit(self: *@This()) void {
        defer self.log.deinit();
        defer self.evolog.deinit();
        defer self.oplog.deinit();
        defer self.diff.deinit();
        defer self.opshow.deinit();
        defer self.file_tree.deinit();
        defer self.file_show.deinit();
        defer self.bookmarks.deinit();
        defer self.help.deinit();
        defer self.toaster.deinit();
        defer self.text_input.deinit();
        defer self.mouse_regions.deinit();
        defer self.icons.deinit();

        defer self.screen.deinit();
        defer self.screen.term.unregister_signal_handlers();
        defer self.screen.term.cook_restore() catch |e| utils_mod.dump_error(e);
    }

    fn _register_mouse_region(self: *@This(), kind: event_mod.MouseRegionKind, surface: *Surface) void {
        self.mouse_regions.append(.{
            .kind = kind,
            .surface_id = surface.id,
            .depth = surface.depth,
            .region = surface.region,
        }) catch |e| utils_mod.dump_error(e);
    }

    fn render_status_bar(self: *@This(), surface: *Surface, state: event_mod.State, temp: std.mem.Allocator) !void {
        if (options.env == .debug) {
            var colors = try surface.split_x(-32, .none, .left);

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
            try surface.draw_buf(" ");
            try surface.draw_buf(state.short_display());
            try surface.draw_buf(" ");
            try surface.apply_style(.reset);

            if (options.env == .debug) {
                try surface.draw_buf(" ");

                try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
                try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
                try surface.apply_style(.bold);
                try surface.draw_buf(try std.fmt.allocPrint(temp, " frame: {d} ", .{self.render_count}));
                try surface.apply_style(.reset);

                try surface.draw_buf(" ");
                try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
                try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
                try surface.apply_style(.bold);
                try surface.draw_buf(try std.fmt.allocPrint(temp, " log:{d} ", .{self.log.limit}));
                try surface.apply_style(.reset);

                try surface.draw_buf(" ");
                try surface.apply_style(.{ .background_color = .from_theme(.default_foreground) });
                try surface.apply_style(.{ .foreground_color = .from_theme(.default_background) });
                try surface.apply_style(.bold);
                try surface.draw_buf(try std.fmt.allocPrint(temp, " reqs:{d} ", .{self.log.request_count}));
                try surface.apply_style(.reset);
            }
        }
    }

    pub fn render(self: *@This(), app: *event_mod.App, tropes: anytype, temp: std.mem.Allocator) !void {
        const state = app.state;
        defer self.render_count += 1;

        self.x_split = @min(self.x_split, 1.0);
        self.x_split = @max(self.x_split, -1.0);
        self.mouse_regions.clearRetainingCapacity();

        {
            var status = try Surface.init(&self.screen, 0, .{});
            defer self._register_mouse_region(.status, &status);
            try status.clear();
            // try status.draw_border(symbols.thin.rounded);

            var bar = try status.split_y(-1, .none, .top);
            // defer self._register_mouse_region(.none, &bar);
            try self.render_status_bar(&bar, state, temp);

            const size = status.size();
            var diffs = try status.split_x(cast(i32, cast(f32, size.x) * @max(self.x_split, 0)), .border, .left);
            defer self._register_mouse_region(.diff, &diffs);

            if (self.x_split < 0) {
                const off = -cast(i32, cast(f32, size.x) * self.x_split);
                diffs.x_scroll += off;
            }

            switch (state) {
                .oplog => {
                    try self.oplog.render(&status, app);
                    try self.opshow.render(&diffs, app, self.oplog.focused_op);
                },
                .file_tree => {
                    try self.file_tree.render(&status, self, app);
                    if (self.file_tree.cache.get(self.log.focused_change, .touch)) |tree| {
                        const focused_file = tree.get_focused_file();
                        try self.file_show.render(&diffs, app, self.log.focused_change, focused_file);
                    }
                },
                .evolog => {
                    try self.evolog.render(&status, app, state, tropes);
                    try self.diff.render(&diffs, app, self.evolog.focused_change);
                },
                else => {
                    try self.log.render(&status, app, state, tropes);
                    try self.diff.render(&diffs, app, self.log.focused_change);
                },
            }

            const max_popup_region = self.screen.term.screen
                .split_y(-2, false).top
                .split_y(1, false).bottom
                .border_sub(.{ .x = 2 });

            if (tropes.bookmarks_enabled) {
                const popup_size = Vec2{ .x = 60, .y = 30 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var surface = try Surface.init(&self.screen, 1, .{ .origin = region.origin, .size = region.size });
                defer self._register_mouse_region(.bookmarks, &surface);

                if (tropes.bookmark_search_enabled or (self.text_input.text.items.len > 0 and !std.meta.eql(state, .{ .bookmark = .create }))) {
                    var input_box = try surface.split_y(3, .none, .bottom);

                    try input_box.clear();
                    try input_box.draw_border(symbols.thin.rounded);

                    try input_box.draw_border_heading(" Search ");

                    try self.text_input.draw(&input_box, tropes.bookmark_search_enabled);
                }

                if (std.meta.eql(state, .{ .bookmark = .view_goto }) or std.meta.eql(state, .{ .bookmark = .search_goto })) {
                    try self.bookmarks.render(&surface, self, app, .{}, .{}, .{});
                } else if (state == .bookmark) {
                    try self.bookmarks.render(&surface, self, app, .{
                        .update_search = state.bookmark != .create,
                    }, .{ .remotes = false }, .{});
                } else if (std.meta.eql(state, .{ .git = .push }) or std.meta.eql(state, .{ .git = .push_search })) {
                    try self.bookmarks.render(&surface, self, app, .{}, .{ .remotes = false }, .{});
                } else if (std.meta.eql(state, .{ .git = .fetch }) or std.meta.eql(state, .{ .git = .fetch_search }) or std.meta.eql(state, .{ .git = .fetch_new })) {
                    try self.bookmarks.render(&surface, self, app, .{}, .{ .remotes = false }, .{ .targets = false });
                } else unreachable;
            }

            if (state == .command or (state == .bookmark and state.bookmark == .create) or (state == .git and state.git == .fetch_new)) {
                const popup_size = Vec2{ .x = 55, .y = 5 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var input_box = try Surface.init(&self.screen, 5, .{ .origin = region.origin, .size = region.size });
                // defer self._register_mouse_region(.none, &input_box);
                try input_box.clear();
                try input_box.draw_border(symbols.thin.rounded);

                if (state == .command) {
                    try input_box.draw_border_heading(" Command ");
                } else if (state == .git and state.git == .fetch_new) {
                    try input_box.draw_border_heading(" Enter branch to fetch ");
                } else {
                    try input_box.draw_border_heading(" Enter new bookmark name ");
                }

                try self.text_input.draw(&input_box, true);
            }

            {
                const region = max_popup_region.split_x(-100, false).right;
                var surface = try Surface.init(&self.screen, 10, .{ .origin = region.origin, .size = region.size });
                // defer self._register_mouse_region(.none, &surface);
                try self.toaster.render(&surface, app, if (self.show_help or tropes.show_help) .up else .down);
            }

            if (self.show_help or tropes.show_help) {
                const screen = self.screen.term.screen;
                const r0 = screen.border_sub(.{ .x = 3, .y = 2 });
                const r1 = r0.split_x(-80, false).right;
                var help = try Surface.init(&self.screen, 4, .{
                    .origin = r1.origin,
                    .size = r1.size,
                });
                // defer self._register_mouse_region(.none, &help);
                try self.help.render(&help, app);
            }
        }
        try self.screen.flush_writes();
    }
};
