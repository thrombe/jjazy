const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub inline fn cast(typ: type, val: anytype) typ {
    const E = @typeInfo(@TypeOf(val));
    const T = @typeInfo(typ);
    if (comptime (std.meta.activeTag(E) == .int and std.meta.activeTag(T) == .float)) {
        return @floatFromInt(val);
    }
    if (comptime (std.meta.activeTag(E) == .float and std.meta.activeTag(T) == .int)) {
        return @intFromFloat(val);
    }
    if (comptime (std.meta.activeTag(E) == .float and std.meta.activeTag(T) == .float)) {
        return @floatCast(val);
    }
    if (comptime (std.meta.activeTag(E) == .int and std.meta.activeTag(T) == .int)) {
        return @intCast(val);
    }
    if (comptime (std.meta.activeTag(E) == .comptime_int)) {
        return val;
    }
    if (comptime (std.meta.activeTag(E) == .comptime_float)) {
        if (comptime (std.meta.activeTag(T) == .float)) {
            return val;
        }
        if (comptime (std.meta.activeTag(T) == .int)) {
            return @intFromFloat(@as(f32, val));
        }
    }
    @compileError("can't cast from '" ++ @typeName(@TypeOf(val)) ++ "' to '" ++ @typeName(typ) ++ "'");
}

const Status = struct {
    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        var children = std.ArrayList(vxfw.SubSurface).init(ctx.arena);
        errdefer children.deinit();
        try children.ensureTotalCapacity(20);

        const count_text = try std.fmt.allocPrint(ctx.arena, "lol. lmao even", .{});
        const text: vxfw.Text = .{ .text = count_text };

        const border = try ctx.arena.create(vxfw.Border);
        border.* = vxfw.Border{
            .child = text.widget(),
            .style = .{ .fg = .{ .index = 3 }, .bg = .default },
        };
        try children.append(.{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try border.draw(ctx.withConstraints(
                .{ .width = max_size.width, .height = max_size.height - 2 },
                .{ .width = max_size.width, .height = max_size.height - 2 },
            )),
        });

        return .{
            .size = max_size,
            .widget = .{
                .userdata = self,
                .drawFn = @This().draw,
            },
            .buffer = &.{},
            .children = try children.toOwnedSlice(),
        };
    }
};
const Diff = struct {
    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const max_size = ctx.max.size();

        var children = std.ArrayList(vxfw.SubSurface).init(ctx.arena);
        errdefer children.deinit();
        try children.ensureTotalCapacity(20);

        const count_text = try std.fmt.allocPrint(ctx.arena, "lol. lmao even", .{});
        const text: vxfw.Text = .{ .text = count_text };

        const border = try ctx.arena.create(vxfw.Border);
        border.* = vxfw.Border{
            .child = text.widget(),
            .style = .{ .fg = .{ .index = 3 }, .bg = .default },
        };
        try children.append(.{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try border.draw(ctx.withConstraints(
                .{ .width = max_size.width, .height = max_size.height - 2 },
                .{ .width = max_size.width, .height = max_size.height - 2 },
            )),
        });

        return .{
            .size = max_size,
            .widget = .{
                .userdata = self,
                .drawFn = @This().draw,
            },
            .buffer = &.{},
            .children = try children.toOwnedSlice(),
        };
    }
};

