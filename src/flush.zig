const std = @import("std");

pub fn main() !void {
    std.os.sync();
    const drop_caches = try std.fs.openFileAbsoluteZ("/proc/sys/vm/drop_caches", .{ .mode = .write_only });
    defer drop_caches.close();
    _ = try drop_caches.write("3");
}
