const std = @import("std");

const utils_mod = @import("utils.zig");

const event_mod = @import("event.zig");

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = utils_mod.FileLogger.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    try utils_mod.FileLogger.logger.init(.{
        .allow_fail = true,
        .console_logs = false,
    });
    defer utils_mod.FileLogger.logger.deinit();

    defer _ = gpa.deinit();

    const app = try event_mod.App.init(alloc);
    defer app.deinit();

    app.event_loop() catch |e| utils_mod.dump_error(e);
}
