const std = @import("std");
const builtin = @import("builtin");
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

const Surface = struct {
    region: lay_mod.Region,

    y: i32 = 0,
    x: i32 = 0,

    y_scroll: i32 = 0,
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
        state: State,
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

        if (self.y >= i and !self.ops.ended() and i > 0) {
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
        len: i32 = 0,
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

    fn render(self: *@This(), surface: *Surface, app: *App, focused: jj_mod.Change) !void {
        _ = app;
        if (self.diffcache.getPtr(focused.hash)) |cdiff| if (cdiff.diff) |diff| {
            cdiff.y = @max(0, cdiff.y);
            // +2 just so it is visually obvious in the UI that the diff has ended
            cdiff.y = @min(cdiff.y, cdiff.len - surface.region.size.y + 2);

            var skip_y = cdiff.y;
            var it = utils_mod.LineIterator.init(diff);
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
        };
    }
};

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

    fn update(self: *@This(), buf: []const u8, app: *App) !void {
        self.alloc.free(self.buf);
        self.selected_bookmark = null;
        self.y = 0;
        self.buf = buf;
        try self._update_cache(app);
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

    fn reset(self: *@This()) void {
        self.y = 0;
        self.it.reset(self.buf);
    }

    fn get_selected(self: *@This()) ?jj_mod.Bookmark.Parsed {
        return self.selected_bookmark;
    }

    // TODO: make window width dynamic with a min size
    fn render(self: *@This(), surface: *Surface, app: *App, include: struct {
        local_only: bool = true,
        remotes: bool = true,
        git_as_remote: bool = false,
    }, show: struct {
        targets: bool = true,
    }) !void {
        self.searched_bookmarks = try self.bookmark_search_collector.reorder_strings(
            self.bookmarks_order.items,
            app.text_input.text.items,
            &self.bookmark_searcher,
            .insensitive,
        );

        try surface.clear();

        try surface.apply_style(.bold);
        try surface.draw_border(symbols.thin.rounded);
        try surface.draw_border_heading(" Bookmarks ");
        try surface.apply_style(.reset);

        var gutter = try surface.split_x(2, .gap);
        std.mem.swap(Surface, surface, &gutter);

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

                if (show.targets) for (bookmark.parsed.target) |target| {
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

const HelpSlate = struct {
    alloc: std.mem.Allocator,
    action_help_map: ActionHelpMap,

    const ActionHelpMap = std.AutoHashMap(Action, []const u8);

    const action_help = [_]struct {
        action: Action,
        help: []const u8,
    }{
        .{
            .action = .{ .fancy_terminal_features_that_break_gdb = .enable },
            .help = "Enable fancy features that break gdb",
        },
        .{
            .action = .{ .fancy_terminal_features_that_break_gdb = .disable },
            .help = "Disable fancy features that break gdb",
        },
        .{
            .action = .trigger_breakpoint,
            .help = "Trigger breakpoint",
        },
        .{
            .action = .refresh_master_content,
            .help = "Refresh Master Content",
        },
        .{
            .action = .{ .scroll = .{ .target = .log, .dir = .up } },
            .help = "Scroll up logs",
        },
        .{
            .action = .{ .scroll = .{ .target = .log, .dir = .down } },
            .help = "Scroll down logs",
        },
        .{
            .action = .{ .scroll = .{ .target = .oplog, .dir = .up } },
            .help = "Scroll up operation logs",
        },
        .{
            .action = .{ .scroll = .{ .target = .oplog, .dir = .down } },
            .help = "Scroll down operation logs",
        },
        .{
            .action = .{ .scroll = .{ .target = .bookmarks, .dir = .up } },
            .help = "Scroll up bookmarks",
        },
        .{
            .action = .{ .scroll = .{ .target = .bookmarks, .dir = .down } },
            .help = "Scroll down bookmarks",
        },
        .{
            .action = .{ .scroll = .{ .target = .diff, .dir = .up } },
            .help = "Scroll up diff",
        },
        .{
            .action = .{ .scroll = .{ .target = .diff, .dir = .down } },
            .help = "Scroll up diff",
        },
        .{
            .action = .{ .resize_master = .left },
            .help = "Decrease master area",
        },
        .{
            .action = .{ .resize_master = .right },
            .help = "Increase master area",
        },
        .{
            .action = .switch_state_to_log,
            .help = "Return to default mode",
        },
        .{
            .action = .select_focused_change,
            .help = "Select focused change",
        },
        .{
            .action = .{ .set_where = .onto },
            .help = "Apply current action Onto selected change",
        },
        .{
            .action = .{ .set_where = .after },
            .help = "Apply current action After selected change",
        },
        .{
            .action = .{ .set_where = .before },
            .help = "Apply current action Before selected change",
        },
        .{
            .action = .send_quit_event,
            .help = "Quit jjazy",
        },
        .{
            .action = .switch_state_to_new,
            .help = "Start jj new",
        },
        .{
            .action = .jj_edit,
            .help = "jj edit",
        },
        .{
            .action = .switch_state_to_git,
            .help = "Git commands",
        },
        .{
            .action = .switch_state_to_rebase_onto,
            .help = "Start jj rebase",
        },
        .{
            .action = .switch_state_to_squash,
            .help = "Start jj squash",
        },
        .{
            .action = .switch_state_to_abandon,
            .help = "Start jj abandon",
        },
        .{
            .action = .switch_state_to_oplog,
            .help = "View Operation logs",
        },
        .{
            .action = .switch_state_to_duplicate,
            .help = "Start jj duplicate",
        },
        .{
            .action = .switch_state_to_bookmarks_view,
            .help = "View bookmarks",
        },
        .{
            .action = .toggle_help,
            .help = "Toggle help menu",
        },
        .{
            .action = .jj_split,
            .help = "jj split",
        },
        .{
            .action = .jj_describe,
            .help = "jj describe",
        },
        .{
            .action = .switch_state_to_command,
            .help = "Execute arbitary command",
        },
        .{
            .action = .{ .apply_jj_rebase = .{ .ignore_immutable = false } },
            .help = "Apply jj rebase",
        },
        .{
            .action = .{ .apply_jj_rebase = .{ .ignore_immutable = true } },
            .help = "Apply jj rebase --ignore-immutable",
        },
        .{
            .action = .{ .apply_jj_abandon = .{ .ignore_immutable = false } },
            .help = "Apply jj abandon",
        },
        .{
            .action = .{ .apply_jj_abandon = .{ .ignore_immutable = true } },
            .help = "Apply jj abandon --ignore-immutable",
        },
        .{
            .action = .{ .apply_jj_squash = .{ .ignore_immutable = false } },
            .help = "Apply jj squash",
        },
        .{
            .action = .{ .apply_jj_squash = .{ .ignore_immutable = true } },
            .help = "Apply jj squash --ignore-immutable",
        },
        .{
            .action = .apply_jj_new,
            .help = "Apply jj new",
        },
        .{
            .action = .{ .execute_command_in_input_buffer = .{ .interactive = false } },
            .help = "Execute entered command",
        },
        .{
            .action = .{ .execute_command_in_input_buffer = .{ .interactive = true } },
            .help = "Execute entered interactive command",
        },
        .{
            .action = .apply_jj_op_restore,
            .help = "jj op restore",
        },
        .{
            .action = .apply_jj_duplicate,
            .help = "apply jj duplicate",
        },
        .{
            .action = .switch_state_to_bookmark_create,
            .help = "Create new bookmark",
        },
        .{
            .action = .new_commit_from_bookmark,
            .help = "jj new on selected bookmark",
        },
        .{
            .action = .{ .move_bookmark_to_selected = .{ .allow_backwards = false } },
            .help = "Move selected bookmark to selected change",
        },
        .{
            .action = .{ .move_bookmark_to_selected = .{ .allow_backwards = true } },
            .help = "Move selected bookmark to selected change (force)",
        },
        .{
            .action = .apply_jj_bookmark_delete,
            .help = "Delete selected bookmark",
        },
        .{
            .action = .{ .apply_jj_bookmark_forget = .{ .include_remotes = false } },
            .help = "Forget selected bookmark",
        },
        .{
            .action = .{ .apply_jj_bookmark_forget = .{ .include_remotes = true } },
            .help = "Forget selected bookmark (include remotes)",
        },
        .{
            .action = .apply_jj_bookmark_create_from_input_buffer_on_selected_change,
            .help = "Create new bookmark on selected change",
        },
        .{
            .action = .apply_jj_git_fetch,
            .help = "Git fetch",
        },
        .{
            .action = .switch_state_to_git_fetch,
            .help = "jj git fetch a remote",
        },
        .{
            .action = .apply_jj_git_push_all,
            .help = "Git push all",
        },
        .{
            .action = .switch_state_to_git_push,
            .help = "Git push a bookmark",
        },
        .{
            .action = .{ .apply_jj_git_push_selected = .{ .allow_new = false } },
            .help = "Git push selected bookmark",
        },
        .{
            .action = .{ .apply_jj_git_push_selected = .{ .allow_new = true } },
            .help = "Git push selected bookmark (allow new)",
        },
        .{
            .action = .start_search,
            .help = "Start Search",
        },
        .{
            .action = .{ .end_search = .{ .reset = true } },
            .help = "End Search (reset input)",
        },
        .{
            .action = .{ .end_search = .{ .reset = false } },
            .help = "End Search",
        },
    };

    fn init(alloc: std.mem.Allocator) !@This() {
        var map = ActionHelpMap.init(alloc);
        errdefer map.deinit();

        for (action_help) |help| {
            try map.put(help.action, help.help);
        }

        return .{
            .alloc = alloc,
            .action_help_map = map,
        };
    }

    fn deinit(self: *@This()) void {
        self.action_help_map.deinit();
    }

    // TODO: make window width dynamic with a min size
    fn render(self: *@This(), surface: *Surface, app: *App) !void {
        const temp = app.arena.allocator();
        const cmp = InputActionMap.Input.HashCtx{};

        const HelpItem = struct {
            key: []const u8,
            desc: []const u8,
        };
        var help_items = std.ArrayList(HelpItem).init(temp);
        var scratch = std.ArrayList(u8).init(temp);

        var it = app.input_action_map.map.iterator();
        while (it.next()) |iam| {
            if (!cmp.eql_state(iam.key_ptr.state, app.state)) continue;
            const help = self.action_help_map.get(iam.value_ptr.*) orelse return error.MissingHelpEntry;
            switch (iam.key_ptr.input) {
                inline .key, .functional, .mouse => |key| if (key.action == .repeat) continue,
                else => continue,
            }
            switch (iam.value_ptr.*) {
                .toggle_help => continue,
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

        try surface.apply_style(.{ .foreground_color = .from_theme(.default_foreground) });
        try surface.apply_style(.bold);

        try surface.clear();
        try surface.draw_border(symbols.thin.rounded);
        try scratch.writer().print(" Help: {s} ", .{app.state.short_display()});
        try surface.draw_border_heading(scratch.items);
        try surface.apply_style(.reset);

        const desc = surface;
        var keys = try desc.split_x(20, .gap);
        std.mem.swap(Surface, desc, &keys);

        var i: u32 = 0;
        while (!desc.is_full()) {
            defer i += 1;
            if (i >= help_items.items.len) {
                break;
            }
            const item = help_items.items[i];

            try keys.draw_bufln(item.key);
            try desc.draw_bufln(item.desc);
        }
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
        mode: Mode,

        const Mode = union(enum) {
            err: anyerror,
            success,
            info,
            warn,
            none,
        };
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
                    toast = try surface.split_y(height, .gap);
                    std.mem.swap(Surface, &toast, surface);
                },
                .down => {
                    toast = try surface.split_y(-height, .gap);
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

const JjazyLogs = struct {};

pub const Sleeper = struct {
    alloc: std.mem.Allocator,
    thread: std.Thread,
    quit: utils_mod.Fuse = .{},
    requests: utils_mod.Channel(Request),
    sleeps: std.ArrayList(Request),

    // not owned
    events: utils_mod.Channel(Event),

    const Request = struct { target_ts: i128, event: Event };

    pub fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(Event)) !*@This() {
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

    pub fn delay_event(self: *@This(), time_ms: i128, event: Event) !void {
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

            std.Thread.sleep(std.time.ns_per_ms * 2);
        }
    }
};

pub const State = union(enum(u8)) {
    log,
    oplog,
    bookmark: enum {
        view,
        create,
        search,
    },
    git: enum {
        none,
        fetch,
        push,
        fetch_search,
        push_search,
    },
    command,
    rebase: Where,
    duplicate: Where,
    new,
    squash,
    abandon,

    inline fn short_display(self: @This()) []const u8 {
        return switch (self) {
            inline .rebase, .duplicate => |_p, t| switch (_p) {
                inline else => |p| @tagName(t) ++ "." ++ @tagName(p),
            },
            inline .bookmark => |_p, t| switch (_p) {
                inline .view => @tagName(t),
                inline else => |p| @tagName(t) ++ "." ++ @tagName(p),
            },
            inline .git => |_p, t| switch (_p) {
                inline .none => @tagName(t),
                inline else => |p| @tagName(t) ++ "." ++ @tagName(p),
            },
            inline else => |_, t| @tagName(t),
        };
    }
};

const MouseRegionKind = enum {
    none,
    status,
    bookmarks,
    diff,
};

pub const Where = enum(u8) {
    onto,
    after,
    before,
};

pub const Event = union(enum) {
    sigwinch,
    rerender,
    scroll_update,
    diff_update: jj_mod.Change,
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
    scroll: struct { target: enum { log, oplog, diff, bookmarks }, dir: enum { up, down } },
    resize_master: enum { left, right },
    switch_state_to_log,
    select_focused_change,
    set_where: Where,
    send_quit_event,
    switch_state_to_new,
    jj_edit,
    switch_state_to_git,
    switch_state_to_rebase_onto,
    switch_state_to_squash,
    switch_state_to_abandon,
    switch_state_to_oplog,
    switch_state_to_duplicate,
    switch_state_to_bookmarks_view,
    toggle_help,
    jj_split,
    jj_describe,
    switch_state_to_command,
    apply_jj_rebase: struct { ignore_immutable: bool },
    apply_jj_abandon: struct { ignore_immutable: bool },
    apply_jj_squash: struct { ignore_immutable: bool },
    apply_jj_new,
    execute_command_in_input_buffer: struct { interactive: bool },
    apply_jj_op_restore,
    apply_jj_duplicate,
    switch_state_to_bookmark_create,
    new_commit_from_bookmark,
    move_bookmark_to_selected: struct { allow_backwards: bool },
    apply_jj_bookmark_delete,
    apply_jj_bookmark_forget: struct { include_remotes: bool },
    apply_jj_bookmark_create_from_input_buffer_on_selected_change,
    apply_jj_git_fetch,
    apply_jj_git_push_all,
    switch_state_to_git_fetch,
    switch_state_to_git_push,
    apply_jj_git_push_selected: struct { allow_new: bool },
    start_search,
    end_search: struct { reset: bool },
};

pub const InputActionMap = struct {
    map: Map,

    fn builder(alloc: std.mem.Allocator) Builder {
        return .{
            .map = .init(alloc),
            .states = .init(alloc),
        };
    }

    fn deinit(self: *@This()) void {
        self.map.deinit();
    }

    fn get(self: *const @This(), state: State, key: Key, mouse_region: ?MouseRegionKind) ?Action {
        return self.map.get(.{ .state = state, .input = key, .mouse_region = mouse_region });
    }

    const Key = term_mod.TermInputIterator.Input;
    const Input = struct {
        state: State,
        input: Key,
        mouse_region: ?MouseRegionKind = null,

        const HashCtx = struct {
            fn hash_input(_: @This(), hasher: anytype, input: Key) void {
                switch (input) {
                    .mouse => |key| {
                        utils_mod.hash_update(hasher, key.key, .{});
                        utils_mod.hash_update(hasher, key.mod, .{});
                        utils_mod.hash_update(hasher, key.action, .{});
                    },
                    else => utils_mod.hash_update(hasher, input, .{}),
                }
            }
            fn hash_state(_: @This(), hasher: anytype, state: State) void {
                switch (state) {
                    else => |t| utils_mod.hash_update(hasher, t, .{}),
                }
            }
            fn eql_input(_: @This(), a: Key, b: @TypeOf(a)) bool {
                if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
                switch (a) {
                    .mouse => {
                        // TODO: mouse pos can't be handled in InputActionMap :/
                        // a.mouse.pos;

                        if (!std.meta.eql(a.mouse.key, b.mouse.key)) return false;
                        if (!std.meta.eql(a.mouse.mod, b.mouse.mod)) return false;
                        if (!std.meta.eql(a.mouse.action, b.mouse.action)) return false;
                        return true;
                    },
                    else => return std.meta.eql(a, b),
                }
            }
            fn eql_state(_: @This(), a: State, b: @TypeOf(a)) bool {
                switch (a) {
                    else => return std.meta.eql(a, b),
                }
            }

            pub fn hash(self: @This(), input: Input) u64 {
                var hasher = std.hash.Wyhash.init(0);
                self.hash_input(&hasher, input.input);
                self.hash_state(&hasher, input.state);
                utils_mod.hash_update(&hasher, input.mouse_region, .{});
                return hasher.final();
            }
            pub fn eql(self: @This(), a: Input, b: Input) bool {
                return self.eql_input(a.input, b.input) and
                    self.eql_state(a.state, b.state) and
                    utils_mod.auto_eql(a.mouse_region, b.mouse_region, .{});
            }
        };
    };
    const Map = std.HashMap(Input, Action, Input.HashCtx, std.hash_map.default_max_load_percentage);

    const Builder = struct {
        map: Map,
        states: std.ArrayList(State),

        fn build(self: *@This()) InputActionMap {
            defer self.states.deinit();
            return .{ .map = self.map };
        }

        fn deinit(self: *@This()) void {
            self.map.deinit();
            self.states.deinit();
        }

        fn for_state(self: *@This(), state: State) !void {
            try self.states.append(state);
        }

        fn for_states(self: *@This(), states: []const State) !void {
            try self.states.appendSlice(states);
        }

        fn add_one(self: *@This(), key: Key, mouse_region: ?MouseRegionKind, action: Action) !void {
            for (self.states.items) |state| try self.map.put(.{ .state = state, .input = key, .mouse_region = mouse_region }, action);
        }

        fn add_many(self: *@This(), keys: []const Key, mouse_region: ?MouseRegionKind, action: Action) !void {
            for (self.states.items) |state| for (keys) |key| try self.map.put(.{ .state = state, .input = key, .mouse_region = mouse_region }, action);
        }

        fn add_one_for_state(self: *@This(), state: State, key: Key, mouse_region: ?MouseRegionKind, action: Action) !void {
            try self.map.put(.{ .state = state, .input = key, .mouse_region = mouse_region }, action);
        }

        fn reset(self: *@This()) void {
            self.states.clearRetainingCapacity();
        }
    };
};

pub const App = struct {
    screen: term_mod.Screen,

    quit_input_loop: utils_mod.Fuse = .{},

    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),
    input_action_map: InputActionMap,

    sleeper: *Sleeper,
    jj: *jj_mod.JujutsuServer,

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    state: State = .log,
    show_help: bool = false,
    x_split: f32 = 0.55,
    text_input: TextInput,
    mouse_regions: std.ArrayList(MouseRegion),

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

    const MouseRegion = struct {
        region: lay_mod.Region,
        depth: f32,
        surface_id: u32,
        kind: MouseRegionKind,
    };

    const CommandResult = struct {
        errored: bool,
        err: []const u8,
        out: []const u8,
    };

    var app: *@This() = undefined;

    fn init(alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();

        var screen = blk: {
            var term = try term_mod.Term.init(alloc);
            errdefer term.deinit();

            break :blk try term_mod.Screen.init(alloc, term);
        };
        errdefer screen.deinit();
        try screen.update_size();

        screen.term.register_signal_handlers(@This());
        errdefer screen.term.unregister_signal_handlers();

        try screen.term.uncook();
        errdefer screen.term.cook_restore() catch |e| utils_mod.dump_error(e);

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        var input_action_map = try init_input_action_map(alloc);
        errdefer input_action_map.deinit();

        var help = try HelpSlate.init(alloc);
        errdefer help.deinit();

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
            .input_iterator = .{
                .input = try .init(alloc),
                .emu = screen.term.emulator,
                .features = screen.term.features,
            },
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
            .bookmarks = .init(alloc),
            .help = help,
            .toaster = .{
                .alloc = alloc,
                .toasts = .init(alloc),
            },
            .text_input = .init(alloc),
            .mouse_regions = .init(alloc),
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
        defer self.toaster.deinit();
        defer self.text_input.deinit();
        defer self.mouse_regions.deinit();
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

    // poll + /dev/tty is broken on macos
    // - [Add `select()` to `std` for darwin. · Issue #16382 · ziglang/zig](https://github.com/ziglang/zig/issues/16382)
    // - [macOS doesn't like polling /dev/tty](https://nathancraddock.com/blog/macos-dev-tty-polling/)
    const input_loop = if (builtin.os.tag.isDarwin()) @This().input_loop_darwin else @This().input_loop_linux;
    // const input_loop = @This().input_loop_darwin;
    // const input_loop = @This().input_loop_linux;

    fn input_loop_darwin(self: *@This()) !void {
        while (true) {
            const c = @cImport({
                @cInclude("unistd.h");
                @cInclude("fcntl.h");
                @cInclude("sys/select.h");
                @cInclude("errno.h");
            });
            const tty_fd = self.screen.term.tty.handle;
            const fd_arr_type = if (builtin.os.tag.isDarwin()) c_int else c_long;
            const fd_field_name = if (builtin.os.tag.isDarwin()) "fds_bits" else "__fds_bits";

            // prepare the read fd_set
            var readfds: c.fd_set = std.mem.zeroes(c.fd_set);
            const fd_index: usize = @intCast(@divFloor(tty_fd, (8 * @sizeOf(fd_arr_type))));
            const fd_bid = @as(fd_arr_type, (@as(fd_arr_type, 1) << @intCast(@rem(tty_fd, (8 * @sizeOf(fd_arr_type))))));
            @field(readfds, fd_field_name)[fd_index] |= fd_bid;

            // timeout of 20ms
            var tv: c.struct_timeval = .{
                .tv_sec = 0,
                .tv_usec = 20 * 1000,
            };

            const nfds = tty_fd + 1;
            const sel = c.select(nfds, &readfds, null, null, &tv);

            if (sel < 0) {
                const err = std.posix.errno(sel);
                if (err == .INTR) {
                    // interrupted by signal, just continue
                    continue;
                } else {
                    return error.SelectError;
                }
            } else if (sel == 0) {
                // timeout, nothing to read
            } else {
                // sel > 0, so some FD is ready
                if (@field(readfds, fd_field_name)[fd_index] & fd_bid != 0) {
                    var buf: [256]u8 = undefined;
                    const n = c.read(tty_fd, &buf, buf.len);
                    if (n > 0) {
                        for (buf[0..@intCast(n)]) |cbyte| {
                            try self.input_iterator.input.push_back(cbyte);
                        }

                        while (self.input_iterator.next() catch |e| switch (e) {
                            error.ExpectedByte => null,
                            else => {
                                try self.events.send(.{ .err = e });
                                return;
                            },
                        }) |input| {
                            try self.events.send(.{ .input = input });
                        }
                    } else if (n < 0) {
                        const err = std.posix.errno(sel);
                        // if (err == .AGAIN or err == .WOULDBLOCK) {
                        if (err == .AGAIN) {
                            // no data after all, ignore
                        } else if (err == .INTR) {
                            // interrupted, ignore
                        } else {
                            return error.SelectError;
                        }
                    } else {
                        // n == 0: EOF or TTY closed, break
                        break;
                    }
                }
            }

            if (self.quit_input_loop.check()) {
                break;
            }
        }
    }

    fn input_loop_linux(self: *@This()) !void {
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
        try self.screen.uncook();
        // terminal might resize when a command is active
        try self.screen.update_size();
        try self._send_event(.rerender);
        try self.jj.requests.send(.log);
    }

    fn init_input_action_map(alloc: std.mem.Allocator) !InputActionMap {
        var map = InputActionMap.builder(alloc);
        errdefer map.deinit();
        const Key = InputActionMap.Key;

        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .command,
                .{ .bookmark = .view },
                .{ .bookmark = .create },
                .{ .git = .none },
                .{ .git = .fetch },
                .{ .git = .push },
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
            });
            if (options.env == .debug) try map.add_one(
                .{ .functional = .{ .key = .escape, .mod = .{ .ctrl = true } } },
                null,
                .trigger_breakpoint,
            );
            try map.add_one(
                .{ .focus = .in },
                null,
                .refresh_master_content,
            );
            try map.add_one(
                .{ .functional = .{ .key = .escape } },
                null,
                .switch_state_to_log,
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .{ .bookmark = .view },
                .{ .bookmark = .search },
                .{ .git = .none },
                .{ .git = .fetch },
                .{ .git = .push },
                .{ .git = .fetch_search },
                .{ .git = .push_search },
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
            });
            if (options.env == .debug) try map.add_one(
                .{ .key = .{ .key = '1' } },
                null,
                .{ .fancy_terminal_features_that_break_gdb = .enable },
            );
            if (options.env == .debug) try map.add_one(
                .{ .key = .{ .key = '1', .mod = .{ .ctrl = true } } },
                null,
                .{ .fancy_terminal_features_that_break_gdb = .disable },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = '?', .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = '?' } }, // zellij does not pass .shift = true with '?'
                },
                null,
                .toggle_help,
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press } },
                    .{ .key = .{ .key = 'j', .action = .repeat } },
                    .{ .functional = .{ .key = .down, .action = .press } },
                    .{ .functional = .{ .key = .down, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .log, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press } },
                    .{ .key = .{ .key = 'k', .action = .repeat } },
                    .{ .functional = .{ .key = .up, .action = .press } },
                    .{ .functional = .{ .key = .up, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .log, .dir = .up } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } },
                },
                .status,
                .{ .scroll = .{ .target = .log, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } },
                },
                .status,
                .{ .scroll = .{ .target = .log, .dir = .down } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } },
                },
                .diff,
                .{ .scroll = .{ .target = .diff, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } },
                },
                .diff,
                .{ .scroll = .{ .target = .diff, .dir = .down } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press, .mod = .{ .ctrl = true } } },
                    .{ .key = .{ .key = 'j', .action = .repeat, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .scroll = .{ .target = .diff, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press, .mod = .{ .ctrl = true } } },
                    .{ .key = .{ .key = 'k', .action = .repeat, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .scroll = .{ .target = .diff, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'h', .action = .press, .mod = .{ .ctrl = true } } },
                    .{ .key = .{ .key = 'h', .action = .repeat, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .resize_master = .left },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'l', .action = .press, .mod = .{ .ctrl = true } } },
                    .{ .key = .{ .key = 'l', .action = .repeat, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .resize_master = .right },
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .oplog,
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press } },
                    .{ .key = .{ .key = 'j', .action = .repeat } },
                    .{ .functional = .{ .key = .down, .action = .press } },
                    .{ .functional = .{ .key = .down, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .oplog, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press } },
                    .{ .key = .{ .key = 'k', .action = .repeat } },
                    .{ .functional = .{ .key = .up, .action = .press } },
                    .{ .functional = .{ .key = .up, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .oplog, .dir = .up } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } },
                },
                .status,
                .{ .scroll = .{ .target = .oplog, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } },
                },
                .status,
                .{ .scroll = .{ .target = .oplog, .dir = .down } },
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = ' ', .action = .press } },
                    .{ .key = .{ .key = ' ', .action = .repeat } },
                },
                null,
                .select_focused_change,
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
            });
            try map.add_one(
                .{ .key = .{ .key = 'o' } },
                null,
                .{ .set_where = .onto },
            );
            try map.add_one(
                .{ .key = .{ .key = 'b' } },
                null,
                .{ .set_where = .before },
            );
            try map.add_one(
                .{ .key = .{ .key = 'a' } },
                null,
                .{ .set_where = .after },
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .bookmark = .view },
                .{ .git = .push },
                .{ .git = .fetch },
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press } },
                    .{ .key = .{ .key = 'j', .action = .repeat } },
                    .{ .functional = .{ .key = .down, .action = .press } },
                    .{ .functional = .{ .key = .down, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .bookmarks, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press } },
                    .{ .key = .{ .key = 'k', .action = .repeat } },
                    .{ .functional = .{ .key = .up, .action = .press } },
                    .{ .functional = .{ .key = .up, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .bookmarks, .dir = .up } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat } },
                },
                .bookmarks,
                .{ .scroll = .{ .target = .bookmarks, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat } },
                },
                .bookmarks,
                .{ .scroll = .{ .target = .bookmarks, .dir = .down } },
            );
        }

        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'q' } },
            null,
            .send_quit_event,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'n' } },
            null,
            .switch_state_to_new,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'e' } },
            null,
            .jj_edit,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'g' } },
            null,
            .switch_state_to_git,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'r' } },
            null,
            .switch_state_to_rebase_onto,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'S', .mod = .{ .shift = true } } },
            null,
            .switch_state_to_squash,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'a' } },
            null,
            .switch_state_to_abandon,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'o' } },
            null,
            .switch_state_to_oplog,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'd' } },
            null,
            .switch_state_to_duplicate,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'b' } },
            null,
            .switch_state_to_bookmarks_view,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 's' } },
            null,
            .jj_split,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'D', .mod = .{ .shift = true } } },
            null,
            .jj_describe,
        );
        {
            defer map.reset();
            try map.for_state(.log);
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = ':', .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = ':' } }, // zellij does not pass .shift = true :/
                },
                null,
                .switch_state_to_command,
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
            });
            try map.add_one(
                .{ .functional = .{ .key = .enter } },
                null,
                .{ .apply_jj_rebase = .{ .ignore_immutable = false } },
            );

            // OOF: zellij enter + shift is broken :/
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .enter, .mod = .{ .shift = true } } },
                    .{ .functional = .{ .key = .enter, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .apply_jj_rebase = .{ .ignore_immutable = true } },
            );
        }
        {
            defer map.reset();
            try map.for_state(.abandon);

            try map.add_one(
                .{ .functional = .{ .key = .enter } },
                null,
                .{ .apply_jj_abandon = .{ .ignore_immutable = false } },
            );

            // OOF: zellij enter + shift is broken :/
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .enter, .mod = .{ .shift = true } } },
                    .{ .functional = .{ .key = .enter, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .apply_jj_abandon = .{ .ignore_immutable = true } },
            );
        }
        {
            defer map.reset();
            try map.for_state(.squash);

            try map.add_one(
                .{ .functional = .{ .key = .enter } },
                null,
                .{ .apply_jj_squash = .{ .ignore_immutable = false } },
            );

            // OOF: zellij enter + shift is broken :/
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .enter, .mod = .{ .shift = true } } },
                    .{ .functional = .{ .key = .enter, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .apply_jj_squash = .{ .ignore_immutable = true } },
            );
        }
        try map.add_one_for_state(
            .new,
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_jj_new,
        );
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .bookmark = .search },
                .{ .git = .fetch_search },
                .{ .git = .push_search },
            });
            try map.add_one(
                .{ .functional = .{ .key = .escape } },
                null,
                .{ .end_search = .{ .reset = true } },
            );
            try map.add_one(
                .{ .functional = .{ .key = .enter } },
                null,
                .{ .end_search = .{ .reset = false } },
            );
        }
        try map.add_one_for_state(
            .command,
            .{ .functional = .{ .key = .enter } },
            null,
            .{ .execute_command_in_input_buffer = .{ .interactive = false } },
        );
        try map.add_one_for_state(
            .command,
            .{ .functional = .{ .key = .enter, .mod = .{ .ctrl = true } } },
            null,
            .{ .execute_command_in_input_buffer = .{ .interactive = true } },
        );
        try map.add_one_for_state(
            .oplog,
            .{ .key = .{ .key = 'r' } },
            null,
            .apply_jj_op_restore,
        );
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
            });
            try map.add_one(
                .{ .functional = .{ .key = .enter } },
                null,
                .apply_jj_duplicate,
            );
        }
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'c' } },
            null,
            .switch_state_to_bookmark_create,
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'n' } },
            null,
            .new_commit_from_bookmark,
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'm' } },
            null,
            .{ .move_bookmark_to_selected = .{ .allow_backwards = false } },
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'M', .mod = .{ .shift = true } } },
            null,
            .{ .move_bookmark_to_selected = .{ .allow_backwards = true } },
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'd' } },
            null,
            .apply_jj_bookmark_delete,
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'f' } },
            null,
            .{ .apply_jj_bookmark_forget = .{ .include_remotes = false } },
        );
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'F', .mod = .{ .shift = true } } },
            null,
            .{ .apply_jj_bookmark_forget = .{ .include_remotes = true } },
        );
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .bookmark = .view },
                .{ .git = .fetch },
                .{ .git = .push },
            });
            try map.add_one(
                .{ .key = .{ .key = '/', .mod = .{} } },
                null,
                .start_search,
            );
        }
        try map.add_one_for_state(
            .{ .bookmark = .create },
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_jj_bookmark_create_from_input_buffer_on_selected_change,
        );
        try map.add_one_for_state(
            .{ .git = .none },
            .{ .key = .{ .key = 'F', .mod = .{ .shift = true } } },
            null,
            .apply_jj_git_fetch,
        );
        try map.add_one_for_state(
            .{ .git = .none },
            .{ .key = .{ .key = 'P', .mod = .{ .shift = true } } },
            null,
            .apply_jj_git_push_all,
        );
        try map.add_one_for_state(
            .{ .git = .none },
            .{ .key = .{ .key = 'f' } },
            null,
            .switch_state_to_git_fetch,
        );
        try map.add_one_for_state(
            .{ .git = .none },
            .{ .key = .{ .key = 'p' } },
            null,
            .switch_state_to_git_push,
        );
        try map.add_one_for_state(
            .{ .git = .fetch },
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_jj_git_fetch,
        );
        try map.add_one_for_state(
            .{ .git = .push },
            .{ .functional = .{ .key = .enter } },
            null,
            .{ .apply_jj_git_push_selected = .{ .allow_new = false } },
        );
        {
            defer map.reset();
            try map.for_state(.{ .git = .push });

            // OOF: zellij enter + shift is broken :/
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .enter, .mod = .{ .shift = true } } },
                    .{ .functional = .{ .key = .enter, .mod = .{ .ctrl = true } } },
                },
                null,
                .{ .apply_jj_git_push_selected = .{ .allow_new = true } },
            );
        }

        return map.build();
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
            .input => |e| {
                // TDOO:
                //  - zellij shift + enter broken
                //  - zellij enter only sends 1 .press event (even for hold). no repeats, no releases
                _ = e;
                // std.log.debug("{any}", .{e});
            },
            else => {},
        }
        return event;
    }

    fn _handle_event(self: *@This(), event: Event) !void {
        const temp = self.arena.allocator();

        const tropes: struct {
            global: bool = true,
            colored_gutter_cursor: bool = false,
            input_text: bool = false,
            show_help: bool = false,
        } = switch (self.state) {
            .new, .squash, .abandon => .{
                .colored_gutter_cursor = true,
            },
            .duplicate, .rebase => .{
                .colored_gutter_cursor = true,
            },
            .command => .{
                .input_text = true,
                .show_help = true,
            },
            .bookmark => |state| switch (state) {
                .create => .{
                    .input_text = true,
                    .show_help = true,
                },
                .view => .{
                    .show_help = true,
                },
                .search => .{
                    .input_text = true,
                    .show_help = true,
                },
            },
            .git => |state| switch (state) {
                .none => .{
                    .show_help = true,
                },
                .fetch => .{
                    .show_help = true,
                },
                .push => .{
                    .show_help = true,
                },
                .fetch_search => .{
                    .input_text = true,
                    .show_help = true,
                },
                .push_search => .{
                    .input_text = true,
                    .show_help = true,
                },
            },
            .oplog, .log => .{},
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
                try self.screen.update_size();
                try self._send_event(.rerender);
            },
            .scroll_update => {
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
                    // debounce diff requests
                    try self.sleeper.delay_event(20, .{ .diff_update = self.log.focused_change });
                }
            },
            .diff_update => |change| {
                if (std.mem.eql(u8, change.hash[0..], self.log.focused_change.hash[0..])) {
                    try self.diff.diffcache.put(change.hash, .{});
                    try self.jj.requests.send(.{ .diff = change });
                }
            },
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
                // std.log.debug("{any}", .{input});
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

                switch (input) {
                    .mouse => |key| {
                        var curr_id: ?i32 = null;
                        var curr_depth: ?f32 = null;
                        var region_kind: ?MouseRegionKind = .none;
                        for (self.mouse_regions.items) |region| {
                            if (region.depth < curr_depth orelse -std.math.inf(f32)) continue;
                            if (region.depth == curr_depth orelse -std.math.inf(f32) and
                                cast(i32, region.surface_id) < curr_id orelse std.math.minInt(i32)) continue;

                            if (region.region.contains_vec(key.pos.sub(.splat(1)))) {
                                curr_id = cast(i32, region.surface_id);
                                curr_depth = region.depth;
                                region_kind = region.kind;
                            }
                        }

                        if (region_kind == .none) {
                            region_kind = null;
                        }

                        const action = self.input_action_map.get(self.state, input, region_kind) orelse return;
                        try self._handle_event(.{ .action = action });
                    },
                    else => {
                        const action = self.input_action_map.get(self.state, input, null) orelse return;
                        try self._handle_event(.{ .action = action });
                    },
                }
            },
            .action => |action| switch (action) {
                .start_search => {
                    switch (self.state) {
                        .bookmark => |s| switch (s) {
                            .view => {
                                self.state = .{ .bookmark = .search };
                                return;
                            },
                            else => {},
                        },
                        .git => |s| switch (s) {
                            .fetch => {
                                self.state = .{ .git = .fetch_search };
                                return;
                            },
                            .push => {
                                self.state = .{ .git = .push_search };
                                return;
                            },
                            else => {},
                        },
                        else => {},
                    }

                    unreachable;
                },
                .end_search => |v| {
                    defer if (v.reset) self.text_input.reset();
                    switch (self.state) {
                        .bookmark => |s| switch (s) {
                            .search => {
                                self.state = .{ .bookmark = .view };
                                return;
                            },
                            else => {},
                        },
                        .git => |s| switch (s) {
                            .fetch_search => {
                                self.state = .{ .git = .fetch };
                                return;
                            },
                            .push_search => {
                                self.state = .{ .git = .push };
                                return;
                            },
                            else => {},
                        },
                        else => {},
                    }

                    unreachable;
                },
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
                        switch (target.dir) {
                            .up => self.log.y -= 1,
                            .down => self.log.y += 1,
                        }
                        try self._send_event(.scroll_update);
                    },
                    .oplog => {
                        switch (target.dir) {
                            .up => self.oplog.y -= 1,
                            .down => self.oplog.y += 1,
                        }
                        try self._send_event(.op_update);
                    },
                    .diff => {
                        if (self.diff.diffcache.getPtr(self.log.focused_change.hash)) |diff| {
                            switch (target.dir) {
                                .up => diff.y -= 10,
                                .down => diff.y += 10,
                            }
                        }
                    },
                    .bookmarks => {
                        switch (target.dir) {
                            .up => self.bookmarks.y -= 1,
                            .down => self.bookmarks.y += 1,
                        }
                    },
                },
                .resize_master => |dir| switch (dir) {
                    .left => self.x_split -= 0.05,
                    .right => self.x_split += 0.05,
                },
                .switch_state_to_log => {
                    self.log.selected_changes.clearRetainingCapacity();
                    self.text_input.reset();
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
                .switch_state_to_git => {
                    self.state = .{ .git = .none };
                    // self.show_help = true;
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
                .toggle_help => {
                    self.show_help = !self.show_help;
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
                .apply_jj_rebase => |v| {
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
                            try self._toast(.{ .err = error.RebaseOnSelected }, try self.alloc.dupe(u8, "Cannot rebase on selected change"));
                            return;
                        }
                    }

                    switch (self.state.rebase) {
                        .onto => try args.append("-d"),
                        .after => try args.append("-A"),
                        .before => try args.append("-B"),
                    }

                    try args.append(self.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        try args.append("--ignore-immutable");
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_abandon => |v| {
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

                    if (v.ignore_immutable) {
                        try args.append("--ignore-immutable");
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_squash => |v| {
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
                            try self._toast(.{ .err = error.SquashOnSelected }, try self.alloc.dupe(u8, "Cannot squash on selected change"));
                            return;
                        }
                    }

                    try args.append("--into");
                    try args.append(self.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        try args.append("--ignore-immutable");
                    }

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
                .execute_command_in_input_buffer => |e| {
                    defer {
                        self.text_input.reset();
                        self.state = .log;
                        self.show_help = false;
                    }

                    var args = std.ArrayList([]const u8).init(temp);

                    // TODO: support parsing and passing "string" and 'string' with \" \' and spaces properly
                    var arg_it = std.mem.splitAny(u8, self.text_input.text.items, &std.ascii.whitespace);
                    while (arg_it.next()) |arg| {
                        if (arg.len == 0) continue;
                        try args.append(arg);
                    }

                    if (args.items.len == 0) {
                        try self._toast(.{ .err = error.CommandInputEmpty }, try self.alloc.dupe(u8, "Input is empty"));
                        return;
                    }

                    if (e.interactive) {
                        try self.execute_interactive_command(args.items);
                    } else {
                        try self.execute_non_interactive_command(args.items);
                    }
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
                    try self.jj.requests.send(.log);
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
                            try self._toast(.{ .err = error.DuplicateOnSelected }, try self.alloc.dupe(u8, "Cannot duplicate on selected change"));
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
                .switch_state_to_bookmark_create => {
                    self.state = .{ .bookmark = .create };
                },
                .new_commit_from_bookmark => {
                    defer {
                        self.text_input.reset();
                        self.state = .log;
                    }

                    const bookmark = self.bookmarks.get_selected() orelse return;

                    // TODO: why multiple targets?
                    if (bookmark.parsed.target.len != 1) {
                        try self._toast(.{ .err = error.MultipleTargetsFound }, try self.alloc.dupe(u8, "Error executing command"));
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
                .move_bookmark_to_selected => |v| {
                    defer self.state = .log;
                    const bookmark = self.bookmarks.get_selected() orelse return;

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("bookmark");
                    try args.append("move");
                    try args.append(bookmark.parsed.name);
                    try args.append("--to");
                    try args.append(self.log.focused_change.id[0..]);
                    if (v.allow_backwards) {
                        try args.append("--allow-backwards");
                    }

                    try self.execute_non_interactive_command(args.items);
                    try self.jj.requests.send(.log);
                },
                .apply_jj_bookmark_delete => {
                    defer self.state = .log;
                    const bookmark = self.bookmarks.get_selected() orelse return;
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "delete",
                        bookmark.parsed.name,
                    });
                },
                .apply_jj_bookmark_forget => |v| {
                    defer self.state = .log;
                    const bookmark = self.bookmarks.get_selected() orelse return;

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
                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("git");
                    try args.append("fetch");

                    if (self.state.git == .fetch) {
                        const bookmark = self.bookmarks.get_selected() orelse return;
                        try args.append("--branch");
                        try args.append(bookmark.parsed.name);
                        if (bookmark.parsed.remote) |remote| {
                            try args.append("--remote");
                            try args.append(remote);
                        }
                    }

                    try self.execute_non_interactive_command(args.items);
                    try self.jj.requests.send(.log);
                },
                .apply_jj_git_push_all => {
                    defer self.state = .log;
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "git",
                        "push",
                        "--all",
                    });
                    try self.jj.requests.send(.log);
                },
                .apply_jj_git_push_selected => |v| {
                    defer self.state = .log;
                    const bookmark = self.bookmarks.get_selected() orelse return;

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("git");
                    try args.append("push");
                    try args.append("--bookmark");
                    try args.append(bookmark.parsed.name);
                    if (v.allow_new) {
                        try args.append("--allow-new");
                    } else if (bookmark.parsed.remote) |remote| {
                        try args.append("--remote");
                        try args.append(remote);
                    }

                    try self.execute_non_interactive_command(args.items);
                    try self.jj.requests.send(.log);
                },
                .switch_state_to_git_fetch => {
                    self.state = .{ .git = .fetch };
                    try self.jj.requests.send(.bookmark);
                },
                .switch_state_to_git_push => {
                    self.state = .{ .git = .push };
                    try self.jj.requests.send(.bookmark);
                },
            },
            .jj => |res| switch (res.req) {
                .log => {
                    switch (res.res) {
                        .ok => |buf| {
                            self.alloc.free(self.log.status);
                            self.log.status = buf;
                            self.log.changes.reset(buf);
                            try self._send_event(.scroll_update);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJLogFailed }, buf),
                    }

                    try self._send_event(.rerender);
                },
                .diff => |req| {
                    switch (res.res) {
                        .ok => |buf| {
                            self.diff.diffcache.getPtr(req.hash).?.diff = buf;

                            var it = utils_mod.LineIterator.init(buf);
                            var len: i32 = 0;
                            while (it.next()) |_| len += 1;
                            self.diff.diffcache.getPtr(req.hash).?.len = len;
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJDiffFailed }, buf),
                    }
                    try self._send_event(.rerender);
                },
                .oplog => {
                    switch (res.res) {
                        .ok => |buf| {
                            self.alloc.free(self.oplog.oplog);
                            self.oplog.oplog = buf;
                            self.oplog.ops.reset(buf);
                            try self._send_event(.rerender);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJOpLogFailed }, buf),
                    }
                },
                .evolog => |req| {
                    _ = req;
                    switch (res.res) {
                        .ok => |buf| {
                            self.alloc.free(buf);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJEvLogFailed }, buf),
                    }
                },
                .bookmark => {
                    switch (res.res) {
                        .ok => |buf| {
                            try self.bookmarks.update(buf, self);
                            try self._send_event(.rerender);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJBookmarkFailed }, buf),
                    }
                },
            },
        }
    }

    fn event_loop(self: *@This()) !void {
        try self._send_event(.rerender);

        if (comptime options.env == .debug) {
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
                hasher.update(&std.mem.toBytes(self.bookmarks.y));
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

    fn _toast(self: *@This(), mode: Toaster.Toast.Mode, msg: []const u8) !void {
        const id = try self.toaster.add(.{ .mode = mode, .msg = msg });
        try self.sleeper.delay_event(5000, .{ .pop_toast = id });
    }

    fn _register_mouse_region(self: *@This(), kind: MouseRegionKind, surface: *Surface) void {
        self.mouse_regions.append(.{
            .kind = kind,
            .surface_id = surface.id,
            .depth = surface.depth,
            .region = surface.region,
        }) catch |e| utils_mod.dump_error(e);
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

        if (options.env == .debug) {
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
            try surface.draw_buf(" ");
            try surface.draw_buf(self.state.short_display());
            try surface.draw_buf(" ");
            try surface.apply_style(.reset);

            if (options.env == .debug) {
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
        self.mouse_regions.clearRetainingCapacity();

        {
            var status = try Surface.init(&self.screen, 0, .{});
            defer self._register_mouse_region(.status, &status);
            try status.clear();
            // try status.draw_border(symbols.thin.rounded);

            var bar = try status.split_y(-1, .none);
            // defer self._register_mouse_region(.none, &bar);
            try self.render_status_bar(&bar);

            var diffs = try status.split_x(cast(i32, cast(f32, status.size().x) * self.x_split), .border);
            defer self._register_mouse_region(.diff, &diffs);

            switch (self.state) {
                .oplog => try self.oplog.render(&status, self),
                else => try self.log.render(&status, self, self.state, tropes),
            }
            try self.diff.render(&diffs, self, self.log.focused_change);

            const max_popup_region = self.screen.term.screen
                .split_y(-2, false).top
                .split_y(1, false).bottom
                .border_sub(.{ .x = 2 });

            if (self.state == .bookmark or
                std.meta.eql(self.state, .{ .git = .push }) or
                std.meta.eql(self.state, .{ .git = .fetch }))
            {
                const popup_size = Vec2{ .x = 60, .y = 30 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var surface = try Surface.init(&self.screen, 1, .{ .origin = region.origin, .size = region.size });
                defer self._register_mouse_region(.bookmarks, &surface);

                if (self.state == .bookmark) {
                    if (self.state.bookmark == .search or self.text_input.text.items.len > 0) {
                        var input_box = try surface.split_y(3, .none);
                        std.mem.swap(@TypeOf(surface), &surface, &input_box);

                        try input_box.clear();
                        try input_box.draw_border(symbols.thin.rounded);

                        try input_box.draw_border_heading(" Search ");

                        try self.text_input.draw(&input_box);
                        try self.bookmarks.render(&surface, self, .{}, .{});
                    } else {
                        try self.bookmarks.render(&surface, self, .{}, .{});
                    }
                } else if (std.meta.eql(self.state, .{ .git = .push })) {
                    try self.bookmarks.render(&surface, self, .{ .remotes = false }, .{});
                } else if (std.meta.eql(self.state, .{ .git = .fetch })) {
                    try self.bookmarks.render(&surface, self, .{ .remotes = false }, .{ .targets = false });
                } else unreachable;
            }

            if (self.state == .command or (self.state == .bookmark and self.state.bookmark == .create)) {
                const popup_size = Vec2{ .x = 55, .y = 5 };
                const origin = max_popup_region.origin.add(max_popup_region.size.mul(0.5)).sub(popup_size.mul(0.5));
                const region = max_popup_region.clamp(.{ .origin = origin, .size = popup_size });
                var input_box = try Surface.init(&self.screen, 5, .{ .origin = region.origin, .size = region.size });
                // defer self._register_mouse_region(.none, &input_box);
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
                var surface = try Surface.init(&self.screen, 10, .{ .origin = region.origin, .size = region.size });
                // defer self._register_mouse_region(.none, &surface);
                try self.toaster.render(&surface, self, if (self.show_help or tropes.show_help) .up else .down);
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
                try self.help.render(&help, self);
            }
        }
        try self.screen.flush_writes();
    }

    fn execute_non_interactive_command(self: *@This(), args: []const []const u8) !void {
        // better error messages. nothing bad. so i just do this for now :|
        // OOF: some jj commands print output when successful. so this mode will dump output in real stdout :/
        // try self.execute_interactive_command(args);

        const res = self._execute_non_interactive_command(args) catch |e| switch (e) {
            error.FileNotFound => CommandResult{
                .errored = true,
                .err = try std.fmt.allocPrint(self.alloc, "Executable not found", .{}),
                .out = &.{},
            },
            else => return e,
        };
        if (res.errored) {
            try self._toast(.{ .err = error.CommandExecutionError }, res.err);
            if (res.out.len > 0) {
                try self._toast(.none, res.out);
            }
        } else {
            if (res.err.len > 0) {
                if (res.out.len > 0) {
                    try self._toast(.warn, res.err);
                } else {
                    try self._toast(.info, res.err);
                }
            }
            if (res.out.len > 0) {
                if (res.err.len > 0) {
                    try self._toast(.none, res.out);
                } else {
                    try self._toast(.success, res.out);
                }
            }
        }

        try self.jj.requests.send(.log);
    }

    fn _execute_non_interactive_command(self: *@This(), args: []const []const u8) !CommandResult {
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

    fn execute_interactive_command(self: *@This(), args: []const []const u8) !void {
        // OOF: zellij does not behave well with .sync_set + interactive command
        // sync_set just so commands that immediately terminate do not flash the screen :P
        // try self.screen.term.tty.writeAll(codes.sync_set);
        try self.restore_terminal_for_command();

        const res = self._execute_command(args) catch |e| switch (e) {
            error.FileNotFound => CommandResult{
                .errored = true,
                .err = try std.fmt.allocPrint(self.alloc, "Executable not found", .{}),
                .out = &.{},
            },
            else => return e,
        };
        if (res.errored) {
            try self._toast(.{ .err = error.CommandExecutionError }, res.err);
        } else {
            if (res.err.len > 0) {
                try self._toast(.info, res.err);
            }
        }

        try self.uncook_terminal();
    }

    fn _execute_command(self: *@This(), args: []const []const u8) !CommandResult {
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

        return .{
            .errored = errored,
            .err = try err_buf.toOwnedSlice(),
            .out = &.{},
        };
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

test "input code" {
    const alloc = std.testing.allocator;

    var map = try App.init_input_action_map(alloc);
    defer map.deinit();
}
