const std = @import("std");
const utils = @import("utils.zig");

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

    const CaseSensitivity = enum {
        sensitive,
        insensitive,
    };

    const Match = struct {
        /// Accumulative score
        score: i32,
        /// Count of current consecutive matched chars
        consecutive: i32,

        first_match_index: u32,
        last_match_index: u32,
    };

    fn init(alloc: std.mem.Allocator) @This() {
        var occ: [256]std.ArrayListUnmanaged(Occurrence) = undefined;
        @memset(&occ, .empty);
        return .{
            .alloc = alloc,
            .occ = occ,
            .match_cache = .{},
        };
    }

    fn reset(self: *@This()) void {
        self.match_cache.clearRetainingCapacity();
        for (&self.occ) |*occ| {
            occ.clearRetainingCapacity();
        }
    }

    fn deinit(self: *@This()) void {
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
        matched.last_match_index = max_match.?.last_match_index;

        try self.match_cache.putNoClobber(self.alloc, match_key, matched);
        return matched;
    }

    fn best_match(self: *@This(), string: []const u8, query: []const u8, case: CaseSensitivity) !?Match {
        if (query.len == 0) return null;
        self.reset();
        try self.match_cache.ensureTotalCapacity(self.alloc, @intCast(query.len * query.len));

        try self.capture_occurrences(string, query, case);

        const qc = query[0];
        const key = switch (case) {
            .sensitive => qc,
            .insensitive => std.ascii.toLower(qc),
        };
        const occs = self.occ[@intCast(key)].items;

        var max_match: ?Match = null;
        for (occs) |occ| {
            const m = try self.match(query, 0, occ, 0, case);
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

        // var matches = std.ArrayListUnmanaged(Match).empty;
        // const Ctx = struct {};
        // std.sort.block(Match, matches.items, Ctx, struct {
        //     fn lessThan(_: Ctx, lhs: Match, rhs: Match) bool {
        //         return lhs.score < rhs.score;
        //     }
        // }.lessThan);
    }
};
