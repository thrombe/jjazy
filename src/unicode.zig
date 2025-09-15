const std = @import("std");

const utils_mod = @import("utils.zig");

// based on [zg](https://codeberg.org/atman/zg/src/commit/9427a9e53aaa29ee071f4dcb35b809a699d75aa9/codegen/dwp.zig)
const TableGenerator = struct {
    const derived_east_asian_width = @embedFile("DerivedEastAsianWidth.txt");
    const derived_general_category = @embedFile("DerivedGeneralCategory.txt");

    const options = struct {
        const cjk_a_width: ?u3 = null;
        const c0_width: ?u3 = null;
        const c1_width: ?u3 = null;
    };

    fn generate(alloc: std.mem.Allocator, w: std.fs.File.Writer) !void {
        _ = w;

        var lenmap = std.AutoHashMap(u21, u3).init(alloc);

        {
            var lines = utils_mod.LineIterator.init(derived_east_asian_width);
            while (lines.next()) |rawline| {
                var line = std.mem.trim(u8, rawline, &std.ascii.whitespace);
                if (line.len == 0) continue;

                const missing = std.mem.containsAtLeast(u8, line, 1, "@missing");
                const comment = std.mem.startsWith(u8, line, "#");
                if (!missing and comment) continue;

                if (missing) {
                    var maybe_missing = std.mem.splitSequence(u8, line, "@missing:");
                    _ = maybe_missing.next();
                    line = std.mem.trim(u8, maybe_missing.next().?, &std.ascii.whitespace);
                }

                var parts = std.mem.splitSequence(u8, line, ";");
                var ranges = std.mem.splitSequence(u8, parts.next().?, "..");
                var props = std.mem.splitAny(u8, std.mem.trim(u8, parts.next().?, &std.ascii.whitespace), &std.ascii.whitespace);

                const start_str = std.mem.trim(u8, ranges.next().?, &std.ascii.whitespace);
                const end_str = std.mem.trim(u8, ranges.next() orelse start_str, &std.ascii.whitespace);
                const start = try std.fmt.parseInt(u21, start_str, 16);
                const end = try std.fmt.parseInt(u21, end_str, 16);
                const prop = props.next().?;

                // std.debug.print("start: {x} end: {x} prop: '{s}'\n", .{ start, end, prop });
                for (start..end + 1) |c| {
                    try lenmap.put(@intCast(c), switch (prop[0]) {
                        'H', 'N' => 1,
                        'W', 'F' => 2,
                        'A' => options.cjk_a_width orelse 2,
                        else => unreachable,
                    });
                }
            }
        }
        {
            var lines = utils_mod.LineIterator.init(derived_general_category);
            while (lines.next()) |rawline| {
                const line = std.mem.trim(u8, rawline, &std.ascii.whitespace);
                if (line.len == 0) continue;
                if (std.mem.startsWith(u8, line, "#")) continue;

                var parts = std.mem.splitSequence(u8, line, ";");
                var ranges = std.mem.splitSequence(u8, parts.next().?, "..");
                var props = std.mem.splitAny(u8, std.mem.trim(u8, parts.next().?, &std.ascii.whitespace), &std.ascii.whitespace);

                const start_str = std.mem.trim(u8, ranges.next().?, &std.ascii.whitespace);
                const end_str = std.mem.trim(u8, ranges.next() orelse start_str, &std.ascii.whitespace);
                const start = try std.fmt.parseInt(u21, start_str, 16);
                const end = try std.fmt.parseInt(u21, end_str, 16);
                const prop = props.next().?;

                // std.debug.print("start: {x} end: {x} prop: '{s}'\n", .{ start, end, prop });
                var set_zero: bool = false;
                set_zero = set_zero or std.mem.eql(u8, prop, "Mn"); // Nonspacing_Mark
                set_zero = set_zero or std.mem.eql(u8, prop, "Me"); // Enclosing_Mark
                set_zero = set_zero or std.mem.eql(u8, prop, "Mc"); // Spacing_Mark
                set_zero = set_zero or (std.mem.eql(u8, prop, "Cf") and std.mem.indexOf(u8, line, "ARABIC") == null); // Format except Arabic

                if (set_zero) for (start..end + 1) |cp| try lenmap.put(@intCast(cp), 0);
            }
        }

        const block_size = 256;
        const Block = [block_size]i4;

        const BlockMap = std.HashMap(
            Block,
            u16,
            struct {
                pub fn hash(_: @This(), k: Block) u64 {
                    var hasher = std.hash.Wyhash.init(0);
                    std.hash.autoHashStrat(&hasher, k, .DeepRecursive);
                    return hasher.final();
                }

                pub fn eql(_: @This(), a: Block, b: Block) bool {
                    return std.mem.eql(i4, &a, &b);
                }
            },
            std.hash_map.default_max_load_percentage,
        );

        var blocks_map = BlockMap.init(alloc);
        defer blocks_map.deinit();

        var stage1 = std.ArrayList(u16).init(alloc);
        defer stage1.deinit();

        var stage2 = std.ArrayList(i4).init(alloc);
        defer stage2.deinit();

        var block: Block = [_]i4{0} ** block_size;
        var block_len: u16 = 0;

        for (0..0x110000) |i| {
            const cp: u21 = @intCast(i);
            var width = lenmap.get(cp) orelse 1;

            // Specific overrides
            switch (cp) {
                // Three-em dash
                0x2e3b => width = 3,

                // C0/C1 control codes
                0...0x20 => width = if (options.c0_width) |c0| c0 else 0,
                0x80...0x9f => width = if (options.c1_width) |c1| c1 else 0,

                // Line separator
                0x2028,

                // Paragraph separator
                0x2029,

                // Hangul syllable and ignorable.
                0x1160...0x11ff,
                0xd7b0...0xd7ff,
                0x2060...0x206f,
                0xfff0...0xfff8,
                0xe0000...0xE0fff,
                => width = 0,

                // Two-em dash
                0x2e3a,

                // Regional indicators
                0x1f1e6...0x1f200,

                // CJK Blocks
                0x3400...0x4dbf, // CJK Unified Ideographs Extension A
                0x4e00...0x9fff, // CJK Unified Ideographs
                0xf900...0xfaff, // CJK Compatibility Ideographs
                0x20000...0x2fffd, // Plane 2
                0x30000...0x3fffd, // Plane 3
                => width = 2,

                else => {},
            }

            // ASCII
            if (0x20 <= cp and cp < 0x7f) width = 1;

            // Soft hyphen
            if (cp == 0xad) width = 1;

            // Backspace and delete
            if (cp == 0x8 or cp == 0x7f) width = if (options.c0_width) |c0| c0 else -1;

            // Process block
            block[block_len] = width;
            block_len += 1;

            if (block_len < block_size and cp != 0x10ffff) continue;

            const gop = try blocks_map.getOrPut(block);
            if (!gop.found_existing) {
                gop.value_ptr.* = @intCast(stage2.items.len);
                try stage2.appendSlice(&block);
            }

            try stage1.append(gop.value_ptr.*);
            block_len = 0;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    const dest = args.next().?;

    const out = try std.fs.createFileAbsolute(dest, .{});
    defer out.close();
    const w = out.writer();

    try TableGenerator.generate(alloc, w);
}
