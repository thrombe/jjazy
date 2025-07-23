const std = @import("std");

const utils_mod = @import("utils.zig");
const cast = utils_mod.cast;

pub const Vec2 = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn splat(t: u16) @This() {
        return .{ .x = t, .y = t };
    }

    pub fn add(self: *const @This(), other: @This()) @This() {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: *const @This(), other: @This()) @This() {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn max(self: *const @This(), other: @This()) @This() {
        return .{ .x = @max(self.x, other.x), .y = @max(self.y, other.y) };
    }

    pub fn min(self: *const @This(), other: @This()) @This() {
        return .{ .x = @min(self.x, other.x), .y = @min(self.y, other.y) };
    }

    pub fn mul(self: *const @This(), t: f32) @This() {
        return .{
            .x = cast(i32, cast(f32, self.x) * t),
            .y = cast(i32, cast(f32, self.y) * t),
        };
    }
};

pub const Region = struct {
    origin: Vec2 = .{},
    size: Vec2,

    pub const Range = struct { begin: i32, end: i32 };

    pub fn contains_x(self: *const @This(), x: i32) bool {
        return self.contains_vec(.{ .x = x, .y = self.origin.y });
    }

    pub fn contains_y(self: *const @This(), y: i32) bool {
        return self.contains_vec(.{ .x = self.origin.x, .y = y });
    }

    pub fn contains_vec(self: *const @This(), vec: Vec2) bool {
        return std.meta.eql(self.clamp_vec(vec), vec);
    }

    pub fn clamp_vec(self: *const @This(), vec: Vec2) Vec2 {
        return self.origin.max(vec).min(self.end());
    }

    pub fn clamp(self: *const @This(), other: @This()) @This() {
        const origin = other.origin
            .max(self.origin)
            .min(self.origin.add(self.size));
        const size = other.size.add(other.origin)
            .min(self.origin.add(self.size))
            .sub(origin)
            .max(.{});
        return .{ .origin = origin, .size = size };
    }

    pub fn end(self: *const @This()) Vec2 {
        return self.origin.add(self.size).sub(.splat(1));
    }

    pub fn range_x(self: *const @This()) Range {
        return .{ .begin = self.origin.x, .end = self.origin.x + self.size.x };
    }

    pub fn range_y(self: *const @This()) Range {
        return .{ .begin = self.origin.y, .end = self.origin.y + self.size.y };
    }

    pub fn border_sub(self: *const @This(), vec: Vec2) @This() {
        return .{ .origin = self.origin.add(vec), .size = self.size.sub(.{ .x = vec.x * 2, .y = vec.y * 2 }).max(.{}) };
    }

    pub fn split_x(self: *const @This(), x: i32, gap: bool) struct { left: Region, right: Region, split: i32 } {
        // gives prefrence from left when x >= 0 else to right

        if (x >= 0) {
            const left = self.clamp(.{
                .origin = self.origin,
                .size = .{ .x = x, .y = self.size.y },
            });
            const right = self.clamp(.{
                .origin = .{
                    .x = left.end().x + @intFromBool(gap) + 1,
                    .y = self.origin.y,
                },
                .size = .{
                    .x = self.size.x - left.size.x - @intFromBool(gap),
                    .y = self.size.y,
                },
            });
            return .{ .split = left.end().x + 1, .left = left, .right = right };
        } else {
            const right = self.clamp(.{
                .origin = .{
                    .x = self.end().x + x + 1,
                    .y = self.origin.y,
                },
                .size = .{
                    .x = -x,
                    .y = self.size.y,
                },
            });
            const left = self.clamp(.{
                .origin = self.origin,
                .size = .{
                    .x = self.size.x - right.size.x - @intFromBool(gap),
                    .y = self.size.y,
                },
            });
            return .{ .split = right.origin.x - 1, .left = left, .right = right };
        }
    }

    pub fn split_y(self: *const @This(), y: i32, gap: bool) struct { top: Region, bottom: Region, split: i32 } {
        // gives prefrence from top when y >= 0 else to bottom

        if (y >= 0) {
            const top = self.clamp(.{
                .origin = self.origin,
                .size = .{ .y = y, .x = self.size.x },
            });
            const bottom = self.clamp(.{
                .origin = .{
                    .y = top.end().y + @intFromBool(gap) + 1,
                    .x = self.origin.x,
                },
                .size = .{
                    .y = self.size.y - top.size.y - @intFromBool(gap),
                    .x = self.size.x,
                },
            });
            return .{ .split = top.end().y + 1, .top = top, .bottom = bottom };
        } else {
            const bottom = self.clamp(.{
                .origin = .{
                    .y = self.end().y + y + 1,
                    .x = self.origin.x,
                },
                .size = .{
                    .y = -y,
                    .x = self.size.x,
                },
            });
            const top = self.clamp(.{
                .origin = self.origin,
                .size = .{
                    .y = self.size.y - bottom.size.y - @intFromBool(gap),
                    .x = self.size.x,
                },
            });
            return .{ .split = bottom.origin.y - 1, .top = top, .bottom = bottom };
        }
    }
};