/// Our main application state
const Model = struct {
    status: Status = .{},
    diff: Diff = .{},
    separator: f32 = 0.5,

    fn init(alloc: std.mem.Allocator) !*@This() {
        // for a stable pointer
        const model = try alloc.create(Model);
        errdefer alloc.destroy(model);

        model.* = @This(){};

        return model;
    }

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Helper function to return a vxfw.Widget struct
    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.handleEvent,
            .drawFn = Model.draw,
        };
    }

    /// This function will be called from the vxfw runtime.
    fn handleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
        const self: *Model = @ptrCast(@alignCast(ptr));
        switch (event) {
            // The root widget is always sent an init event as the first event. Users of the
            // library can also send this event to other widgets they create if they need to do
            // some initialization.
            // .init => return ctx.requestFocus(self.button.widget()),
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    ctx.quit = true;
                    return;
                }
                if (key.matches('l', .{ .ctrl = true })) {
                    self.separator += 0.1;
                    self.separator = @min(self.separator, 1.0);
                }
                if (key.matches('h', .{ .ctrl = true })) {
                    self.separator -= 0.1;
                    self.separator = @max(self.separator, 0.0);
                }
                try ctx.queueRefresh();
            },
            // We can request a specific widget gets focus. In this case, we always want to focus
            // our button. Having focus means that key events will be sent up the widget tree to
            // the focused widget, and then bubble back down the tree to the root. Users can tell
            // the runtime the event was handled and the capture or bubble phase will stop
            // .focus_in => return ctx.requestFocus(self.button.widget()),
            else => {},
        }
    }

    /// This function is called from the vxfw runtime. It will be called on a regular interval, and
    /// only when any event handler has marked the redraw flag in EventContext as true. By
    /// explicitly requiring setting the redraw flag, vxfw can prevent excessive redraws for events
    /// which don't change state (ie mouse motion, unhandled key events, etc)
    fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        // The DrawContext is inspired from Flutter. Each widget will receive a minimum and maximum
        // constraint. The minimum constraint will always be set, even if it is set to 0x0. The
        // maximum constraint can have null width and/or height - meaning there is no constraint in
        // that direction and the widget should take up as much space as it needs. By calling size()
        // on the max, we assert that it has some constrained size. This is *always* the case for
        // the root widget - the maximum size will always be the size of the terminal screen.
        const max_size = ctx.max.size();

        // The DrawContext also contains an arena allocator that can be used for each frame. The
        // lifetime of this allocation is until the next time we draw a frame. This is useful for
        // temporary allocations such as the one below: we have an integer we want to print as text.
        // We can safely allocate this with the ctx arena since we only need it for this frame.
        // const count_text = try std.fmt.allocPrint(ctx.arena, "{d}", .{self.count});
        // const text: vxfw.Text = .{ .text = count_text };

        var children = std.ArrayList(vxfw.SubSurface).init(ctx.arena);
        errdefer children.deinit();
        try children.ensureTotalCapacity(20);

        const status_width = cast(u16, cast(f32, max_size.width) * self.separator);

        // Each widget returns a Surface from its draw function. A Surface contains the rectangular
        // area of the widget, as well as some information about the surface or widget: can we focus
        // it? does it handle the mouse?
        //
        // It DOES NOT contain the location it should be within its parent. Only the parent can set
        // this via a SubSurface. Here, we will return a Surface for the root widget (Model), which
        // has two SubSurfaces: one for the text and one for the button. A SubSurface is a Surface
        // with an offset and a z-index - the offset can be negative. This lets a parent draw a
        // child and place it within itself
        try children.append(.{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try Status.draw(@ptrCast(&self.status), ctx.withConstraints(ctx.min, .{
                .width = status_width,
                .height = max_size.height,
            })),
        });

        try children.append(.{
            .origin = .{ .row = 0, .col = status_width },
            .surface = try Diff.draw(@ptrCast(&self.diff), ctx.withConstraints(ctx.min, .{
                .width = max_size.width - status_width,
                .height = max_size.height,
            })),
        });

        // try children.append(.{
        //     .origin = .{ .row = 2, .col = 0 },
        //     .surface = try self.button.draw(ctx.withConstraints(
        //         ctx.min,
        //         // Here we explicitly set a new maximum size constraint for the Button. A Button will
        //         // expand to fill its area and must have some hard limit in the maximum constraint
        //         .{ .width = 16, .height = 3 },
        //     )),
        // });

        // const border = try ctx.arena.create(vxfw.Border);
        // border.* = vxfw.Border{
        //     .child = self.button.widget(),
        //     .style = .{ .fg = .{ .index = 3 }, .bg = .default },
        // };
        // try children.append(.{
        //     .origin = .{ .row = 10, .col = 10 },
        //     .surface = try border.draw(ctx.withConstraints(.{}, .{ .width = max_size.width - 10, .height = max_size.height - 10 })),
        // });

        return .{
            // A Surface must have a size. Our root widget is the size of the screen
            .size = max_size,
            .widget = self.widget(),
            // We didn't actually need to draw anything for the root. In this case, we can set
            // buffer to a zero length slice. If this slice is *not zero length*, the runtime will
            // assert that its length is equal to the size.width * size.height.
            .buffer = &.{},
            .children = try children.toOwnedSlice(),
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    const model = try Model.init(allocator);
    defer model.deinit(allocator);

    try app.run(model.widget(), .{});
}
