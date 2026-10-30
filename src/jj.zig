const std = @import("std");

const utils_mod = @import("utils.zig");

const term_mod = @import("term.zig");

const main_mod = @import("main.zig");
const Event = main_mod.Event;

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

    pub const Attributes = struct {
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
        workspace_name: ?[]const u8,
        attributes: Attributes,
    };

    pub const BookmarkTargetSide = enum { normal, added, removed };

    pub const BookmarkTarget = struct {
        commit_id: []const u8,
        description: []const u8 = "",
        side: BookmarkTargetSide,
    };

    pub const Bookmark = struct {
        name: []const u8,
        remote: ?[]const u8 = null,
        conflict: bool = false,
        present: bool = true,
        targets: []const BookmarkTarget = &.{},
    };

    // - [Templating language - Jujutsu docs](https://jj-vcs.github.io/jj/latest/templates/#treeentry-type)
    pub const FileTreeEntry = struct {
        path: []const u8,
        conflict: bool,
        file_type: enum {
            file,
            symlink,
            tree,
            conflict,
            @"git-submodule",
            none,

            pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                _ = allocator;
                _ = options;
                const token = try source.next();
                return switch (token) {
                    .string, .allocated_string => |s| if (s.len == 0) .none else std.meta.stringToEnum(@This(), s) orelse error.InvalidEnumTag,
                    else => error.UnexpectedToken,
                };
            }
        },
    };
    pub const FileTreeDiffEntry = struct {
        pub const Status = enum {
            modified,
            added,
            removed,
            copied,
            renamed,
        };
        path: []const u8,
        status: Status,
        source: Schema.FileTreeEntry,
        target: Schema.FileTreeEntry,
    };
};

pub const Formatted = struct {
    height: u32 = 0,
    buf: []u8 = &.{},

    pub fn from(buf: []u8) @This() {
        var it = utils_mod.LineIterator.init(buf);
        var i: u32 = 0;
        while (it.next()) |line| {
            _ = line;
            i += 1;
        }
        return .{
            .height = i,
            .buf = buf,
        };
    }
};

const template_sep = struct {
    // OOF: too much noise in oplog
    // const seed = "JJAZY";
    // const sep = "-" ++ std.fmt.comptimePrint("{d}", .{hash(seed)}) ++ "-";
    // const escaped = escape(sep);

    const sep = "-JJaZY-";
    const escaped = sep[0..3] ++ escape(sep[3..4]) ++ sep[4..];

    fn escape(comptime str: []const u8) [str.len * 4]u8 {
        comptime {
            var buf = std.mem.zeroes([str.len * 4]u8);
            for (str, 0..) |c, i| {
                _ = std.fmt.bufPrint(buf[i * 4 ..], "\\x{x}", .{c}) catch unreachable;
            }
            return buf;
        }
    }

    fn hash(str: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(str);
        return hasher.final();
    }
};

