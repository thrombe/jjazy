const std = @import("std");
const utils = @import("utils.zig");

const CaseSensitivity = enum {
    sensitive,
    insensitive,
};

pub const SearchCollector = struct {
    matched: std.ArrayListUnmanaged(Match) = .empty,
    strings: std.ArrayListUnmanaged([]const u8) = .empty,
    alloc: std.mem.Allocator,

    const Match = struct { index: u32, score: i32 };

    pub fn init(alloc: std.mem.Allocator) @This() {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *@This()) void {
        self.matched.deinit(self.alloc);
        self.strings.deinit(self.alloc);
    }

    pub fn reorder_strings(self: *@This(), strings: []const []const u8, query: []const u8, searcher: anytype, case: CaseSensitivity) ![]const []const u8 {
        self.matched.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        try self.matched.ensureTotalCapacity(self.alloc, strings.len);
        try self.strings.ensureTotalCapacity(self.alloc, strings.len);

        for (strings, 0..) |string, i| {
            const score = try searcher.get_score(string, query, case) orelse continue;
            try self.matched.append(self.alloc, .{ .index = @intCast(i), .score = score });
        }

        const Ctx = struct {};
        std.sort.block(Match, self.matched.items, Ctx{}, struct {
            fn lessThan(_: Ctx, lhs: Match, rhs: Match) bool {
                return lhs.score > rhs.score;
            }
        }.lessThan);

        for (self.matched.items) |match| {
            try self.strings.append(self.alloc, strings[match.index]);
        }

        return self.strings.items;
    }
};

