const std = @import("std");

const utils_mod = @import("utils.zig");

// based on [zg](https://codeberg.org/atman/zg/src/commit/9427a9e53aaa29ee071f4dcb35b809a699d75aa9/codegen/dwp.zig)
const TableGenerator = struct {
    const derived_east_asian_width = @embedFile("DerivedEastAsianWidth.txt");
    const derived_general_category = @embedFile("DerivedGeneralCategory.txt");

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
                        'H' => 1,
                        'N' => 1,
                        'W' => 2,
                        'F' => 2,
                        'A' => 2,
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
                if (std.mem.eql(u8, prop, "Mn")) {
                    // Nonspacing_Mark
                    for (start..end + 1) |cp| try lenmap.put(@intCast(cp), 0);
                } else if (std.mem.eql(u8, prop, "Me")) {
                    // Enclosing_Mark
                    for (start..end + 1) |cp| try lenmap.put(@intCast(cp), 0);
                } else if (std.mem.eql(u8, prop, "Mc")) {
                    // Spacing_Mark
                    for (start..end + 1) |cp| try lenmap.put(@intCast(cp), 0);
                } else if (std.mem.eql(u8, prop, "Cf")) {
                    if (std.mem.indexOf(u8, line, "ARABIC") == null) {
                        // Format except Arabic
                        for (start..end + 1) |cp| try lenmap.put(@intCast(cp), 0);
                    }
                }
            }
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
