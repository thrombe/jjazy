const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

const term_mod = @import("term.zig");

const lay_mod = @import("lay.zig");

const jj_mod = @import("jj.zig");
const Formatted = jj_mod.Formatted;
const Change = jj_mod.Change;
const Operation = jj_mod.Operation;
const Bookmark = jj_mod.Bookmark;
const FileTreeEntry = jj_mod.FileTreeEntry;

const components_mod = @import("components.zig");

pub const action_help = [_]struct {
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
        .action = .{ .scroll = .{ .target = .bookmarks, .dir = .up } },
        .help = "Scroll up bookmarks",
    },
    .{
        .action = .{ .scroll = .{ .target = .bookmarks, .dir = .down } },
        .help = "Scroll down bookmarks",
    },
    .{
        .action = .{ .scroll = .{ .target = .log, .dir = .up, .pan = true } },
        .help = "Pan up logs",
    },
    .{
        .action = .{ .scroll = .{ .target = .log, .dir = .down, .pan = true } },
        .help = "Pan down logs",
    },
    .{
        .action = .{ .scroll = .{ .target = .bookmarks, .dir = .up, .pan = true } },
        .help = "Pan up bookmarks",
    },
    .{
        .action = .{ .scroll = .{ .target = .bookmarks, .dir = .down, .pan = true } },
        .help = "Pan down bookmarks",
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
        .action = .{ .scroll = .{ .target = .diff, .dir = .up, .pan = true } },
        .help = "Scroll up diff",
    },
    .{
        .action = .{ .scroll = .{ .target = .diff, .dir = .down, .pan = true } },
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
        .action = .go_back_a_mode,
        .help = "Go back a mode",
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
        .action = .switch_state_to_evolog,
        .help = "View Change Evolution logs",
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
        .action = .switch_state_to_file_tree,
        .help = "View file tree for change",
    },
    .{
        .action = .toggle_file_tree_diff,
        .help = "Toggle file tree diff",
    },
    .{
        .action = .toggle_file_tree_only_changed,
        .help = "Toggle unchanged files",
    },
    .{
        .action = .start_range_diff,
        .help = "Start Range Diff Selection",
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
        .action = .switch_state_to_bookmark_goto,
        .help = "Goto bookmark",
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
        .action = .switch_state_to_git_push,
        .help = "Git push a bookmark",
    },
    .{
        .action = .switch_state_to_git_fetch_new,
        .help = "Fetch a new branch",
    },
    .{
        .action = .apply_jj_git_fetch_new,
        .help = "Apply git fetch new",
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
    .{
        .action = .apply_bookmark_goto,
        .help = "Goto selected bookmark",
    },
    .{
        .action = .{ .file_tree_collapse = .{ .collapse = false } },
        .help = "Uncollapse dir",
    },
    .{
        .action = .{ .file_tree_collapse = .{ .collapse = true } },
        .help = "Collapse dir",
    },
    .{
        .action = .{ .change_diff_context = .{ .off = .reset } },
        .help = "Reset Diff context size",
    },
    .{
        .action = .{ .change_diff_context = .{ .off = .increase } },
        .help = "Increase Diff context size",
    },
    .{
        .action = .{ .change_diff_context = .{ .off = .decrease } },
        .help = "Decrease Diff context size",
    },
    .{
        .action = .open_temp_file,
        .help = "Open temporary copy of selected file",
    },
    .{
        .action = .open_source_file,
        .help = "Open file from current commit",
    },
    .{
        .action = .toggle_file_tree_full_context,
        .help = "Toggle full context in file tree diff",
    },
};

pub const State = union(enum(u8)) {
    log,
    oplog,
    evolog,
    file_tree: enum {
        list,
        diff,
        range_diff,
        search_list,
        search_diff,
        search_range_diff,

        pub fn from(mode: components_mod.FileTreeSlate.FileList.Mode) @This() {
            return switch (mode) {
                .list => .list,
                .diff => .diff,
                .range_diff => .range_diff,
            };
        }

        pub fn is_diff(self: @This()) bool {
            return self == .diff or self == .range_diff or self == .search_diff or self == .search_range_diff;
        }

        pub fn base_mode(self: @This()) components_mod.FileTreeSlate.FileList.Mode {
            return switch (self) {
                .list, .search_list => .list,
                .diff, .search_diff => .diff,
                .range_diff, .search_range_diff => .range_diff,
            };
        }
    },
    bookmark: enum {
        view,
        create,
        search,
        view_goto,
        search_goto,
    },
    log_range_diff,
    git: enum {
        none,
        fetch,
        push,
        fetch_search,
        push_search,
        fetch_new,
    },
    command,
    rebase: Where,
    duplicate: Where,
    new,
    squash,
    abandon,

    pub fn is_file_tree_diff(self: @This()) bool {
        return switch (self) {
            .file_tree => |m| m.is_diff(),
            else => false,
        };
    }

    pub inline fn short_display(self: @This()) []const u8 {
        return switch (self) {
            inline .file_tree, .rebase, .duplicate => |_p, t| switch (_p) {
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

pub const MouseRegionKind = enum {
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
    file_show_scroll_update,
    file_show_update: struct { to: jj_mod.Change, from: ?jj_mod.Change = null, path: []const u8, context: u32 },
    diff_update: struct { change: jj_mod.Change, context: u32 },
    opshow_update: jj_mod.Operation,
    op_update,
    quit,
    input: term_mod.TermInputIterator.Input,
    jj: JujutsuServer.Response,
    err: anyerror,
    toast: components_mod.Toaster.Toast,
    pop_toast: components_mod.Toaster.Id,
    action: Action,
};

pub const Action = union(enum) {
    fancy_terminal_features_that_break_gdb: enum { enable, disable },
    trigger_breakpoint,
    refresh_master_content,
    scroll: struct { target: enum { log, diff, bookmarks }, dir: enum { up, down }, pan: bool = false },
    resize_master: enum { left, right },
    change_diff_context: struct { off: enum { reset, increase, decrease } },
    go_back_a_mode,
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
    switch_state_to_evolog,
    switch_state_to_duplicate,
    switch_state_to_bookmarks_view,
    switch_state_to_file_tree,
    toggle_file_tree_diff,
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
    switch_state_to_bookmark_goto,
    apply_bookmark_goto,
    switch_state_to_git_fetch,
    switch_state_to_git_push,
    file_tree_collapse: struct { collapse: bool },
    apply_jj_git_push_selected: struct { allow_new: bool },
    start_search,
    switch_state_to_git_fetch_new,
    apply_jj_git_fetch_new,
    end_search: struct { reset: bool },
    open_temp_file,
    open_source_file,
    start_range_diff,
    toggle_file_tree_full_context,
    toggle_file_tree_only_changed,
};

pub const JujutsuServer = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    quit: utils_mod.Fuse = .{},
    thread: std.Thread,
    requests: utils_mod.Channel(struct { id: ?u32, req: Request }),

    // not owned
    events: utils_mod.Channel(Event),

    pub const Request = union(enum) {
        log: struct { n: u32, reset_pos: bool = false },
        oplog: struct { reset_pos: bool = false },
        bookmark,
        diff: struct { change: Change, context: u32 },
        opshow: Operation,
        evolog: Change,
        file_tree: components_mod.FileTreeSlate.RangeContext,
        file_content: struct {
            to: Change,
            from: ?Change = null,
            path: []const u8,
            mode: FileContentMode,
            context: u32,
        },
        git_fetch: struct { branch: ?[]const u8, remote: ?[]const u8 },
        git_push: struct { branch: ?[]const u8, remote: ?[]const u8, allow_new: bool },
        command: struct {
            cmd: utils_mod.Command,
            toast_success: bool = false,
            refresh_log: bool = false,
            reset_log_pos: bool = false,
            refresh_oplog: bool = false,
            reset_oplog_pos: bool = false,
        },
    };

    pub const FileContentMode = enum { plain, diff };

    pub const OkWithStatus = struct {
        status: Formatted,
        buf: Formatted,
    };

    pub const Result = union(enum) {
        with_status: OkWithStatus,
        file_tree: struct {
            status: Formatted,
            buf: Formatted,
            diffs: Formatted,
        },
        ok: Formatted,
        command_result: utils_mod.Command.Result,
        err: Formatted,
    };

    pub const Response = struct {
        req: Request,
        res: Result,
    };

    pub fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(Event)) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        self.* = .{
            .events = events,
            .requests = try .init(alloc),
            .alloc = alloc,
            .arena = .init(alloc),
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
        defer self.arena.deinit();
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

        const temp = self.arena.allocator();
        while (self.requests.wait_recv()) |const_request| {
            if (self.quit.check()) return;
            var request = const_request;
            defer _ = self.arena.reset(.retain_capacity);
            defer if (request.id) |id| self.events.send(.{ .pop_toast = id }) catch {};

            switch (request.req) {
                .log => |v| {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "log",
                        "--template",
                        Change.Parsed.template,
                        "--limit",
                        try std.fmt.allocPrint(temp, "{d}", .{v.n}),
                    });
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .oplog => |v| {
                    _ = v;
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "op",
                        "log",
                        "--template",
                        Operation.Parsed.template,
                    });
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .evolog => |change| {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "evolog",
                        "--template",
                        Change.Parsed.template,
                        "-r",
                        change.id[0..],
                        "--stat",
                    });
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .diff => |v| {
                    // TODO: these diffs can get pretty large, maybe add some kinda paging support to this?
                    //  - something like: caller passes some line range info (start, end)
                    var stat_cmd = utils_mod.Command.init(temp);
                    defer stat_cmd.deinit();
                    _ = try stat_cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "show",
                        "--stat",
                        "-r",
                        v.change.hash[0..],
                    });
                    const stat = stat_cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(stat);

                    // jj diff -r lqo --tool delta --config merge-tools.delta.diff-args='["--diff-args=\"-U50\"", "$left", "$right"]'
                    var diff_cmd = utils_mod.Command.init(temp);
                    defer diff_cmd.deinit();
                    _ = try diff_cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "diff",
                        "--tool",
                        "delta",
                        "--config",
                        try std.fmt.allocPrint(temp,
                            \\merge-tools.delta.diff-args=["--diff-args=\"-U{d}\"", "$left", "$right"]
                        , .{v.context}),
                        "-r",
                        v.change.hash[0..],
                    });
                    const diff = diff_cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(diff);

                    try self.events.send(.{ .jj = .{
                        .req = request.req,
                        .res = .{
                            .with_status = .{
                                .status = .from(stat),
                                .buf = .from(diff),
                            },
                        },
                    } });
                },
                .opshow => |op| {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "op",
                        "show",
                        "--stat",
                        "--tool",
                        "delta",
                        op.hash[0..],
                    });
                    const stat = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(stat) } } });
                },
                .bookmark => {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "list",
                        "-a",
                        "--template",
                        Bookmark.Parsed.template,
                    });
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .file_tree => |payload| {
                    var stat_cmd = utils_mod.Command.init(temp);
                    defer stat_cmd.deinit();
                    if (payload.from) |from| {
                        _ = try stat_cmd.add_args(&[_][]const u8{
                            "jj",
                            "--color",
                            "always",
                            "diff",
                            "--stat",
                            "--from",
                            from.hash[0..],
                            "--to",
                            payload.to.hash[0..],
                        });
                    } else {
                        _ = try stat_cmd.add_args(&[_][]const u8{
                            "jj",
                            "--color",
                            "always",
                            "show",
                            "--stat",
                            "-r",
                            payload.to.hash[0..],
                        });
                    }
                    const stat = stat_cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(stat);

                    var res_cmd = utils_mod.Command.init(temp);
                    defer res_cmd.deinit();
                    _ = try res_cmd.add_args(&[_][]const u8{
                        "jj",
                        "file",
                        "list",
                        "-r",
                        payload.to.id[0..],
                        "--template",
                        FileTreeEntry.Parsed.template,
                    });
                    const res = res_cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(res);

                    var diffs_cmd = utils_mod.Command.init(temp);
                    defer diffs_cmd.deinit();
                    if (payload.from) |from| {
                        _ = try diffs_cmd.add_args(&[_][]const u8{
                            "jj",
                            "diff",
                            "--from",
                            from.hash[0..],
                            "--to",
                            payload.to.hash[0..],
                            "--template",
                            jj_mod.FileTreeDiffEntry.Parsed.template,
                        });
                    } else {
                        _ = try diffs_cmd.add_args(&[_][]const u8{
                            "jj",
                            "diff",
                            "-r",
                            payload.to.id[0..],
                            "--template",
                            jj_mod.FileTreeDiffEntry.Parsed.template,
                        });
                    }
                    const diffs = diffs_cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(diffs);

                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .file_tree = .{
                        .status = .from(stat),
                        .buf = .from(res),
                        .diffs = .from(diffs),
                    } } } });
                },
                .file_content => |payload| {
                    const cmd_str = switch (payload.mode) {
                        // NOTE: file path needs to be relative to current path instead of from repo root, but we fix this by just changing the cwd to the workspace root
                        .plain => try std.fmt.allocPrint(temp, "jj file show -r {s} {s} | bat --color=always --style numbers,plain --file-name {s}", .{
                            payload.to.id[0..],
                            payload.path,
                            payload.path,
                        }),
                        // jj diff -r lqo --tool delta --config merge-tools.delta.diff-args='["--diff-args=\"-U50\"", "$left", "$right"]'
                        .diff => if (payload.from) |from|
                            try std.fmt.allocPrint(temp, "jj diff --from {s} --to {s} {s} --tool delta --config merge-tools.delta.diff-args='[\"--diff-args=-U{d}\", \"$left\", \"$right\"]'", .{
                                from.hash[0..],
                                payload.to.hash[0..],
                                payload.path,
                                payload.context,
                            })
                        else
                            try std.fmt.allocPrint(temp, "jj diff -r {s} {s} --tool delta --config merge-tools.delta.diff-args='[\"--diff-args=-U{d}\", \"$left\", \"$right\"]'", .{
                                payload.to.id[0..],
                                payload.path,
                                payload.context,
                            }),
                    };
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "sh", "-c", cmd_str });
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .git_fetch => |v| {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "git", "fetch" });
                    if (v.branch) |branch| {
                        _ = try cmd.add_args(&[_][]const u8{ "--bookmark", branch });
                    }
                    if (v.remote) |remote| {
                        _ = try cmd.add_args(&[_][]const u8{ "--remote", remote });
                    }
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .git_push => |v| {
                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "git", "push" });
                    if (v.branch) |branch| {
                        _ = try cmd.add_args(&[_][]const u8{ "--bookmark", branch });
                    }
                    if (v.allow_new) {
                        _ = try cmd.arg("--allow-new");
                    } else if (v.remote) |remote| {
                        _ = try cmd.add_args(&[_][]const u8{ "--remote", remote });
                    }
                    const res = cmd.exec_capture(self.alloc, temp) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .ok = .from(res) } } });
                },
                .command => |*payload| {
                    const res = payload.cmd.exec_status(self.alloc) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = request.req, .res = .{ .command_result = res } } });
                },
            }
        }
    }
};