pub const SublimeSearcher = struct {
    occ: [256]std.ArrayListUnmanaged(Occurrence),
    match_cache: MatchCache,
    alloc: std.mem.Allocator,
    config: Config = .{},

    const Config = struct {
        bonus: struct {
            consecutive: i32 = 8,
            word_start: i32 = 72,
            match_case: i32 = 8,
            penalty_distance: i32 = 4,
        } = .{},
    };
    const MatchCache = std.AutoHashMapUnmanaged(MatchKey, ?Match);
    const MatchKey = struct {
        query_index: u32,
        target_index: u32,
        consecutive: i32,
    };

    const Occurrence = struct {
        index: u32,
        char: u8,
        is_start: bool,
    };

    const Match = struct {
        /// Accumulative score
        score: i32,
        /// Count of current consecutive matched chars
        consecutive: i32,

        first_match_index: u32,
        last_match_index: u32,
    };

    pub fn init(alloc: std.mem.Allocator, config: Config) @This() {
        var occ: [256]std.ArrayListUnmanaged(Occurrence) = undefined;
        @memset(&occ, .empty);
        return .{
            .alloc = alloc,
            .occ = occ,
            .match_cache = .{},
            .config = config,
        };
    }

    fn reset(self: *@This()) void {
        self.match_cache.clearRetainingCapacity();
        for (&self.occ) |*occ| {
            occ.clearRetainingCapacity();
        }
    }

    pub fn deinit(self: *@This()) void {
        self.match_cache.deinit(self.alloc);
        for (&self.occ) |*occ| {
            occ.deinit(self.alloc);
        }
    }

    fn capture_occurrences(self: *@This(), string: []const u8, query: []const u8, case: CaseSensitivity) !void {
        var chars = std.bit_set.ArrayBitSet(usize, 256).initEmpty();
        for (query) |c| {
            const case_c = switch (case) {
                .sensitive => c,
                .insensitive => std.ascii.toLower(c),
            };
            chars.set(@intCast(case_c));
        }

        var prev: struct {
            is_sep: bool,
            is_upper: bool,
            is_start: bool,
        } = .{
            .is_sep = true,
            .is_upper = false,
            .is_start = false,
        };
        for (string, 0..) |original, i| {
            const is_sep = !std.ascii.isAlphanumeric(original);
            const is_upper = std.ascii.isUpper(original);
            const key = switch (case) {
                .insensitive => std.ascii.toLower(original),
                .sensitive => original,
            };

            if (is_sep) {
                if (chars.isSet(@intCast(key))) {
                    const occ = &self.occ[@intCast(key)];
                    try occ.ensureTotalCapacity(self.alloc, 32);
                    try occ.append(self.alloc, .{ .index = @intCast(i), .char = original, .is_start = false });
                }

                prev.is_upper = false;
                prev.is_sep = true;
                prev.is_start = false;
            } else {
                var is_start = false;
                if (prev.is_sep) {
                    is_start = true;
                } else {
                    if (!prev.is_start and (prev.is_upper != is_upper)) {
                        is_start = true;
                    }
                }

                if (chars.isSet(@intCast(key))) {
                    const occ = &self.occ[@intCast(key)];
                    try occ.ensureTotalCapacity(self.alloc, 32);
                    try occ.append(self.alloc, .{ .index = @intCast(i), .char = original, .is_start = is_start });
                }

                prev.is_upper = is_upper;
                prev.is_sep = is_sep;
                prev.is_start = is_start;
            }
        }
    }

    fn match(self: *@This(), query: []const u8, index: usize, occurrence: Occurrence, consecutive: i32, case: CaseSensitivity) !?Match {
        const match_key = MatchKey{
            .query_index = @intCast(index),
            .target_index = occurrence.index,
            .consecutive = consecutive,
        };

        // already scored sub-tree
        if (self.match_cache.getPtr(match_key)) |matched| return matched.*;

        const case_bonus = switch (case) {
            .sensitive => false,
            .insensitive => (if (index < query.len) query[index] == occurrence.char else false),
        };
        const score = consecutive * self.config.bonus.consecutive +
            @intFromBool(occurrence.is_start) * self.config.bonus.word_start +
            @intFromBool(case_bonus) * self.config.bonus.match_case;

        if (index + 1 >= query.len) {
            const matched = Match{
                .score = score,
                .consecutive = consecutive,
                .first_match_index = occurrence.index,
                .last_match_index = occurrence.index,
            };
            try self.match_cache.putNoClobber(self.alloc, match_key, matched);
            return matched;
        }

        const next_char = query[index + 1];
        const occs = self.occ[
            switch (case) {
                .sensitive => next_char,
                .insensitive => std.ascii.toLower(next_char),
            }
        ].items;

        // reached end of target without matching all query chars
        if (occs.len == 0) {
            try self.match_cache.putNoClobber(self.alloc, match_key, null);
            return null;
        }

        var max_match: ?Match = null;
        for (occs) |occ| {
            if (occ.index <= occurrence.index) continue;
            const m = try self.match(
                query,
                index + 1,
                occ,
                if (occ.index - occurrence.index == 1) consecutive + 1 else 0,
                case,
            );
            if (m == null) continue;
            if (max_match) |mm| {
                if (mm.score < m.?.score) {
                    max_match = m;
                }
            } else {
                max_match = m;
            }
        }

        if (max_match == null) {
            try self.match_cache.putNoClobber(self.alloc, match_key, null);
            return null;
        }

        var matched = Match{
            .score = score,
            .consecutive = consecutive,
            .first_match_index = occurrence.index,
            .last_match_index = occurrence.index,
        };

        matched.score += max_match.?.score;
        matched.consecutive += max_match.?.consecutive;
        const distance: i32 = @intCast(max_match.?.first_match_index - matched.last_match_index);
        switch (distance) {
            0 => {},
            1 => {
                matched.consecutive += 1;
                matched.score += matched.consecutive * self.config.bonus.consecutive;
            },
            else => {
                matched.consecutive = 0;
                const penalty = (distance - 1) * self.config.bonus.penalty_distance;
                matched.score -= penalty;
            },
        }
        // TODO: to show the matched characters in UI, we need to store what we matched.
        // matched.matches.extend(max_match.?.matches);
        matched.last_match_index = max_match.?.last_match_index;

        try self.match_cache.putNoClobber(self.alloc, match_key, matched);
        return matched;
    }

    pub fn best_match(self: *@This(), string: []const u8, query: []const u8, case: CaseSensitivity) !?Match {
        if (query.len == 0) return null;
        self.reset();
        try self.match_cache.ensureTotalCapacity(self.alloc, @intCast(query.len * query.len));

        try self.capture_occurrences(string, query, case);

        // NOTE: this is a loop because we don't know which is the first key that even matched. so searching for the first self.occ[key].len > 0
        for (query, 0..) |qc, i| {
            const key = switch (case) {
                .sensitive => qc,
                .insensitive => std.ascii.toLower(qc),
            };
            const occs = self.occ[@intCast(key)].items;

            // TODO: decide if this should really be a break or continue.
            // 'break' if every character of query must be in the string. else the code needs more changes anyway.
            // if (occs.len == 0) continue;
            if (occs.len == 0) break;

            var max_match: ?Match = null;
            for (occs) |occ| {
                const m = try self.match(query, i, occ, 0, case);
                if (m == null) continue;
                if (max_match) |mm| {
                    if (mm.score < m.?.score) {
                        max_match = m;
                    }
                } else {
                    max_match = m;
                }
            }

            return max_match;
        }

        return null;
    }

    pub fn get_score(self: *@This(), string: []const u8, query: []const u8, case: CaseSensitivity) !?i32 {
        const maybe_matched = try self.best_match(string, query, case);
        const matched = maybe_matched orelse return null;
        return matched.score;
    }
};

