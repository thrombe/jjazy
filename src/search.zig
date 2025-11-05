const std = @import("std");
const utils = @import("utils.zig");

const CaseSensitivity = enum {
    sensitive,
    insensitive,
};

pub const SearchCollector = struct {
    matched: std.ArrayListUnmanaged(Match) = .empty,
    alloc: std.mem.Allocator,
    matches_arena: std.heap.ArenaAllocator,

    pub const Match = struct { index: u32, score: i32, matches: []const u32, string: []const u8 };

    pub fn init(alloc: std.mem.Allocator) @This() {
        return .{ .alloc = alloc, .matches_arena = .init(alloc) };
    }

    pub fn deinit(self: *@This()) void {
        self.matches_arena.deinit();
        self.matched.deinit(self.alloc);
    }

    pub fn reorder_strings(self: *@This(), strings: []const []const u8, query: []const u8, searcher: anytype, case: CaseSensitivity) ![]const Match {
        _ = self.matches_arena.reset(.retain_capacity);
        self.matched.clearRetainingCapacity();
        try self.matched.ensureTotalCapacity(self.alloc, strings.len);

        for (strings, 0..) |string, i| {
            const m = try searcher.best_match(string, query, case) orelse {
                if (query.len == 0) {
                    try self.matched.append(self.alloc, .{
                        .index = @intCast(i),
                        .score = 0,
                        .matches = &.{},
                        .string = string,
                    });
                }
                continue;
            };
            const temp = self.matches_arena.allocator();
            try self.matched.append(self.alloc, .{
                .index = @intCast(i),
                .score = m.score,
                .matches = try temp.dupe(u32, m.matches),
                .string = string,
            });
        }

        const Ctx = struct {};
        std.sort.block(Match, self.matched.items, Ctx{}, struct {
            fn lessThan(_: Ctx, lhs: Match, rhs: Match) bool {
                return lhs.score > rhs.score;
            }
        }.lessThan);

        return self.matched.items;
    }
};