pub const Sleeper = struct {
    alloc: std.mem.Allocator,
    thread: std.Thread,
    quit: utils_mod.Fuse = .{},
    requests: utils_mod.Channel(Request),
    sleeps: Sleeps,

    // not owned
    events: utils_mod.Channel(Event),

    const Request = struct { target_ts: i128, event: Event };
    const Sleeps = utils_mod.MaxHeap(Request, struct {
        pub fn lessThan(_: *@This(), a: *Request, b: *Request) bool {
            return a.target_ts < b.target_ts;
        }
    });

    pub fn init(alloc: std.mem.Allocator, events: utils_mod.Channel(Event)) !*@This() {
        const self = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var requests = try utils_mod.Channel(Request).init(alloc);
        errdefer requests.deinit();

        self.* = .{
            .alloc = alloc,
            .sleeps = .init(alloc, .{}),
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
                try self.sleeps.push(e);
            }

            const now = std.time.nanoTimestamp();
            if (self.sleeps.peek()) |s| if (now >= s.target_ts) {
                const sleep = self.sleeps.pop().?;
                try self.events.send(sleep.event);
            };

            std.Thread.sleep(std.time.ns_per_ms * 2);
        }
    }
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
    pub const Input = struct {
        state: State,
        input: Key,
        mouse_region: ?MouseRegionKind = null,

        pub const HashCtx = struct {
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
            pub fn eql_state(_: @This(), a: State, b: @TypeOf(a)) bool {
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
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    envmap: std.process.EnvMap,

    quit_input_loop: utils_mod.Fuse = .{},

    renderer: components_mod.Renderer,
    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),
    input_action_map: InputActionMap,

    sleeper: *Sleeper,
    jj: *JujutsuServer,

    state: State = .log,
    file_tree_from: ?Change = null,
    file_tree_diff_context: u32 = 30,

    const CommandResult = struct {
        errored: bool,
        err: []const u8,
        out: []const u8,
    };

    var app: *@This() = undefined;

    pub fn init(alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        errdefer alloc.destroy(self);

        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();

        var envmap = try std.process.getEnvMap(alloc);
        errdefer envmap.deinit();

        var renderer = try components_mod.Renderer.init(alloc, &envmap, @This());
        errdefer renderer.deinit();

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        var input_action_map = try init_input_action_map(alloc);
        errdefer input_action_map.deinit();

        const sleeper = try Sleeper.init(alloc, events);
        errdefer sleeper.deinit();

        const jj = try JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        // set working directory to workspace root
        {
            var cmd = utils_mod.Command.init(arena.allocator());
            _ = try cmd.add_args(&[_][]const u8{ "jj", "workspace", "root" });
            const root = cmd.exec_capture(arena.allocator(), arena.allocator()) catch |e| {
                utils_mod.dump_error(e);
                return e;
            };
            const trimmed = std.mem.trim(u8, root, &std.ascii.whitespace);
            try std.process.changeCurDir(trimmed);
        }

        try jj.requests.send(.{ .req = .{ .log = .{ .n = renderer.log.limit } }, .id = null });
        try jj.requests.send(.{ .req = .bookmark, .id = null });

        self.* = .{
            .alloc = alloc,
            .arena = arena,
            .envmap = envmap,
            .renderer = renderer,
            .input_iterator = .{
                .input = try .init(alloc),
                .emu = renderer.screen.term.emulator,
                .features = renderer.screen.term.features,
            },
            .events = events,
            .sleeper = sleeper,
            .jj = jj,
            .input_action_map = input_action_map,
            .input_thread = undefined,
        };

        const input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        errdefer {
            _ = self.quit_input_loop.fuse();
            input_thread.join();
        }

        self.input_thread = input_thread;
        app = self;
        return self;
    }

    pub fn deinit(self: *@This()) void {
        const alloc = self.alloc;
        defer alloc.destroy(self);
        defer self.arena.deinit();
        defer self.envmap.deinit();
        defer self.input_action_map.deinit();
        defer self.renderer.deinit();
        defer self.input_iterator.input.deinit();
        defer {
            while (self.events.try_recv()) |e| switch (e) {
                .jj => |res| switch (res.res) {
                    .command_result => |r| {
                        self.alloc.free(r.err);
                        self.alloc.free(r.out);
                    },
                    .ok, .err => |buf| self.alloc.free(buf.buf),
                    .with_status => |r| {
                        self.alloc.free(r.status.buf);
                        self.alloc.free(r.buf.buf);
                    },
                    .file_tree => |r| {
                        self.alloc.free(r.status.buf);
                        self.alloc.free(r.buf.buf);
                        self.alloc.free(r.diffs.buf);
                    },
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
        var waiting_for_input_after_escape: bool = false;
        while (true) {
            if (self.quit_input_loop.check()) break;

            if (try self.has_input(20)) {
                var buf = std.mem.zeroes([256]u8);
                const n = try self.renderer.screen.term.tty.read(&buf);
                for (buf[0..n]) |c| try self.input_iterator.input.push_back(c);

                waiting_for_input_after_escape = buf[n - 1] == 0x1b;
            } else if (waiting_for_input_after_escape) {
                waiting_for_input_after_escape = false;

                // NOTE:(1007) we push extra null byte just so we can recognise the last 0x1B byte as .escape without waiting for more input
                try self.input_iterator.input.push_back(0x00);
            } else continue;

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
    }

    // poll + /dev/tty is broken on macos
    // - [Add `select()` to `std` for darwin. · Issue #16382 · ziglang/zig](https://github.com/ziglang/zig/issues/16382)
    // - [macOS doesn't like polling /dev/tty](https://nathancraddock.com/blog/macos-dev-tty-polling/)
    const has_input = if (builtin.os.tag.isDarwin()) @This().has_input_darwin else @This().has_input_linux;
    // const has_input = @This().has_input_darwin;
    // const has_input = @This().has_input_linux;

    fn has_input_darwin(self: *@This(), wait_ms: u32) !bool {
        const c = @cImport({
            @cInclude("unistd.h");
            @cInclude("fcntl.h");
            @cInclude("sys/select.h");
            @cInclude("errno.h");
        });
        const tty_fd = self.renderer.screen.term.tty.handle;
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
            .tv_usec = @as(fd_arr_type, @intCast(wait_ms)) * 1000,
        };

        const nfds = tty_fd + 1;
        const sel = c.select(nfds, &readfds, null, null, &tv);

        if (sel < 0) {
            const err = std.posix.errno(sel);
            if (err == .INTR) {
                // interrupted by signal, just continue
                return false;
            } else {
                return error.SelectError;
            }
        } else if (sel == 0) {
            // sel == 0, timeout, nothing to read
            return false;
        } else {
            // sel > 0, so some FD is ready
            return @field(readfds, fd_field_name)[fd_index] & fd_bid != 0;
        }
    }

    fn has_input_linux(self: *@This(), wait_ms: u32) !bool {
        var fds = [1]std.posix.pollfd{.{ .fd = self.renderer.screen.term.tty.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        return try std.posix.poll(&fds, @intCast(wait_ms)) > 0;
    }

    fn restore_terminal_for_command(self: *@This()) !void {
        self.renderer.screen.term.unregister_signal_handlers();
        try self.renderer.screen.term.cook_restore();
        _ = self.quit_input_loop.fuse();
        defer _ = self.quit_input_loop.unfuse();
        self.input_thread.join();
    }

    fn uncook_terminal(self: *@This()) !void {
        self.input_thread = try std.Thread.spawn(.{}, @This()._input_loop, .{self});
        self.renderer.screen.term.register_signal_handlers(@This());
        try self.renderer.screen.uncook();
        // terminal might resize when a command is active
        try self.renderer.screen.update_size();
        try self._send_event(.rerender);
        const limit = self.renderer.log.calc_limit(.{});
        self.renderer.log.limit = limit;
        try self.jj_request(.{ .log = .{ .n = limit } });
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
                .evolog,
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
                .command,
                .{ .bookmark = .view },
                .{ .bookmark = .view_goto },
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
                .log_range_diff,
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
                .go_back_a_mode,
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .evolog,
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
                .{ .bookmark = .view },
                .{ .bookmark = .view_goto },
                .{ .bookmark = .search },
                .{ .bookmark = .search_goto },
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
                .log_range_diff,
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
                .oplog,
                .evolog,
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
                .log_range_diff,
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'J', .action = .press, .mod = .{} } },
                    .{ .key = .{ .key = 'J', .action = .repeat, .mod = .{} } },
                    .{ .key = .{ .key = 'J', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = 'J', .action = .repeat, .mod = .{ .shift = true } } },
                },
                null,
                .{ .scroll = .{ .target = .log, .dir = .down, .pan = true } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'K', .action = .press } },
                    .{ .key = .{ .key = 'K', .action = .repeat } },
                    .{ .key = .{ .key = 'K', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = 'K', .action = .repeat, .mod = .{ .shift = true } } },
                },
                null,
                .{ .scroll = .{ .target = .log, .dir = .up, .pan = true } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press } },
                    .{ .key = .{ .key = 'j', .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .log, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press } },
                    .{ .key = .{ .key = 'k', .action = .repeat } },
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
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press, .mod = .{ .shift = true } } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat, .mod = .{ .shift = true } } },
                },
                .status,
                .{ .scroll = .{ .target = .log, .dir = .up, .pan = true } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press, .mod = .{ .shift = true } } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat, .mod = .{ .shift = true } } },
                },
                .status,
                .{ .scroll = .{ .target = .log, .dir = .down, .pan = true } },
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .evolog,
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
                .log_range_diff,
            });

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
                    .{ .functional = .{ .key = .up, .action = .press } },
                    .{ .functional = .{ .key = .up, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .diff, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .down, .action = .press } },
                    .{ .functional = .{ .key = .down, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .diff, .dir = .down } },
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

            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .left, .action = .press, .mod = .{} } },
                    .{ .functional = .{ .key = .left, .action = .repeat, .mod = .{} } },
                },
                null,
                .{ .resize_master = .left },
            );
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .right, .action = .press, .mod = .{} } },
                    .{ .functional = .{ .key = .right, .action = .repeat, .mod = .{} } },
                },
                null,
                .{ .resize_master = .right },
            );
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .evolog,
                .{ .rebase = .onto },
                .{ .rebase = .after },
                .{ .rebase = .before },
                .{ .duplicate = .onto },
                .{ .duplicate = .after },
                .{ .duplicate = .before },
                .new,
                .squash,
                .abandon,
                .log_range_diff,
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
            });

            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = '+', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = '+', .action = .repeat, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = '+', .action = .press, .mod = .{} } },
                    .{ .key = .{ .key = '+', .action = .repeat, .mod = .{} } },
                },
                null,
                .{ .change_diff_context = .{ .off = .increase } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = '_', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = '_', .action = .repeat, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = '_', .action = .press, .mod = .{} } },
                    .{ .key = .{ .key = '_', .action = .repeat, .mod = .{} } },
                },
                null,
                .{ .change_diff_context = .{ .off = .decrease } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = ')', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = ')', .action = .repeat, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = ')', .action = .press, .mod = .{} } },
                    .{ .key = .{ .key = ')', .action = .repeat, .mod = .{} } },
                },
                null,
                .{ .change_diff_context = .{ .off = .reset } },
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
                .{ .bookmark = .view_goto },
                .{ .git = .push },
                .{ .git = .fetch },
            });
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'J', .action = .press, .mod = .{} } },
                    .{ .key = .{ .key = 'J', .action = .repeat, .mod = .{} } },
                    .{ .key = .{ .key = 'J', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = 'J', .action = .repeat, .mod = .{ .shift = true } } },
                },
                null,
                .{ .scroll = .{ .target = .bookmarks, .dir = .down, .pan = true } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'K', .action = .press } },
                    .{ .key = .{ .key = 'K', .action = .repeat } },
                    .{ .key = .{ .key = 'K', .action = .press, .mod = .{ .shift = true } } },
                    .{ .key = .{ .key = 'K', .action = .repeat, .mod = .{ .shift = true } } },
                },
                null,
                .{ .scroll = .{ .target = .bookmarks, .dir = .up, .pan = true } },
            );

            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'j', .action = .press } },
                    .{ .key = .{ .key = 'j', .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .bookmarks, .dir = .down } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .key = .{ .key = 'k', .action = .press } },
                    .{ .key = .{ .key = 'k', .action = .repeat } },
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

            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .press, .mod = .{ .shift = true } } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_up, .action = .repeat, .mod = .{ .shift = true } } },
                },
                .bookmarks,
                .{ .scroll = .{ .target = .bookmarks, .dir = .up, .pan = true } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .press, .mod = .{ .shift = true } } },
                    .{ .mouse = .{ .pos = .{}, .key = .scroll_down, .action = .repeat, .mod = .{ .shift = true } } },
                },
                .bookmarks,
                .{ .scroll = .{ .target = .bookmarks, .dir = .down, .pan = true } },
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
            .{ .key = .{ .key = 'l' } },
            null,
            .switch_state_to_file_tree,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'v' } },
            null,
            .switch_state_to_evolog,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'L' } },
            null,
            .start_range_diff,
        );
        try map.add_one_for_state(
            .log,
            .{ .key = .{ .key = 'L', .mod = .{ .shift = true } } },
            null,
            .start_range_diff,
        );
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
            });
            try map.add_one(
                .{ .key = .{ .key = 'h' } },
                null,
                .{ .file_tree_collapse = .{ .collapse = true } },
            );
            try map.add_one(
                .{ .key = .{ .key = 'l' } },
                null,
                .{ .file_tree_collapse = .{ .collapse = false } },
            );
            try map.add_one(
                .{ .key = .{ .key = 'o' } },
                null,
                .open_temp_file,
            );
            try map.add_one(
                .{ .key = .{ .key = 'O' } },
                null,
                .open_source_file,
            );
            try map.add_one(
                .{ .key = .{ .key = 'O', .mod = .{ .shift = true } } },
                null,
                .open_source_file,
            );
        }
        try map.add_one_for_state(
            .{ .file_tree = .list },
            .{ .key = .{ .key = 'd' } },
            null,
            .toggle_file_tree_diff,
        );
        try map.add_one_for_state(
            .{ .file_tree = .diff },
            .{ .key = .{ .key = 'd' } },
            null,
            .toggle_file_tree_diff,
        );
        try map.add_one_for_state(
            .{ .file_tree = .diff },
            .{ .key = .{ .key = 'f' } },
            null,
            .toggle_file_tree_full_context,
        );
        try map.add_one_for_state(
            .{ .file_tree = .range_diff },
            .{ .key = .{ .key = 'f' } },
            null,
            .toggle_file_tree_full_context,
        );
        try map.add_one_for_state(
            .{ .file_tree = .diff },
            .{ .key = .{ .key = 'D', .mod = .{ .shift = true } } },
            null,
            .toggle_file_tree_only_changed,
        );
        try map.add_one_for_state(
            .{ .file_tree = .range_diff },
            .{ .key = .{ .key = 'D', .mod = .{ .shift = true } } },
            null,
            .toggle_file_tree_only_changed,
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
                .{ .bookmark = .search_goto },
                .{ .git = .fetch_search },
                .{ .git = .push_search },
                .{ .file_tree = .search_list },
                .{ .file_tree = .search_diff },
                .{ .file_tree = .search_range_diff },
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
        try map.add_one_for_state(
            .{ .bookmark = .view },
            .{ .key = .{ .key = 'g' } },
            null,
            .switch_state_to_bookmark_goto,
        );
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .{ .bookmark = .view },
                .{ .bookmark = .view_goto },
                .{ .git = .fetch },
                .{ .git = .push },
                .{ .file_tree = .list },
                .{ .file_tree = .diff },
                .{ .file_tree = .range_diff },
            });
            try map.add_one(
                .{ .key = .{ .key = '/', .mod = .{} } },
                null,
                .start_search,
            );
        }
        try map.add_one_for_state(
            .{ .bookmark = .view_goto },
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_bookmark_goto,
        );
        try map.add_one_for_state(
            .{ .bookmark = .view_goto },
            .{ .key = .{ .key = 'n' } },
            null,
            .new_commit_from_bookmark,
        );
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
        try map.add_one_for_state(
            .{ .git = .fetch_new },
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_jj_git_fetch_new,
        );
        try map.add_one_for_state(
            .{ .git = .fetch_new },
            .{ .functional = .{ .key = .escape } },
            null,
            .{ .end_search = .{ .reset = true } },
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
        try map.add_one_for_state(
            .{ .git = .fetch },
            .{ .key = .{ .key = 'n' } },
            null,
            .switch_state_to_git_fetch_new,
        );
        try map.add_one_for_state(
            .{ .git = .fetch_new },
            .{ .functional = .{ .key = .enter } },
            null,
            .apply_jj_git_fetch_new,
        );
        try map.add_one_for_state(
            .{ .git = .fetch_new },
            .{ .functional = .{ .key = .escape } },
            null,
            .{ .end_search = .{ .reset = true } },
        );
        try map.add_one_for_state(
            .log_range_diff,
            .{ .key = .{ .key = 'l' } },
            null,
            .switch_state_to_file_tree,
        );
        try map.add_one_for_state(
            .log_range_diff,
            .{ .functional = .{ .key = .escape } },
            null,
            .go_back_a_mode,
        );

        return map.build();
    }

    pub fn get_change_range(self: *@This()) components_mod.FileTreeSlate.RangeContext {
        return .{ .to = self.renderer.log.focused_change, .from = self.file_tree_from };
    }

    pub fn get_file_tree_context_len(self: *@This()) u32 {
        const full_context = if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| list.full_context else false;
        return if (full_context) 9999 else self.file_tree_diff_context;
    }

    pub fn get_file_tree_show_context(self: *@This(), from: ?Change, node_status: ?jj_mod.Schema.FileTreeDiffEntry.Status) struct { from: ?Change, from_hash: ?Change.Hash, context: u32, is_diff: bool } {
        const is_diff = (node_status != null and self.state.is_file_tree_diff());
        return .{
            .from = if (is_diff) from else null,
            .from_hash = if (is_diff) (if (from) |f| f.hash else null) else null,
            .context = if (is_diff) self.get_file_tree_context_len() else 0,
            .is_diff = is_diff,
        };
    }

    // thread safety: do not use from other threads
    pub fn _send_event(self: *@This(), event: Event) !void {
        switch (event) {
            .rerender => {
                self.renderer.rerender_pending_count += 1;
            },
            else => {},
        }

        try self.events.send(event);
    }

    fn _wait_recv_event(self: *@This()) ?Event {
        const event = self.events.wait_recv() orelse return null;
        switch (event) {
            .rerender => {
                self.renderer.rerender_pending_count -|= 1;
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
            bookmarks_enabled: bool = false,
            bookmark_search_enabled: bool = false,
            file_tree_search_enabled: bool = false,
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
                    .bookmarks_enabled = true,
                    .input_text = true,
                    .show_help = true,
                },
                .view, .view_goto => .{
                    .bookmarks_enabled = true,
                    .show_help = true,
                },
                .search, .search_goto => .{
                    .bookmarks_enabled = true,
                    .bookmark_search_enabled = true,
                    .input_text = true,
                    .show_help = true,
                },
            },
            .git => |state| switch (state) {
                .none => .{
                    .show_help = true,
                },
                .fetch => .{
                    .bookmarks_enabled = true,
                    .show_help = true,
                },
                .push => .{
                    .bookmarks_enabled = true,
                    .show_help = true,
                },
                .fetch_search => .{
                    .bookmarks_enabled = true,
                    .bookmark_search_enabled = true,
                    .input_text = true,
                    .show_help = true,
                },
                .push_search => .{
                    .bookmarks_enabled = true,
                    .bookmark_search_enabled = true,
                    .input_text = true,
                    .show_help = true,
                },
                .fetch_new => .{
                    .bookmarks_enabled = false,
                    .input_text = true,
                    .show_help = true,
                },
            },
            .oplog, .evolog, .log => .{},
            .file_tree => |state| switch (state) {
                .list, .diff, .range_diff => .{},
                .search_list, .search_diff, .search_range_diff => .{
                    .file_tree_search_enabled = true,
                    .input_text = true,
                },
            },
            .log_range_diff => .{
                .colored_gutter_cursor = true,
            },
        };

        switch (event) {
            .quit => return error.Quit,
            .err => |err| return err,
            .rerender => {
                var should_render = false;
                // should_render = should_render or self.renderer.rerender_pending_count == 0;
                should_render = should_render or self.events.count() < 5;
                should_render = should_render or self.renderer.rerender_pending_since > 50;

                if (should_render) {
                    self.renderer.rerender_pending_since = 0;
                    try self.renderer.render(self, tropes, temp);
                } else {
                    self.renderer.rerender_pending_since += 1;
                }
            },
            .sigwinch => {
                try self.renderer.screen.update_size();
                try self._send_event(.rerender);
            },
            .scroll_update => {
                const log = switch (self.state) {
                    .evolog => &self.renderer.evolog,
                    else => &self.renderer.log,
                };
                log.changes.reset(log.status.buf);
                var i: i32 = 0;
                while (try log.changes.next()) |parsed| {
                    const change = jj_mod.Change.from_parsed(&parsed);

                    // const n: i32 = 3;
                    const n: i32 = 0;
                    if (log.y == i) {
                        log.focused_change = change;
                    } else if (@abs(log.y - i) < n) {
                        const diff = try self.diff.cache.getOrPut(change.hash);
                        if (!diff.found_existing) {
                            diff.val.* = .{};
                            try self.jj_request(.{ .diff = change });
                        }
                    } else if (log.y + n < i) {
                        break;
                    }

                    if (self.state == .log and i > log.limit - 50) {
                        log.limit += 200;
                        try self.jj_request(.{ .log = .{ .n = log.limit } });
                    }
                    i += 1;
                }

                if (self.renderer.diff.get(log.focused_change.hash, .touch)) |_| {
                    try self._send_event(.rerender);
                } else {
                    // debounce diff requests
                    try self.sleeper.delay_event(20, .{ .diff_update = .{
                        .change = log.focused_change,
                        .context = self.renderer.diff.context,
                    } });
                }
            },
            .file_show_scroll_update => {
                const tree = self.renderer.file_tree.cache.get(self.get_change_range(), .touch) orelse return;
                if (tree.get_focused_file()) |focused| {
                    // debounce
                    try self.sleeper.delay_event(20, .{ .file_show_update = .{
                        .to = self.renderer.log.focused_change,
                        .from = self.file_tree_from,
                        .path = focused,
                        .context = self.get_file_tree_context_len(),
                    } });
                    try self._send_event(.rerender);
                }
            },
            .file_show_update => |v| {
                if (!std.mem.eql(u8, v.to.hash[0..], self.renderer.log.focused_change.hash[0..])) return;
                if (v.context != self.get_file_tree_context_len()) return;
                const tree = self.renderer.file_tree.cache.get(.{ .to = v.to, .from = v.from }, .touch) orelse return;

                if (tree.get_focused_file()) |focused_file| {
                    if (!std.mem.eql(u8, focused_file, v.path)) return;
                    const res = self.get_file_tree_show_context(v.from, if (tree.focused_node) |node| node.status else null);

                    const key_lookup = components_mod.FileShowSlate.Key{
                        .to = v.to.hash,
                        .from = res.from_hash,
                        .path = v.path,
                        .context = res.context,
                    };

                    var cfile: *components_mod.FileShowSlate.CachedFile = undefined;
                    var path_to_use: []const u8 = undefined;
                    if (self.renderer.file_show.filecache.get(key_lookup, .touch)) |found| {
                        cfile = found;
                        path_to_use = key_lookup.path;
                    } else {
                        const path = try self.alloc.dupe(u8, v.path);
                        const entry = try self.renderer.file_show.filecache.getOrPut(.{
                            .to = v.to.hash,
                            .from = res.from_hash,
                            .path = path,
                            .context = res.context,
                        });
                        entry.val.* = .{};
                        cfile = entry.val;
                        path_to_use = entry.key.path;
                    }

                    if (res.is_diff) {
                        if (cfile.diff == null) {
                            try app.jj_request(.{ .file_content = .{
                                .to = v.to,
                                .from = res.from,
                                .path = path_to_use,
                                .mode = .diff,
                                .context = res.context,
                            } });
                        }
                    } else {
                        if (cfile.content == null) {
                            try app.jj_request(.{
                                .file_content = .{
                                    .to = v.to,
                                    .from = null, // Plain show is always from one commit
                                    .path = path_to_use,
                                    .mode = .plain,
                                    .context = 0,
                                },
                            });
                        }
                    }
                }
            },
            .op_update => {
                const oplog = &self.renderer.oplog;
                oplog.ops.reset(oplog.oplog);
                var i: i32 = 0;
                while (try oplog.ops.next()) |parsed| {
                    const op = jj_mod.Operation.from_parsed(&parsed);

                    // const n: i32 = 3;
                    const n: i32 = 0;
                    if (oplog.y == i) {
                        oplog.focused_op = op;
                    } else if (@abs(oplog.y - i) < n) {
                        const diff = try self.opshow.cache.getOrPut(op.hash);
                        if (!diff.found_existing) {
                            diff.val.* = .{};
                            try self.jj_request(.{ .opshow = op });
                        }
                    } else if (oplog.y + n < i) {
                        break;
                    }
                    i += 1;
                }

                if (self.renderer.opshow.get(oplog.focused_op.hash, .touch)) |_| {
                    try self._send_event(.rerender);
                } else {
                    // debounce op show requests
                    try self.sleeper.delay_event(20, .{ .opshow_update = oplog.focused_op });
                }
            },
            .diff_update => |v| {
                const focused = switch (self.state) {
                    .evolog => self.renderer.evolog.focused_change,
                    else => self.renderer.log.focused_change,
                };
                if (std.mem.eql(u8, v.change.hash[0..], focused.hash[0..]) and self.renderer.diff.context == v.context) {
                    const diff = try self.renderer.diff.getOrPut(
                        v.change.hash,
                        v.context,
                    );
                    if (!diff.found_existing) {
                        diff.val.* = .{};
                        try self.jj_request(.{ .diff = .{ .change = v.change, .context = v.context } });
                    }
                }
            },
            .opshow_update => |op| {
                if (std.mem.eql(u8, op.hash[0..], self.renderer.oplog.focused_op.hash[0..])) {
                    const diff = try self.renderer.opshow.getOrPut(op.hash, self.renderer.opshow.context);
                    if (!diff.found_existing) {
                        diff.val.* = .{};
                        try self.jj_request(.{ .opshow = op });
                    }
                }
            },
            .toast => |toast| {
                const id = try self.renderer.toaster.add(toast);
                try self.sleeper.delay_event(500, .{ .pop_toast = id });
            },
            .pop_toast => |id| {
                self.renderer.toaster.remove(id);
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
                            try self.renderer.text_input.write(cast(u8, key.key));
                        }
                    },
                    .functional => |key| {
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{})) {
                            self.renderer.text_input.left();
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{})) {
                            self.renderer.text_input.right();
                        }
                        if (key.key == .left and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.renderer.text_input.left_word();
                        }
                        if (key.key == .right and key.action.pressed() and key.mod.eq(.{ .ctrl = true })) {
                            self.renderer.text_input.right_word();
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{})) {
                            _ = self.renderer.text_input.back();
                        }
                        if (key.key == .backspace and key.action.pressed() and key.mod.eq(.{ .alt = true })) {
                            _ = self.renderer.text_input.back();
                            while (true) {
                                if (' ' == self.renderer.text_input.peek_back() orelse break) {
                                    break;
                                }
                                _ = self.renderer.text_input.back();
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
                        for (self.renderer.mouse_regions.items) |region| {
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
                            .view_goto => {
                                self.state = .{ .bookmark = .search_goto };
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
                        .file_tree => |s| switch (s) {
                            .list => {
                                self.state = .{ .file_tree = .search_list };
                                return;
                            },
                            .diff => {
                                self.state = .{ .file_tree = .search_diff };
                                return;
                            },
                            .range_diff => {
                                self.state = .{ .file_tree = .search_range_diff };
                                return;
                            },
                            else => {},
                        },
                        else => {},
                    }

                    unreachable;
                },
                .end_search => |v| {
                    defer if (v.reset) self.renderer.text_input.reset();
                    switch (self.state) {
                        .bookmark => |s| switch (s) {
                            .search => {
                                self.state = .{ .bookmark = .view };
                                return;
                            },
                            .search_goto => {
                                self.state = .{ .bookmark = .view_goto };
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
                            .fetch_new => {
                                self.state = .{ .git = .fetch };
                                return;
                            },
                            else => {},
                        },
                        .file_tree => |s| switch (s) {
                            .search_list, .search_diff, .search_range_diff => {
                                self.state = .{ .file_tree = .from(self.state.file_tree.base_mode()) };

                                if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                                    if (v.reset) {
                                        if (list.initial_y) |y| list.y = y;
                                        for (list.search_expanded_nodes.items) |node| {
                                            node.collapsed = true;
                                        }
                                    }
                                    list.initial_y = null;
                                    list.search_expanded_nodes.clearRetainingCapacity();

                                    const is_diff = self.state.file_tree.is_diff();
                                    const only_changed = if (list.mode.is_diff()) list.only_changed else false;
                                    try list.update_focused_node(!is_diff, only_changed);
                                }
                                self.renderer.text_input.reset();
                                try self._send_event(.file_show_scroll_update);
                                return;
                            },
                            else => {},
                        },
                        else => {},
                    }

                    unreachable;
                },
                .fancy_terminal_features_that_break_gdb => |set| switch (set) {
                    .disable => try self.renderer.screen.term.fancy_features_that_break_gdb(.disable, .{}),
                    .enable => try self.renderer.screen.term.fancy_features_that_break_gdb(.enable, .{}),
                },
                .trigger_breakpoint => {
                    try self.renderer.screen.term.fancy_features_that_break_gdb(.disable, .{});
                    @breakpoint();
                },
                .refresh_master_content => {
                    switch (self.state) {
                        .oplog => try self.jj_request(.{ .oplog = .{} }),
                        .evolog => try self.jj_request(.{ .evolog = self.renderer.log.focused_change }),
                        else => {},
                    }
                    self.renderer.log.limit = self.renderer.log.calc_limit(.{});
                    try self.jj_request(.{ .log = .{ .n = self.renderer.log.limit } });
                },
                .toggle_file_tree_full_context => {
                    if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                        list.full_context = !list.full_context;
                    }
                    try self._send_event(.file_show_scroll_update);
                },
                .toggle_file_tree_only_changed => {
                    if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                        list.only_changed = !list.only_changed;
                    }
                    try self._send_event(.rerender);
                },
                .scroll => |target| switch (target.target) {
                    .log => {
                        if (target.pan) {
                            switch (self.state) {
                                .oplog => {
                                    switch (target.dir) {
                                        .up => self.renderer.oplog.skip_y = @max(0, self.renderer.oplog.skip_y - 1),
                                        .down => self.renderer.oplog.skip_y += 1,
                                    }
                                },
                                .evolog => {
                                    switch (target.dir) {
                                        .up => self.renderer.evolog.skip_y = @max(0, self.renderer.evolog.skip_y - 1),
                                        .down => self.renderer.evolog.skip_y += 1,
                                    }
                                },
                                .file_tree => |_| {
                                    const tree = self.renderer.file_tree.cache.get(self.get_change_range(), .touch).?;
                                    switch (target.dir) {
                                        .up => tree.skip_y = @max(0, tree.skip_y - 1),
                                        .down => tree.skip_y += 1,
                                    }
                                },
                                else => {
                                    switch (target.dir) {
                                        .up => self.renderer.log.skip_y = @max(0, self.renderer.log.skip_y - 1),
                                        .down => self.renderer.log.skip_y += 1,
                                    }
                                },
                            }
                        } else {
                            switch (self.state) {
                                .oplog => {
                                    switch (target.dir) {
                                        .up => self.renderer.oplog.y -= 1,
                                        .down => self.renderer.oplog.y += 1,
                                    }
                                    try self._send_event(.op_update);
                                },
                                .evolog => {
                                    switch (target.dir) {
                                        .up => self.renderer.evolog.y -= 1,
                                        .down => self.renderer.evolog.y += 1,
                                    }
                                    try self._send_event(.scroll_update);
                                },
                                .file_tree => |_| {
                                    const tree = self.renderer.file_tree.cache.get(self.get_change_range(), .touch).?;
                                    switch (target.dir) {
                                        .up => tree.y -= 1,
                                        .down => tree.y += 1,
                                    }
                                    const is_diff = self.state.is_file_tree_diff();
                                    const only_changed = if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| list.only_changed else false;
                                    try tree.update_focused_node(!is_diff, only_changed and is_diff);
                                    try self._send_event(.file_show_scroll_update);
                                },
                                else => {
                                    switch (target.dir) {
                                        .up => self.renderer.log.y -= 1,
                                        .down => self.renderer.log.y += 1,
                                    }
                                    try self._send_event(.scroll_update);
                                },
                            }
                        }
                    },
                    .diff => {
                        switch (self.state) {
                            .oplog => {
                                if (self.renderer.opshow.get(self.renderer.oplog.focused_op.hash, .touch)) |opshow| {
                                    switch (target.dir) {
                                        .up => opshow.y -= 10,
                                        .down => opshow.y += 10,
                                    }
                                }
                            },
                            .file_tree => |_| {
                                const tree = self.renderer.file_tree.cache.get(self.get_change_range(), .touch).?;
                                if (tree.get_focused_file()) |focused_file| {
                                    const res = self.get_file_tree_show_context(self.file_tree_from, if (tree.focused_node) |node| node.status else null);

                                    const key_lookup = components_mod.FileShowSlate.Key{
                                        .to = self.renderer.log.focused_change.hash,
                                        .from = res.from_hash,
                                        .path = focused_file,
                                        .context = res.context,
                                    };
                                    if (self.renderer.file_show.filecache.get(key_lookup, .touch)) |cfile| {
                                        switch (target.dir) {
                                            .up => cfile.y -= 10,
                                            .down => cfile.y += 10,
                                        }
                                    }
                                }
                            },
                            .evolog => {
                                if (self.renderer.diff.get(self.renderer.evolog.focused_change.hash, .touch)) |diff| {
                                    switch (target.dir) {
                                        .up => diff.y -= 10,
                                        .down => diff.y += 10,
                                    }
                                }
                            },
                            else => {
                                if (self.renderer.diff.get(self.renderer.log.focused_change.hash, .touch)) |diff| {
                                    switch (target.dir) {
                                        .up => diff.y -= 10,
                                        .down => diff.y += 10,
                                    }
                                }
                            },
                        }
                    },
                    .bookmarks => {
                        switch (target.dir) {
                            .up => self.renderer.bookmarks.y -= 1,
                            .down => self.renderer.bookmarks.y += 1,
                        }
                    },
                },
                .resize_master => |dir| switch (dir) {
                    .left => self.renderer.x_split -= 0.05,
                    .right => self.renderer.x_split += 0.05,
                },
                .change_diff_context => |v| {
                    const log = switch (self.state) {
                        .evolog => &self.renderer.evolog,
                        else => &self.renderer.log,
                    };

                    if (self.state == .file_tree) {
                        if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                            list.full_context = false;
                        }
                        switch (v.off) {
                            .reset => self.file_tree_diff_context = 30,
                            .increase => self.file_tree_diff_context += 10,
                            .decrease => self.file_tree_diff_context -|= 10,
                        }

                        // already debounced
                        try self._send_event(.file_show_scroll_update);
                    } else {
                        switch (v.off) {
                            .reset => self.renderer.diff.context = 3,
                            .increase => self.renderer.diff.context += 10,
                            .decrease => self.renderer.diff.context -|= 10,
                        }

                        const diff = self.renderer.diff.get(log.focused_change.hash, .touch);
                        if (diff == null) {
                            try self.sleeper.delay_event(20, .{ .diff_update = .{
                                .change = log.focused_change,
                                .context = self.renderer.diff.context,
                            } });
                        }
                    }
                },
                .go_back_a_mode => {
                    self.renderer.log.selected_changes.clearRetainingCapacity();
                    self.renderer.text_input.reset();
                    self.renderer.show_help = false;

                    switch (self.state) {
                        .file_tree => {
                            if (self.file_tree_from != null) {
                                self.state = .log_range_diff;
                            } else {
                                self.state = .log;
                            }
                        },
                        else => {
                            self.file_tree_from = null;
                            self.state = .log;
                        },
                    }
                },
                .select_focused_change => {
                    if (self.renderer.log.selected_changes.fetchOrderedRemove(self.renderer.log.focused_change) == null) {
                        try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
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
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .jj_edit => {
                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "edit", self.renderer.log.focused_change.id[0..] });
                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .switch_state_to_git => {
                    self.state = .{ .git = .none };
                    // self.show_help = true;
                },
                .switch_state_to_rebase_onto => {
                    self.state = .{ .rebase = .onto };
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .switch_state_to_squash => {
                    self.state = .squash;
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .switch_state_to_abandon => {
                    self.state = .abandon;
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .switch_state_to_oplog => {
                    self.state = .oplog;
                    try self.jj_request(.{ .oplog = .{ .reset_pos = true } });
                },
                .switch_state_to_duplicate => {
                    self.state = .{ .duplicate = .onto };
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .switch_state_to_bookmarks_view => {
                    self.state = .{ .bookmark = .view };
                    try self.jj_request(.bookmark);
                },
                .switch_state_to_bookmark_goto => {
                    self.state = .{ .bookmark = .view_goto };
                },
                .switch_state_to_evolog => {
                    self.state = .evolog;
                    try self.jj_request(.{ .evolog = self.renderer.log.focused_change });
                },
                .switch_state_to_file_tree => {
                    switch (self.state) {
                        .log => {
                            if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                                self.state = .{
                                    .file_tree = switch (list.mode) {
                                        .list => .list,
                                        .diff => .diff,
                                        .range_diff => .range_diff,
                                    },
                                };
                            } else {
                                self.state = .{ .file_tree = .list };
                            }
                        },
                        .log_range_diff => {
                            self.state = .{ .file_tree = .range_diff };
                        },
                        else => unreachable,
                    }

                    try self.jj_request(.{ .file_tree = self.get_change_range() });
                    try self._send_event(.rerender);
                },
                .toggle_file_tree_diff => {
                    std.debug.assert(self.state == .file_tree);

                    if (self.state.file_tree == .list) {
                        self.state = .{ .file_tree = .diff };
                    } else {
                        self.state = .{ .file_tree = .list };
                    }

                    if (self.renderer.file_tree.cache.get(self.get_change_range(), .touch)) |list| {
                        list.mode = self.state.file_tree.base_mode();
                    }
                    try self.jj_request(.{ .file_tree = self.get_change_range() });
                    try self._send_event(.rerender);
                },
                .toggle_help => {
                    self.renderer.show_help = !self.renderer.show_help;
                },
                .jj_split => {
                    try self.execute_interactive_command(&[_][]const u8{
                        "jj",
                        "split",
                        "-r",
                        self.renderer.log.focused_change.id[0..],
                    });
                },
                .jj_describe => {
                    try self.execute_interactive_command(&[_][]const u8{
                        "jj",
                        "describe",
                        "-r",
                        self.renderer.log.focused_change.id[0..],
                    });
                },
                .switch_state_to_git_fetch_new => {
                    self.state = .{ .git = .fetch_new };
                    self.renderer.text_input.reset();
                },
                .switch_state_to_command => {
                    self.state = .command;
                    self.renderer.text_input.reset();
                },
                .apply_jj_rebase => |v| {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "rebase" });

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        _ = try cmd.add_args(&[_][]const u8{ "-r", e.key_ptr.id[0..] });

                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.RebaseOnSelected }, try self.alloc.dupe(u8, "Cannot rebase on selected change"));
                            cmd.deinit();
                            return;
                        }
                    }

                    switch (self.state.rebase) {
                        .onto => _ = try cmd.arg("-d"),
                        .after => _ = try cmd.arg("-A"),
                        .before => _ = try cmd.arg("-B"),
                    }

                    _ = try cmd.arg(self.renderer.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        _ = try cmd.arg("--ignore-immutable");
                    }

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .start_range_diff => {
                    self.file_tree_from = self.renderer.log.focused_change;
                    self.state = .log_range_diff;
                },
                .apply_jj_abandon => |v| {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "abandon", "--retain-bookmarks" });

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        _ = try cmd.arg(e.key_ptr.id[0..]);
                    }

                    if (v.ignore_immutable) {
                        _ = try cmd.arg("--ignore-immutable");
                    }

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_squash => |v| {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "squash" });

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.SquashOnSelected }, try self.alloc.dupe(u8, "Cannot squash on selected change"));
                            cmd.deinit();
                            return;
                        }
                        _ = try cmd.add_args(&[_][]const u8{ "--from", e.key_ptr.id[0..] });
                    }

                    _ = try cmd.arg("--into");
                    _ = try cmd.arg(self.renderer.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        _ = try cmd.arg("--ignore-immutable");
                    }

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_new => {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "new" });

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        _ = try cmd.arg(e.key_ptr.id[0..]);
                    }

                    try self.jj_request(.{ .command = .{
                        .cmd = cmd,
                        .refresh_log = true,
                        .reset_log_pos = true,
                    } });
                },
                .execute_command_in_input_buffer => |e| {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                        self.renderer.show_help = false;
                    }

                    var args = std.ArrayList([]const u8).init(temp);

                    // TODO: support parsing and passing "string" and 'string' with \" \' and spaces properly
                    var arg_it = std.mem.splitAny(u8, self.renderer.text_input.text.items, &std.ascii.whitespace);
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
                        var cmd = utils_mod.Command.init(self.alloc);
                        errdefer cmd.deinit();
                        _ = try cmd.add_args(args.items);
                        try self.jj_toasted_request(.{ .command = .{
                            .cmd = cmd,
                            .toast_success = true,
                            .refresh_log = true,
                        } }, "Executing command...");
                    }
                },
                .apply_jj_op_restore => {
                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "op",
                        "restore",
                        self.renderer.oplog.focused_op.hash[0..],
                    });
                    try self.jj_request(.{ .command = .{
                        .cmd = cmd,
                        .refresh_log = true,
                        .reset_oplog_pos = true,
                        .refresh_oplog = true,
                    } });
                },
                .apply_jj_duplicate => {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "duplicate" });

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.DuplicateOnSelected }, try self.alloc.dupe(u8, "Cannot duplicate on selected change"));
                            cmd.deinit();
                            return;
                        }
                        _ = try cmd.arg(e.key_ptr.id[0..]);
                    }

                    switch (self.state.duplicate) {
                        .onto => _ = try cmd.arg("-d"),
                        .after => _ = try cmd.arg("-A"),
                        .before => _ = try cmd.arg("-B"),
                    }

                    _ = try cmd.arg(self.renderer.log.focused_change.id[0..]);

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .switch_state_to_bookmark_create => {
                    self.state = .{ .bookmark = .create };
                },
                .apply_bookmark_goto => {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }

                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;
                    const target = bookmark.parsed.target[0] orelse return;

                    try self.renderer.log.focus_commit(target);
                },
                .new_commit_from_bookmark => {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }

                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

                    // TODO: why multiple targets?
                    if (bookmark.parsed.target.len != 1 and bookmark.parsed.target[0] != null) {
                        try self._toast(.{ .err = error.MultipleTargetsFound }, try self.alloc.dupe(u8, "Error executing command"));
                        return;
                    }
                    const target = bookmark.parsed.target[0].?;

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "new", "-r", target });
                    try self.jj_request(.{ .command = .{
                        .cmd = cmd,
                        .refresh_log = true,
                        .reset_log_pos = true,
                    } });
                },
                .move_bookmark_to_selected => |v| {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "move",
                        bookmark.parsed.name,
                        "--to",
                        self.renderer.log.focused_change.id[0..],
                    });
                    if (v.allow_backwards) {
                        _ = try cmd.arg("--allow-backwards");
                    }

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_bookmark_delete => {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;
                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "bookmark", "delete", bookmark.parsed.name });
                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_bookmark_forget => |v| {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{ "jj", "bookmark", "forget", bookmark.parsed.name });
                    if (v.include_remotes) {
                        _ = try cmd.arg("--include-remotes");
                    }

                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_bookmark_create_from_input_buffer_on_selected_change => {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }

                    var cmd = utils_mod.Command.init(self.alloc);
                    errdefer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "create",
                        "-r",
                        self.renderer.log.focused_change.id[0..],
                        self.renderer.text_input.text.items,
                    });
                    try self.jj_request(.{ .command = .{ .cmd = cmd, .refresh_log = true } });
                },
                .apply_jj_git_fetch_new => {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }
                    var req = JujutsuServer.Request{
                        .git_fetch = .{
                            .branch = null,
                            .remote = null,
                        },
                    };
                    const text = std.mem.trim(u8, self.renderer.text_input.text.items, &std.ascii.whitespace);
                    if (text.len > 0) {
                        req.git_fetch.branch = text;
                        try self.jj_toasted_request(req, "Fetching from remote...");
                    }
                },
                .apply_jj_git_fetch => {
                    defer self.state = .log;
                    var req = JujutsuServer.Request{
                        .git_fetch = .{
                            .branch = null,
                            .remote = null,
                        },
                    };
                    if (self.state.git == .fetch) {
                        const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;
                        req.git_fetch.branch = bookmark.parsed.name;
                        if (bookmark.parsed.remote) |remote| {
                            req.git_fetch.remote = remote;
                        }
                    }

                    try self.jj_toasted_request(req, "Fetching from remote...");
                },
                .apply_jj_git_push_selected => |v| {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

                    var req = JujutsuServer.Request{
                        .git_push = .{
                            .branch = null,
                            .remote = null,
                            .allow_new = false,
                        },
                    };
                    req.git_push.branch = bookmark.parsed.name;
                    if (v.allow_new) {
                        req.git_push.allow_new = true;
                    } else if (bookmark.parsed.remote) |remote| {
                        req.git_push.remote = remote;
                    }
                    try self.jj_toasted_request(req, "Pushing to remote...");
                },
                .switch_state_to_git_fetch => {
                    self.state = .{ .git = .fetch };
                    try self.jj_request(.bookmark);
                },
                .switch_state_to_git_push => {
                    self.state = .{ .git = .push };
                    try self.jj_request(.bookmark);
                },
                .open_temp_file => {
                    if (self.state != .file_tree) return;
                    const change = self.get_change_range();
                    const list = self.renderer.file_tree.cache.get(change, .touch) orelse return;
                    const node = list.focused_node orelse return;
                    if (node.typ != .file) return;

                    var cmd = utils_mod.Command.init(temp);
                    defer cmd.deinit();
                    _ = try cmd.add_args(&[_][]const u8{
                        "jj",
                        "file",
                        "show",
                        "-r",
                        change.to.hash[0..],
                        node.path,
                    });
                    const content = cmd.exec_capture(temp, temp) catch |e| {
                        try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not read contents of file"));
                        return;
                    };

                    var content_it = try term_mod.TermStyledGraphemeIterator.init(&self.renderer.screen.unicode_width_table, content);

                    const temp_file_name = try temp.dupe(u8, node.path);
                    std.mem.replaceScalar(u8, temp_file_name, '/', '_');

                    const temp_file_path = try std.fmt.allocPrint(
                        temp,
                        "/tmp/jjazy/{s}-{s}",
                        .{
                            change.to.hash,
                            temp_file_name,
                        },
                    );

                    std.fs.makeDirAbsolute("/tmp/jjazy") catch |e| switch (e) {
                        error.PathAlreadyExists => {},
                        else => {
                            try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not create temp file"));
                            return;
                        },
                    };
                    blk: {
                        const temp_file = std.fs.createFileAbsolute(temp_file_path, .{}) catch |e| {
                            try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not create temp file"));
                            return;
                        };
                        defer temp_file.close();

                        while (content_it.next() catch |e| {
                            try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not create temp file"));
                            return;
                        }) |tok| {
                            // skip non utf8
                            if (tok.codepoint) |_| continue;

                            temp_file.writeAll(tok.grapheme) catch |e| {
                                try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not create temp file"));
                                return;
                            };
                        }

                        // set file as readonly just to stop user from forgetting that this is a temp file
                        const meta = temp_file.metadata() catch break :blk;
                        var perms = meta.permissions();
                        perms.setReadOnly(true);
                        temp_file.setPermissions(perms) catch break :blk;
                    }

                    const editor = self.envmap.get("EDITOR") orelse "vi";
                    try self.execute_interactive_command(&[_][]const u8{
                        editor,
                        temp_file_path,
                    });

                    std.fs.deleteFileAbsolute(temp_file_path) catch |e| {
                        try self._toast(.{ .err = e }, try self.alloc.dupe(u8, "Could not delete temp file"));
                        return;
                    };
                },
                .open_source_file => {
                    if (self.state != .file_tree) return;
                    const list = self.renderer.file_tree.cache.get(self.get_change_range(), .touch) orelse return;
                    const node = list.focused_node orelse return;
                    if (node.typ != .file) return;

                    const editor = self.envmap.get("EDITOR") orelse "vi";
                    try self.execute_interactive_command(&[_][]const u8{
                        editor,
                        node.path,
                    });
                },
                .file_tree_collapse => |v| {
                    const list = self.renderer.file_tree.cache.get(self.get_change_range(), .touch).?;
                    const node = list.focused_node orelse return;
                    switch (node.typ) {
                        .file => {
                            if (v.collapse) {
                                const is_diff = self.state.is_file_tree_diff();
                                const only_changed = if (list.mode.is_diff()) list.only_changed else false;
                                const parent = try list.focus_parent(!is_diff, only_changed);
                                if (parent == null) {
                                    try self._handle_event(.{ .action = .go_back_a_mode });
                                    return;
                                }
                            }
                        },
                        .dir => {
                            if (v.collapse) {
                                if (!node.collapsed) {
                                    node.collapsed = true;
                                    return;
                                }

                                const is_diff = self.state.is_file_tree_diff();
                                const only_changed = if (list.mode.is_diff()) list.only_changed else false;
                                const parent = try list.focus_parent(!is_diff, only_changed);
                                if (parent) |_| {
                                    return;
                                }

                                try self._handle_event(.{ .action = .go_back_a_mode });
                            } else {
                                node.collapsed = false;
                            }
                        },
                    }
                },
            },
            .jj => |res| switch (res.req) {
                .log => {
                    switch (res.res) {
                        .ok => |log| {
                            if (res.req.log.reset_pos) {
                                self.renderer.log.y = 0;
                                self.renderer.log.focused_change = .{};
                            }
                            try self.renderer.log.update(log);
                            try self._send_event(.scroll_update);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJLogFailed }, buf.buf),
                        else => unreachable,
                    }

                    try self._send_event(.rerender);
                },
                .evolog => {
                    switch (res.res) {
                        .ok => |log| {
                            try self.renderer.evolog.update(log);
                            try self._send_event(.scroll_update);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJEvLogFailed }, buf.buf),
                        else => unreachable,
                    }
                },
                .diff => |req| {
                    switch (res.res) {
                        .with_status => |diff| {
                            // NOTE: using the .context from original request
                            const empty_diff = self.renderer.diff.cache.get(.{
                                .hash = req.change.hash,
                                .context = req.context,
                            }, .touch);

                            if (empty_diff) |d| {
                                d.* = .{
                                    .buf = diff.buf,
                                    .status = diff.status,
                                };
                            } else {
                                // too late. it got removed already
                                self.alloc.free(diff.buf.buf);
                                self.alloc.free(diff.status.buf);
                            }
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJDiffFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .oplog => {
                    switch (res.res) {
                        .ok => |buf| {
                            if (res.req.oplog.reset_pos) {
                                self.renderer.oplog.y = 0;
                                self.renderer.oplog.focused_op = .{};
                            }
                            try self.renderer.oplog.update(buf.buf);
                            try self._send_event(.op_update);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJOpLogFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .opshow => |req| {
                    switch (res.res) {
                        .ok => |op| {
                            self.renderer.opshow.get(req.hash, .touch).?.* = .{ .buf = op };
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJOpShowFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .bookmark => {
                    switch (res.res) {
                        .ok => |buf| {
                            try self.renderer.bookmarks.update(buf, self);
                            try self._send_event(.rerender);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJBookmarkFailed }, buf.buf),
                        else => unreachable,
                    }
                },
                .file_tree => |req| {
                    switch (res.res) {
                        .file_tree => |buf| {
                            _ = try self.renderer.file_tree.update_list(req, buf.status, buf.buf, buf.diffs);
                            try self._send_event(.file_show_scroll_update);
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJFileTreeFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .file_content => |req| {
                    switch (res.res) {
                        .ok => |buf| {
                            const key_lookup = components_mod.FileShowSlate.Key{
                                .to = req.to.hash,
                                .from = if (req.from) |f| f.hash else null,
                                .path = req.path,
                                .context = req.context,
                            };
                            const file = self.renderer.file_show.filecache.get(key_lookup, .touch);
                            if (file) |f| {
                                switch (req.mode) {
                                    .plain => {
                                        if (f.content) |old| self.alloc.free(old);
                                        f.content = buf.buf;
                                        f.len = @intCast(buf.height);
                                    },
                                    .diff => {
                                        if (f.diff) |old| self.alloc.free(old);
                                        f.diff = buf.buf;
                                        f.diff_len = @intCast(buf.height);
                                    },
                                }
                            } else {
                                self.alloc.free(buf.buf);
                            }
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJFileShowFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .git_fetch => |req| {
                    _ = req;
                    switch (res.res) {
                        .ok => |buf| {
                            self.alloc.free(buf.buf);
                            try self._toast_timed(.success, try self.alloc.dupe(u8, "Git fetch successful"), std.time.ms_per_s);

                            try self.jj_request(.{ .log = .{ .n = self.renderer.log.limit } });
                        },
                        .err => |buf| try self._toast(.{ .err = error.GitFetchFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .git_push => |req| {
                    _ = req;
                    switch (res.res) {
                        .ok => |buf| {
                            self.alloc.free(buf.buf);
                            try self._toast_timed(.success, try self.alloc.dupe(u8, "Git push successful"), std.time.ms_per_s);

                            try self.jj_request(.{ .log = .{ .n = self.renderer.log.limit } });
                        },
                        .err => |buf| try self._toast(.{ .err = error.GitPushFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .command => {
                    var cmd = res.req.command;
                    defer cmd.cmd.deinit();

                    switch (res.res) {
                        .command_result => |c_res| {
                            if (c_res.errored) {
                                try self._toast(.{ .err = error.CommandExecutionError }, c_res.err);
                                if (c_res.out.len > 0) {
                                    try self._toast(.none, c_res.out);
                                }
                            } else {
                                if (c_res.err.len > 0) {
                                    if (c_res.out.len > 0) {
                                        try self._toast(.warn, c_res.err);
                                    } else {
                                        try self._toast(.info, c_res.err);
                                    }
                                }
                                if (c_res.out.len > 0) {
                                    if (c_res.err.len > 0) {
                                        try self._toast(.none, c_res.out);
                                    } else {
                                        try self._toast(.success, c_res.out);
                                    }
                                } else if (cmd.toast_success) {
                                    try self._toast_timed(.success, try self.alloc.dupe(u8, "Command execution successful"), std.time.ms_per_s);
                                }

                                if (cmd.refresh_log) {
                                    if (cmd.reset_log_pos) {
                                        self.renderer.log.limit = self.renderer.log.calc_limit(.{ .y = 0 });
                                    }
                                    try self.jj_request(.{ .log = .{
                                        .n = self.renderer.log.limit,
                                        .reset_pos = cmd.reset_log_pos,
                                    } });
                                }
                                if (cmd.refresh_oplog) {
                                    try self.jj_request(.{ .oplog = .{ .reset_pos = cmd.reset_oplog_pos } });
                                }
                            }
                        },
                        else => unreachable,
                    }
                },
            },
        }
    }

    pub fn event_loop(self: *@This()) !void {
        try self._send_event(.rerender);

        if (comptime options.env == .debug) {
            // try self.renderer.screen.term.fancy_features_that_break_gdb(.disable, .{});
        }

        while (self._wait_recv_event()) |event| {
            defer _ = self.arena.reset(.retain_capacity);
            var hasher = std.hash.Wyhash.init(0);
            defer {
                hasher.update(&std.mem.toBytes(self.state));
                hasher.update(&std.mem.toBytes(self.renderer.show_help));
                hasher.update(&std.mem.toBytes(self.renderer.x_split));

                switch (self.state) {
                    .log, .evolog, .bookmark, .command, .rebase, .duplicate, .new, .squash, .abandon, .git, .log_range_diff => {
                        const log = switch (self.state) {
                            .evolog => &self.renderer.evolog,
                            else => &self.renderer.log,
                        };
                        hasher.update(&std.mem.toBytes(log.y));
                        hasher.update(&std.mem.toBytes(log.skip_y));
                        hasher.update(&std.mem.toBytes(self.renderer.diff.context));
                        if (self.renderer.diff.get(log.focused_change.hash, .peek)) |diff| {
                            hasher.update(&std.mem.toBytes(diff.y));
                        }
                        var it = log.selected_changes.iterator();
                        while (it.next()) |e| {
                            hasher.update(&e.key_ptr.id);
                        }
                    },
                    .oplog => {
                        hasher.update(&std.mem.toBytes(self.renderer.oplog.y));
                        hasher.update(&std.mem.toBytes(self.renderer.oplog.skip_y));
                        if (self.renderer.opshow.get(self.renderer.oplog.focused_op.hash, .peek)) |opshow| {
                            hasher.update(&std.mem.toBytes(opshow.y));
                        }
                    },
                    .file_tree => {
                        const _tree = self.renderer.file_tree.cache.get(self.get_change_range(), .peek);
                        if (_tree) |tree| {
                            hasher.update(&std.mem.toBytes(tree.y));
                            hasher.update(&std.mem.toBytes(tree.skip_y));
                            if (tree.focused_node) |node| {
                                hasher.update(node.path);
                                hasher.update(&std.mem.toBytes(node.collapsed));
                                const res = self.get_file_tree_show_context(self.file_tree_from, node.status);
                                const file = self.renderer.file_show.filecache.get(.{
                                    .path = node.path,
                                    .to = self.renderer.log.focused_change.hash,
                                    .from = res.from_hash,
                                    .context = res.context,
                                }, .peek);
                                if (file) |f| hasher.update(&std.mem.toBytes(f.y));
                            }
                        }
                    },
                }

                hasher.update(&std.mem.toBytes(self.renderer.text_input.text.items.len));
                hasher.update(&std.mem.toBytes(self.renderer.text_input.cursor));
                hasher.update(&std.mem.toBytes(self.renderer.bookmarks.y));
                hasher.update(&std.mem.toBytes(self.renderer.bookmarks.skip_y));
                // hasher.update(self.log.status); // too much text for hashing on every event

                const final_hash = hasher.final();
                if (final_hash != self.renderer.last_hash) {
                    self._send_event(.rerender) catch |e| utils_mod.dump_error(e);
                }
                self.renderer.last_hash = final_hash;
            }

            self._handle_event(event) catch |e| switch (e) {
                error.Quit => return,
                else => return e,
            };
        }
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

    pub fn _toast(self: *@This(), mode: components_mod.Toaster.Toast.Mode, msg: []const u8) !void {
        const id = try self.renderer.toaster.add(.{ .mode = mode, .msg = msg });
        try self.sleeper.delay_event(5000, .{ .pop_toast = id });
    }

    pub fn _toast_timed(self: *@This(), mode: components_mod.Toaster.Toast.Mode, msg: []const u8, ms: i128) !void {
        const id = try self.renderer.toaster.add(.{ .mode = mode, .msg = msg });
        try self.sleeper.delay_event(ms, .{ .pop_toast = id });
    }

    pub fn jj_request(self: *@This(), req: JujutsuServer.Request) !void {
        switch (req) {
            .log => self.renderer.log.request_count += 1,
            else => {},
        }
        try self.jj.requests.send(.{ .id = null, .req = req });
    }

    pub fn jj_toasted_request(self: *@This(), req: JujutsuServer.Request, msg: []const u8) !void {
        const id = try self.renderer.toaster.add(.{ .mode = .info, .msg = try self.alloc.dupe(u8, msg) });
        try self.jj.requests.send(.{ .id = id, .req = req });
    }
};