test "basic exact match" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const target = "abc";

    const m = try searcher.best_match(target, query, .insensitive);
    try std.testing.expect(m != null);
    try std.testing.expect(m.?.score > 0);
    try std.testing.expectEqual(@as(u32, 0), m.?.first_match_index);
    try std.testing.expectEqual(@as(u32, 2), m.?.last_match_index);
}

test "characters appear out of order should not match" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const target = "cba";
    const m = try searcher.best_match(target, query, .insensitive);
    try std.testing.expect(m == null);
}

test "case sensitivity - match only with correct case" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "A";
    const target = "ab";

    const m_sensitive = try searcher.best_match(target, query, .sensitive);
    const m_insensitive = try searcher.best_match(target, query, .insensitive);

    try std.testing.expect(m_sensitive == null);
    try std.testing.expect(m_insensitive != null);
}

test "bonus for word start vs middle" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const q = "c";
    const t1 = "Controller"; // 'C' at start = word start
    const t2 = "mycontroller"; // 'c' not at word start

    const m1 = try searcher.best_match(t1, q, .insensitive);
    const m2 = try searcher.best_match(t2, q, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score > m2.?.score);
}

test "bonus for consecutive characters" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "ab";
    const t1 = "ab"; // consecutive
    const t2 = "a_b"; // non-consecutive

    searcher.config.bonus.word_start = 0;
    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score > m2.?.score);
}

test "penalty for large gaps between chars" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const t1 = "abc";
    const t2 = "a----b----c";

    searcher.config.bonus.word_start = 0;
    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score > m2.?.score);
}

test "longer string with embedded query" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "cat";
    const target = "concatenate";
    const m = try searcher.best_match(target, query, .insensitive);

    try std.testing.expect(m != null);
    try std.testing.expect(m.?.score > 0);
}

test "non-alphanumeric separators are treated as word starts" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "b";
    const target1 = "foo-bar"; // 'b' after '-' = word start
    const target2 = "foobar"; // 'b' not a word start

    const m1 = try searcher.best_match(target1, query, .insensitive);
    const m2 = try searcher.best_match(target2, query, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score != m2.?.score);
}

test "handles empty query" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const target = "anything";
    const m = try searcher.best_match(target, "", .insensitive);
    try std.testing.expect(m == null);
}

test "handles query longer than target" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "longquery";
    const target = "short";
    const m = try searcher.best_match(target, query, .insensitive);
    try std.testing.expect(m == null);
}

test "prefer tighter matches (fewer gaps)" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const t1 = "a-b-c";
    const t2 = "a---b---c";

    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    try std.testing.expect(m1.?.score > m2.?.score);
}

test "camelCase word start bonus" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "cn";
    const t1 = "CamelName"; // matches at capitals
    const t2 = "camelname"; // no camelCase bonus

    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score > m2.?.score);
}

test "case match" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "sC";
    const t1 = "simpleController";
    const t2 = "sire-cool";

    searcher.config.bonus.word_start = 0;
    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    try std.testing.expect(m1 != null and m2 != null);
    try std.testing.expect(m1.?.score > m2.?.score);
}

test "many repeats in string" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const target = "aaaabbbccc";
    const m = try searcher.best_match(target, query, .insensitive);

    try std.testing.expect(m != null);
    try std.testing.expect(m.?.score > 0);
}

test "non alpha-numeric matches" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "-";
    const target = "huh-man";
    const m = try searcher.best_match(target, query, .insensitive);

    try std.testing.expect(m != null);
    try std.testing.expect(m.?.score > 0);
}

test "first char does not match" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "tman";
    const t1 = "ab manig";
    const t2 = "abigman";

    const m1 = try searcher.best_match(t1, query, .insensitive);
    const m2 = try searcher.best_match(t2, query, .insensitive);

    // try std.testing.expect(m1 != null and m2 != null);
    // try std.testing.expect(m1.?.score > m2.?.score);

    try std.testing.expect(m1 == null and m2 == null);
}