pub const SublimeSearcher = struct {
    occ: [256]std.ArrayListUnmanaged(Occurrence),
    match_cache: MatchCache,
    matches: std.ArrayListUnmanaged(u32),
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
    const MatchCache = std.AutoHashMapUnmanaged(MatchKey, ?InnerMatch);
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
        score: i32,
        consecutive: i32,
        matches: []u32,
    };

    const InnerMatch = struct {
        /// Accumulative score
        score: i32,
        /// Count of current consecutive matched chars
        consecutive: i32,

        first_match_index: u32,
        last_match_index: u32,

        next_key: ?MatchKey,
    };

    pub fn init(alloc: std.mem.Allocator, config: Config) @This() {
        var occ: [256]std.ArrayListUnmanaged(Occurrence) = undefined;
        @memset(&occ, .empty);
        return .{
            .alloc = alloc,
            .occ = occ,
            .match_cache = .{},
            .matches = .empty,
            .config = config,
        };
    }

    fn reset(self: *@This()) void {
        self.matches.clearRetainingCapacity();
        self.match_cache.clearRetainingCapacity();
        for (&self.occ) |*occ| {
            occ.clearRetainingCapacity();
        }
    }

    pub fn deinit(self: *@This()) void {
        self.matches.deinit(self.alloc);
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

    fn match(self: *@This(), query: []const u8, index: usize, occurrence: Occurrence, consecutive: i32, case: CaseSensitivity) !?InnerMatch {
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
            const matched = InnerMatch{
                .score = score,
                .consecutive = consecutive,
                .first_match_index = occurrence.index,
                .last_match_index = occurrence.index,
                .next_key = null,
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

        var next_match_key: MatchKey = undefined;
        var max_match: ?InnerMatch = null;
        for (occs) |occ| {
            if (occ.index <= occurrence.index) continue;
            const _match_key = MatchKey{
                .query_index = @intCast(index + 1),
                .consecutive = if (occ.index - occurrence.index == 1) consecutive + 1 else 0,
                .target_index = occ.index,
            };
            const m = try self.match(
                query,
                _match_key.query_index,
                occ,
                _match_key.consecutive,
                case,
            );
            if (m == null) continue;
            if (max_match) |mm| {
                if (mm.score < m.?.score) {
                    max_match = m;
                    next_match_key = _match_key;
                }
            } else {
                max_match = m;
                next_match_key = _match_key;
            }
        }

        if (max_match == null) {
            try self.match_cache.putNoClobber(self.alloc, match_key, null);
            return null;
        }

        var matched = InnerMatch{
            .score = score,
            .consecutive = consecutive,
            .first_match_index = occurrence.index,
            .last_match_index = occurrence.index,
            .next_key = next_match_key,
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

            var max_match: ?InnerMatch = null;
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

            if (max_match == null) return null;

            self.matches.clearRetainingCapacity();
            try self.matches.append(self.alloc, max_match.?.first_match_index);
            var k = max_match.?.next_key;
            while (k) |match_key| {
                const m = self.match_cache.getPtr(match_key).?;
                if (m.* == null) break;
                k = m.*.?.next_key;
                try self.matches.append(self.alloc, m.*.?.first_match_index);
            }

            const real_match = Match{
                .score = max_match.?.score,
                .consecutive = max_match.?.consecutive,
                .matches = self.matches.items,
            };
            return real_match;
        }

        return null;
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
    try std.testing.expectEqual(@as(u32, 0), m.?.matches[0]);
    try std.testing.expectEqual(@as(u32, 2), m.?.matches[2]);
}

test "match indices" {
    var searcher = SublimeSearcher.init(std.testing.allocator, .{});
    defer searcher.deinit();

    const query = "abc";
    const target = " a b c";

    const m = try searcher.best_match(target, query, .insensitive);
    try std.testing.expect(m != null);
    try std.testing.expect(m.?.score > 0);
    try std.testing.expectEqual(@as(u32, 1), m.?.matches[0]);
    try std.testing.expectEqual(@as(u32, 3), m.?.matches[1]);
    try std.testing.expectEqual(@as(u32, 5), m.?.matches[2]);
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

test "SearchCollector: basic ordering by fuzzy match score" {
    const alloc = std.testing.allocator;

    var searcher = SublimeSearcher.init(alloc, .{});
    defer searcher.deinit();

    var collector = SearchCollector.init(alloc);
    defer collector.deinit();

    const strings = [_][]const u8{
        "controller",
        "cat",
        "concatenate",
        "dog",
    };

    const query = "cat";

    const results = try collector.reorder_strings(&strings, query, &searcher, .insensitive);

    // "cat" and "concatenate" should rank highest (exact and prefix match)
    try std.testing.expectEqualStrings("cat", results[0].string);
    try std.testing.expectEqualStrings("concatenate", results[1].string);

    // TODO: do we expect 2?
    // try std.testing.expectEqual(@as(usize, 3), results.len);
}

test "SearchCollector: ignores non-matching strings" {
    const alloc = std.testing.allocator;

    var searcher = SublimeSearcher.init(alloc, .{});
    defer searcher.deinit();

    var collector = SearchCollector.init(alloc);
    defer collector.deinit();

    const strings = [_][]const u8{
        "abc",
        "xyz",
        "def",
    };

    const query = "a";

    const results = try collector.reorder_strings(&strings, query, &searcher, .insensitive);

    // Only "abc" should match, because it contains 'a'
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("abc", results[0].string);
}

test "SearchCollector: orders by score descending" {
    const alloc = std.testing.allocator;

    var searcher = SublimeSearcher.init(alloc, .{});
    defer searcher.deinit();

    var collector = SearchCollector.init(alloc);
    defer collector.deinit();

    const strings = [_][]const u8{
        "abc",
        "a_b_c",
        "a---b---c",
    };

    const query = "abc";

    searcher.config.bonus.word_start = 0;
    const results = try collector.reorder_strings(&strings, query, &searcher, .insensitive);

    // "abc" (tightest match) should be first, then "a_b_c", then "a---b---c"
    try std.testing.expectEqualStrings("abc", results[0].string);
    try std.testing.expectEqualStrings("a_b_c", results[1].string);
    try std.testing.expectEqualStrings("a---b---c", results[2].string);
}

test "SearchCollector: stable when scores tie" {
    const alloc = std.testing.allocator;

    var searcher = SublimeSearcher.init(alloc, .{});
    defer searcher.deinit();

    var collector = SearchCollector.init(alloc);
    defer collector.deinit();

    const strings = [_][]const u8{
        "alpha",
        "alphanumeric",
    };

    const query = "alp";

    const results = try collector.reorder_strings(&strings, query, &searcher, .insensitive);

    // Both contain "alp"; their scores may tie.
    // At least ensure both appear in the result set and in some deterministic order.
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("alpha", results[0].string);
}

test "SearchCollector: empty query produces empty results" {
    const alloc = std.testing.allocator;

    var searcher = SublimeSearcher.init(alloc, .{});
    defer searcher.deinit();

    var collector = SearchCollector.init(alloc);
    defer collector.deinit();

    const strings = [_][]const u8{
        "one",
        "two",
        "three",
    };

    const query = "";

    const results = try collector.reorder_strings(&strings, query, &searcher, .insensitive);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