fn Template(typ: type, _template: []const u8, _sep: []const u8) type {
    return struct {
        parsed: typ,
        formatted: Formatted,
        json: []const u8,
        raw: []const u8,

        const Self = @This();
        pub const sep = _sep;
        pub const template = _template;

        pub const Iterator = struct {
            state: utils_mod.LineIterator,

            alloc: std.mem.Allocator,
            temp: std.heap.ArenaAllocator,
            scratch: std.ArrayList(u8),

            pub fn init(alloc: std.mem.Allocator, buf: []const u8) @This() {
                return .{
                    .alloc = alloc,
                    .temp = .init(alloc),
                    .state = .init(buf),
                    .scratch = .init(alloc),
                };
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

pub const Bookmark = struct {
    pub const Parsed = Template(
        Schema.Bookmark,
        \\concat(
        \\  "{\"name\":", json(name),
        \\  ",\"remote\":", json(remote),
        \\  ",\"conflict\":", if(conflict, "true", "false"),
        \\  ",\"present\":", if(present, "true", "false"),
        \\  ",\"targets\":[",
        \\  if(conflict,
        \\    separate(",",
        \\      self.removed_targets().map(|c| concat(
        \\        "{\"commit_id\":", json(c.commit_id()),
        \\        ",\"description\":", json(c.description().first_line()),
        \\        ",\"side\":\"removed\"}"
        \\      )).join(","),
        \\      self.added_targets().map(|c| concat(
        \\        "{\"commit_id\":", json(c.commit_id()),
        \\        ",\"description\":", json(c.description().first_line()),
        \\        ",\"side\":\"added\"}"
        \\      )).join(",")
        \\    ),
        \\    if(normal_target,
        \\      concat(
        \\        "{\"commit_id\":", json(normal_target.commit_id()),
        \\        ",\"description\":", json(normal_target.description().first_line()),
        \\        ",\"side\":\"normal\"}"
        \\      ),
        \\      ""
        \\    )
        \\  ),
        \\  "]}"
        \\) ++ "
    ++ template_sep.escaped ++
        "\n\"",
        template_sep.sep,
    );
};

pub const Change = struct {
    id: Hash = [1]u8{'z'} ** 8,
    hash: Hash = [1]u8{'0'} ** 8,

    pub const Hash = [8]u8;

    pub const Parsed = Template(
        Schema.Change,
        "json(self) ++ \"" ++ template_sep.escaped ++ "\" ++ builtin_log_compact",
        template_sep.sep,
    );

    pub const evlog_template = "json(commit) ++ \"" ++ template_sep.escaped ++ "\" ++ builtin_log_compact(commit) ++ builtin_op_log_compact(operation)";

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
    hash: Hash = [1]u8{'0'} ** 12,

    pub const Hash = [12]u8;

    pub const Parsed = Template(
        Schema.Operation,
        "json(self) ++ \"" ++ template_sep.escaped ++ "\" ++ builtin_op_log_compact",
        template_sep.sep,
    );

    pub fn from_parsed(parsed: *const Parsed) @This() {
        var self: @This() = .{};
        @memcpy(self.hash[0..], parsed.parsed.id[0..self.hash.len]);
        return self;
    }

    pub fn is_root(self: *@This()) bool {
        return std.mem.allEqual(u8, self.hash, '0');
    }
};

pub const FileTreeEntry = struct {
    path: []const u8 = &.{},
    conflict: bool = false,

    pub const Parsed = Template(
        Schema.FileTreeEntry,
        \\"{ \"path\": \"" ++ self.path() ++ "\", \"conflict\": " ++ self.conflict() ++ ", \"file_type\": \"" ++ self.file_type() ++ "\" }"
    ++ "++ \"" ++ template_sep.escaped ++ "\" ++ \"\n\"",
        template_sep.sep,
    );

    pub fn from_parsed(parsed: *const Parsed) void {
        return .{ .path = parsed.parsed.path, .conflict = parsed.parsed.conflict };
    }
};

pub const FileTreeDiffEntry = struct {
    path: []const u8,
    status: Schema.FileTreeDiffEntry.Status,
    source: Schema.FileTreeEntry,
    target: Schema.FileTreeEntry,

    pub const Parsed = Template(
        Schema.FileTreeDiffEntry,
        \\concat("{",
        \\  "\"path\": \"", path, "\", ",
        \\  "\"status\": \"", status, "\", ",
        \\  "\"source\": {",
        \\      "\"path\": \"", self.source().path(), "\", ",
        \\      "\"conflict\": ", self.source().conflict(), ", ",
        \\      "\"file_type\": \"", self.source().file_type(), "\"",
        \\  "}, ",
        \\  "\"target\": {",
        \\      "\"path\": \"", self.target().path(), "\", ",
        \\      "\"conflict\": ", self.target().conflict(), ", ",
        \\      "\"file_type\": \"", self.target().file_type(), "\"",
        \\  "}",
        \\"}")
    ++ "++" ++ "\"" ++ template_sep.escaped ++ "\"" ++ "++" ++ "\"\\n\"",
        template_sep.sep,
    );
};
