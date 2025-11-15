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
};

pub const State = union(enum(u8)) {
    log,
    oplog,
    evolog,
    file_tree,
    bookmark: enum {
        view,
        create,
        search,
        view_goto,
        search_goto,
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

    pub inline fn short_display(self: @This()) []const u8 {
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
    diff_update: jj_mod.Change,
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
    scroll: struct { target: enum { log, diff, bookmarks }, dir: enum { up, down } },
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
    switch_state_to_evolog,
    switch_state_to_duplicate,
    switch_state_to_bookmarks_view,
    switch_state_to_file_tree,
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
    switch_state_to_bookmark_goto,
    apply_bookmark_goto,
    switch_state_to_git_fetch,
    switch_state_to_git_push,
    file_tree_collapse: struct { collapse: bool },
    apply_jj_git_push_selected: struct { allow_new: bool },
    start_search,
    end_search: struct { reset: bool },
};

pub const JujutsuServer = struct {
    alloc: std.mem.Allocator,
    quit: utils_mod.Fuse = .{},
    thread: std.Thread,
    requests: utils_mod.Channel(Request),

    // not owned
    events: utils_mod.Channel(Event),

    pub const Request = union(enum) {
        log,
        oplog,
        bookmark,
        diff: Change,
        opshow: Operation,
        evolog: Change,
        file_list: Change,
        file_show: struct {
            change: Change,
            path: []const u8,
        },
    };

    pub const OkWithStatus = struct {
        status: Formatted,
        buf: Formatted,
    };
    pub const Result = union(enum) {
        with_status: OkWithStatus,
        ok: Formatted,
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
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(res) } } });
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
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(res) } } });
                },
                .evolog => |change| {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "evolog",
                        "--template",
                        Change.Parsed.template,
                        "-r",
                        change.id[0..],
                        "--stat",
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(res) } } });
                },
                .diff => |change| {
                    // TODO: these diffs can get pretty large, maybe add some kinda paging support to this?
                    //  - something like: caller passes some line range info (start, end)
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
                    errdefer self.alloc.free(stat);
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
                    errdefer self.alloc.free(diff);

                    try self.events.send(.{ .jj = .{
                        .req = req,
                        .res = .{
                            .with_status = .{
                                .status = .from(stat),
                                .buf = .from(diff),
                            },
                        },
                    } });
                },
                .opshow => |op| {
                    const stat = self.jjcall(&[_][]const u8{
                        "jj",
                        "--color",
                        "always",
                        "op",
                        "show",
                        "--stat",
                        "--tool",
                        "delta",
                        op.hash[0..],
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };

                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(stat) } } });
                },
                .bookmark => {
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "list",
                        "-a",
                        "--template",
                        Bookmark.Parsed.template,
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(res) } } });
                },
                .file_list => |change| {
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
                    errdefer self.alloc.free(stat);
                    const res = self.jjcall(&[_][]const u8{
                        "jj",
                        "file",
                        "list",
                        "-r",
                        change.id[0..],
                        "--template",
                        FileTreeEntry.Parsed.template,
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    errdefer self.alloc.free(res);
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .with_status = .{ .status = .from(stat), .buf = .from(res) } } } });
                },
                .file_show => |payload| {
                    const cmd = try std.fmt.allocPrint(self.alloc, "jj file show -r {s} {s} | bat --color=always --style numbers,plain --file-name {s}", .{
                        payload.change.id[0..],
                        payload.path,
                        payload.path,
                    });
                    defer self.alloc.free(cmd);
                    const res = self.jjcall(&[_][]const u8{
                        "sh",
                        "-c",
                        cmd,
                    }) catch |e| {
                        utils_mod.dump_error(e);
                        continue;
                    };
                    try self.events.send(.{ .jj = .{ .req = req, .res = .{ .ok = .from(res) } } });
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

    quit_input_loop: utils_mod.Fuse = .{},

    renderer: components_mod.Renderer,
    input_thread: std.Thread,
    input_iterator: term_mod.TermInputIterator,
    events: utils_mod.Channel(Event),
    input_action_map: InputActionMap,

    sleeper: *Sleeper,
    jj: *JujutsuServer,

    state: State = .log,

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

        var renderer = try components_mod.Renderer.init(alloc, @This());
        errdefer renderer.deinit();

        var events = try utils_mod.Channel(Event).init(alloc);
        errdefer events.deinit();

        var input_action_map = try init_input_action_map(alloc);
        errdefer input_action_map.deinit();

        const sleeper = try Sleeper.init(alloc, events);
        errdefer sleeper.deinit();

        const jj = try JujutsuServer.init(alloc, events);
        errdefer jj.deinit();

        try jj.requests.send(.log);
        try jj.requests.send(.bookmark);

        self.* = .{
            .alloc = alloc,
            .arena = arena,
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
        defer self.input_action_map.deinit();
        defer self.renderer.deinit();
        defer self.input_iterator.input.deinit();
        defer {
            while (self.events.try_recv()) |e| switch (e) {
                .jj => |res| switch (res.res) {
                    .ok, .err => |buf| self.alloc.free(buf.buf),
                    .with_status => |r| {
                        self.alloc.free(r.status.buf);
                        self.alloc.free(r.buf.buf);
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
            .tv_usec = @as(c_long, @intCast(wait_ms)) * 1000,
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
                .evolog,
                .file_tree,
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
                .evolog,
                .file_tree,
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
                .file_tree,
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
        }
        {
            defer map.reset();
            try map.for_states(&[_]State{
                .log,
                .oplog,
                .evolog,
                .file_tree,
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
                    .{ .functional = .{ .key = .page_up, .action = .press } },
                    .{ .functional = .{ .key = .page_up, .action = .repeat } },
                },
                null,
                .{ .scroll = .{ .target = .diff, .dir = .up } },
            );
            try map.add_many(
                &[_]Key{
                    .{ .functional = .{ .key = .page_down, .action = .press } },
                    .{ .functional = .{ .key = .page_down, .action = .repeat } },
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
            .file_tree,
            .{ .key = .{ .key = 'h' } },
            null,
            .{ .file_tree_collapse = .{ .collapse = true } },
        );
        try map.add_one_for_state(
            .file_tree,
            .{ .key = .{ .key = 'l' } },
            null,
            .{ .file_tree_collapse = .{ .collapse = false } },
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
            },
            .oplog, .evolog, .log, .file_tree => .{},
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
                            try self.jj.requests.send(.{ .diff = change });
                        }
                    } else if (log.y + n < i) {
                        break;
                    }
                    i += 1;
                }

                if (self.renderer.diff.cache.get(log.focused_change.hash, .touch)) |_| {
                    try self._send_event(.rerender);
                } else {
                    // debounce diff requests
                    try self.sleeper.delay_event(20, .{ .diff_update = log.focused_change });
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
                            try self.jj.requests.send(.{ .opshow = op });
                        }
                    } else if (oplog.y + n < i) {
                        break;
                    }
                    i += 1;
                }

                if (self.renderer.opshow.cache.get(oplog.focused_op.hash, .touch)) |_| {
                    try self._send_event(.rerender);
                } else {
                    // debounce op show requests
                    try self.sleeper.delay_event(20, .{ .opshow_update = oplog.focused_op });
                }
            },
            .diff_update => |change| {
                const focused = switch (self.state) {
                    .evolog => self.renderer.evolog.focused_change,
                    else => self.renderer.log.focused_change,
                };
                if (std.mem.eql(u8, change.hash[0..], focused.hash[0..])) {
                    const diff = try self.renderer.diff.cache.getOrPut(change.hash);
                    if (!diff.found_existing) {
                        diff.val.* = .{};
                        try self.jj.requests.send(.{ .diff = change });
                    }
                }
            },
            .opshow_update => |op| {
                if (std.mem.eql(u8, op.hash[0..], self.renderer.oplog.focused_op.hash[0..])) {
                    const diff = try self.renderer.opshow.cache.getOrPut(op.hash);
                    if (!diff.found_existing) {
                        diff.val.* = .{};
                        try self.jj.requests.send(.{ .opshow = op });
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
                        .oplog => try self.jj.requests.send(.oplog),
                        .evolog => try self.jj.requests.send(.{ .evolog = self.renderer.log.focused_change }),
                        else => {},
                    }
                    try self.jj.requests.send(.log);
                },
                .scroll => |target| switch (target.target) {
                    .log => {
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
                            .file_tree => {
                                const tree = self.renderer.file_tree.cache.get(self.renderer.log.focused_change, .touch).?;
                                switch (target.dir) {
                                    .up => tree.y -= 1,
                                    .down => tree.y += 1,
                                }
                            },
                            else => {
                                switch (target.dir) {
                                    .up => self.renderer.log.y -= 1,
                                    .down => self.renderer.log.y += 1,
                                }
                                try self._send_event(.scroll_update);
                            },
                        }
                    },
                    .diff => {
                        switch (self.state) {
                            .oplog => {
                                if (self.renderer.opshow.cache.get(self.renderer.oplog.focused_op.hash, .touch)) |opshow| {
                                    switch (target.dir) {
                                        .up => opshow.y -= 10,
                                        .down => opshow.y += 10,
                                    }
                                }
                            },
                            .file_tree => {
                                if (self.renderer.file_tree.cache.get(self.renderer.log.focused_change, .touch).?.get_focused_file()) |focused_file| {
                                    const key_lookup = components_mod.FileShowSlate.Key{ .change_hash = self.renderer.log.focused_change.hash, .path = focused_file };
                                    if (self.renderer.file_show.filecache.get(key_lookup, .touch)) |cfile| {
                                        switch (target.dir) {
                                            .up => cfile.y -= 10,
                                            .down => cfile.y += 10,
                                        }
                                    }
                                }
                            },
                            .evolog => {
                                if (self.renderer.diff.cache.get(self.renderer.evolog.focused_change.hash, .touch)) |diff| {
                                    switch (target.dir) {
                                        .up => diff.y -= 10,
                                        .down => diff.y += 10,
                                    }
                                }
                            },
                            else => {
                                if (self.renderer.diff.cache.get(self.renderer.log.focused_change.hash, .touch)) |diff| {
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
                .switch_state_to_log => {
                    self.renderer.log.selected_changes.clearRetainingCapacity();
                    self.renderer.text_input.reset();
                    self.state = .log;
                    self.renderer.show_help = false;
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
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "edit",
                        self.renderer.log.focused_change.id[0..],
                    });
                    try self.jj.requests.send(.log);
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
                    self.renderer.oplog.y = 0;
                    self.renderer.oplog.focused_op = .{};
                    try self.jj.requests.send(.oplog);
                },
                .switch_state_to_duplicate => {
                    self.state = .{ .duplicate = .onto };
                    try self.renderer.log.selected_changes.put(self.renderer.log.focused_change, {});
                },
                .switch_state_to_bookmarks_view => {
                    self.state = .{ .bookmark = .view };
                    try self.jj.requests.send(.bookmark);
                },
                .switch_state_to_bookmark_goto => {
                    self.state = .{ .bookmark = .view_goto };
                },
                .switch_state_to_evolog => {
                    self.state = .evolog;
                    try self.jj.requests.send(.{ .evolog = self.renderer.log.focused_change });
                },
                .switch_state_to_file_tree => {
                    self.state = .file_tree;
                    if (self.renderer.file_tree.cache.get(self.renderer.log.focused_change, .touch) == null) {
                        try self.jj.requests.send(.{ .file_list = self.renderer.log.focused_change });
                    }
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
                .switch_state_to_command => {
                    self.state = .command;
                    self.renderer.text_input.reset();
                },
                .apply_jj_rebase => |v| {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("rebase");

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append("-r");
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.RebaseOnSelected }, try self.alloc.dupe(u8, "Cannot rebase on selected change"));
                            return;
                        }
                    }

                    switch (self.state.rebase) {
                        .onto => try args.append("-d"),
                        .after => try args.append("-A"),
                        .before => try args.append("-B"),
                    }

                    try args.append(self.renderer.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        try args.append("--ignore-immutable");
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_abandon => |v| {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("abandon");
                    try args.append("--retain-bookmarks");

                    var it = self.renderer.log.selected_changes.iterator();
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
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("squash");

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append("--from");
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.SquashOnSelected }, try self.alloc.dupe(u8, "Cannot squash on selected change"));
                            return;
                        }
                    }

                    try args.append("--into");
                    try args.append(self.renderer.log.focused_change.id[0..]);

                    if (v.ignore_immutable) {
                        try args.append("--ignore-immutable");
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                },
                .apply_jj_new => {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("new");

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append(e.key_ptr.id[0..]);
                    }

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
                    self.renderer.log.y = 0;
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
                        try self.execute_non_interactive_command(args.items);
                    }
                },
                .apply_jj_op_restore => {
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "op",
                        "restore",
                        self.renderer.oplog.focused_op.hash[0..],
                    });
                    self.renderer.oplog.y = 0;
                    try self.jj.requests.send(.oplog);
                    try self.jj.requests.send(.log);
                },
                .apply_jj_duplicate => {
                    defer {
                        self.renderer.log.selected_changes.clearRetainingCapacity();
                        self.state = .log;
                    }

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("duplicate");

                    var it = self.renderer.log.selected_changes.iterator();
                    while (it.next()) |e| {
                        try args.append(e.key_ptr.id[0..]);

                        if (std.meta.eql(e.key_ptr.*, self.renderer.log.focused_change)) {
                            try self._toast(.{ .err = error.DuplicateOnSelected }, try self.alloc.dupe(u8, "Cannot duplicate on selected change"));
                            return;
                        }
                    }

                    switch (self.state.duplicate) {
                        .onto => try args.append("-d"),
                        .after => try args.append("-A"),
                        .before => try args.append("-B"),
                    }

                    try args.append(self.renderer.log.focused_change.id[0..]);

                    try self.execute_non_interactive_command(args.items);

                    try self.jj.requests.send(.log);
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

                    try self.renderer.log.focus_commit(bookmark.parsed.target[0]);
                },
                .new_commit_from_bookmark => {
                    defer {
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }

                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

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
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

                    var args = std.ArrayList([]const u8).init(temp);
                    try args.append("jj");
                    try args.append("bookmark");
                    try args.append("move");
                    try args.append(bookmark.parsed.name);
                    try args.append("--to");
                    try args.append(self.renderer.log.focused_change.id[0..]);
                    if (v.allow_backwards) {
                        try args.append("--allow-backwards");
                    }

                    try self.execute_non_interactive_command(args.items);
                    try self.jj.requests.send(.log);
                },
                .apply_jj_bookmark_delete => {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;
                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "delete",
                        bookmark.parsed.name,
                    });
                },
                .apply_jj_bookmark_forget => |v| {
                    defer self.state = .log;
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

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
                        self.renderer.text_input.reset();
                        self.state = .log;
                    }

                    try self.execute_non_interactive_command(&[_][]const u8{
                        "jj",
                        "bookmark",
                        "create",
                        "-r",
                        self.renderer.log.focused_change.id[0..],
                        self.renderer.text_input.text.items,
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
                        const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;
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
                    const bookmark = self.renderer.bookmarks.selected_bookmark orelse return;

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
                .file_tree_collapse => |v| {
                    const list = self.renderer.file_tree.cache.get(self.renderer.log.focused_change, .touch).?;
                    const node = list.focused_node orelse return;
                    switch (node.typ) {
                        .file => {
                            if (v.collapse) {
                                const parent = try list.focus_parent();
                                if (parent == null) {
                                    try self._handle_event(.{ .action = .switch_state_to_log });
                                    return;
                                }
                            }
                        },
                        .dir => {
                            if (node.collapsed and v.collapse) {
                                try self._handle_event(.{ .action = .switch_state_to_log });
                                return;
                            }
                            node.collapsed = v.collapse;
                        },
                    }
                },
            },
            .jj => |res| switch (res.req) {
                .log => {
                    switch (res.res) {
                        .ok => |log| {
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
                            self.renderer.diff.cache.get(req.hash, .touch).?.* = .{ .buf = diff.buf, .status = diff.status };
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJDiffFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .oplog => {
                    switch (res.res) {
                        .ok => |buf| {
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
                            self.renderer.opshow.cache.get(req.hash, .touch).?.* = .{ .buf = op };
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
                .file_list => |req| {
                    switch (res.res) {
                        .with_status => |buf| {
                            const list = try self.renderer.file_tree.add_list(req, buf.status, buf.buf);
                            const focused_file = list.get_focused_file() orelse return;

                            const path = try self.alloc.dupe(u8, focused_file);
                            try self.renderer.file_show.filecache.put(.{ .change_hash = req.hash, .path = path }, .{});
                            try self.jj.requests.send(.{ .file_show = .{
                                .change = req,
                                .path = path,
                            } });
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJFileListFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
                },
                .file_show => |req| {
                    switch (res.res) {
                        .ok => |buf| {
                            const key = components_mod.FileShowSlate.Key{ .change_hash = req.change.hash, .path = req.path };
                            const entry = self.renderer.file_show.filecache.get(key, .touch).?;
                            entry.* = .{ .content = buf.buf, .len = @intCast(buf.height) };
                        },
                        .err => |buf| try self._toast(.{ .err = error.JJFileShowFailed }, buf.buf),
                        else => unreachable,
                    }
                    try self._send_event(.rerender);
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
                    .log, .evolog, .bookmark, .command, .rebase, .duplicate, .new, .squash, .abandon, .git => {
                        const log = switch (self.state) {
                            .evolog => &self.renderer.evolog,
                            else => &self.renderer.log,
                        };
                        hasher.update(&std.mem.toBytes(log.y));
                        if (self.renderer.diff.cache.get(log.focused_change.hash, .peek)) |diff| {
                            hasher.update(&std.mem.toBytes(diff.y));
                        }
                        var it = log.selected_changes.iterator();
                        while (it.next()) |e| {
                            hasher.update(&e.key_ptr.id);
                        }
                    },
                    .oplog => {
                        hasher.update(&std.mem.toBytes(self.renderer.oplog.y));
                        if (self.renderer.opshow.cache.get(self.renderer.oplog.focused_op.hash, .peek)) |opshow| {
                            hasher.update(&std.mem.toBytes(opshow.y));
                        }
                    },
                    .file_tree => {
                        const _tree = self.renderer.file_tree.cache.get(self.renderer.log.focused_change, .peek);
                        if (_tree) |tree| {
                            hasher.update(&std.mem.toBytes(tree.y));
                            if (tree.focused_node) |node| {
                                hasher.update(node.path);
                                hasher.update(&std.mem.toBytes(node.collapsed));
                                const file = self.renderer.file_show.filecache.get(.{
                                    .path = node.path,
                                    .change_hash = self.renderer.log.focused_change.hash,
                                }, .peek);
                                if (file) |f| hasher.update(&std.mem.toBytes(f.y));
                            }
                        }
                    },
                }

                hasher.update(&std.mem.toBytes(self.renderer.text_input.text.items.len));
                hasher.update(&std.mem.toBytes(self.renderer.text_input.cursor));
                hasher.update(&std.mem.toBytes(self.renderer.bookmarks.y));
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

    pub fn _toast(self: *@This(), mode: components_mod.Toaster.Toast.Mode, msg: []const u8) !void {
        const id = try self.renderer.toaster.add(.{ .mode = mode, .msg = msg });
        try self.sleeper.delay_event(5000, .{ .pop_toast = id });
    }
};
