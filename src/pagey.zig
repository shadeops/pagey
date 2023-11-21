const std = @import("std");

const ray = @cImport(
    @cInclude("raylib.h"),
);

const default_res_x = 1200;
const default_res_y = 1000;

const Msg = struct {
    ticks: u64,
    msg: enum {
        none,
        normal,
        sequential,
        random,
    },
    fn draw(self: Msg) !void {
        switch (self.msg) {
            .normal => ray.DrawText("madvise normal", 30, 30, 48, ray.BLUE),
            .sequential => ray.DrawText("madvise sequential", 30, 30, 48, ray.BLUE),
            .random => ray.DrawText("madvise random", 30, 30, 48, ray.BLUE),
            .none => return,
        }
    }
};

fn offsetFromPageTile(tile_x: u64, tile_y: u64, pages_in_row: u64) usize {
    return @intCast((tile_x + (tile_y * pages_in_row)) * std.mem.page_size);
}

// From https://math.stackexchange.com/questions/466198/algorithm-to-get-the-maximum-size-of-n-squares-that-fit-into-a-rectangle-with-a
fn squareSize(n: u64, x: u64, y: u64) u64 {
    // we could use @Vector for this
    const n_f = @as(f32, @floatFromInt(n));
    const x_f = @as(f32, @floatFromInt(x));
    const y_f = @as(f32, @floatFromInt(y));
    const px = @ceil(@sqrt(n_f * x_f / y_f));
    const py = @ceil(@sqrt(n_f * y_f / x_f));
    const sx = if (@floor(px * y_f / x_f) * px < n_f) y_f / @ceil(px * y_f / x_f) else x_f / px;
    const sy = if (@floor(px * x_f / y_f) * py < n_f) x_f / @ceil(py * x_f / y_f) else y_f / py;
    return @intFromFloat(@max(sx, sy));
}

fn flush() void {
    std.os.sync();
    const drop_caches = std.fs.openFileAbsoluteZ(
        "/proc/sys/vm/drop_caches",
        .{ .mode = .write_only }) catch |err| switch (err) {
            error.AccessDenied => {
                std.log.err("No permissions for /proc/sys/vm/drop_caches, try sudo", .{});
                return;
            },
            else => {
                std.log.err("Error accessing /proc/sys/vm/drop_caches, {}", .{err});
                return;
            },
        };
    defer drop_caches.close();
    _ = drop_caches.write("3") catch |err| {
        std.log.err("Failed to write to drop_caches {}", .{err});
    };
}

pub fn main() !u8 {

    // Setup Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    // Parse Args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) {
        std.log.err("Missing filename", .{});
        return 1;
    }
    const file_name = args[1];

    var window_title_buf: [255:0]u8 = undefined;
    const pagey_title = "pagey - ";
    const window_title = try std.fmt.bufPrintZ(&window_title_buf, "{s}{s}", .{
        pagey_title,
        file_name[0..@min(file_name.len, 255 - pagey_title.len)],
    });

    // Open File
    const cwd = std.fs.cwd();
    const file = cwd.openFile(file_name, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("'{s}' is not a valid file", .{file_name});
            return 1;
        },
        else => return err,
    };
    defer file.close();
    const reader = file.reader();

    const file_size = try file.getEndPos();
    const pages = (file_size + std.mem.page_size - 1) / std.mem.page_size;

    ///////////////////////////////////////////////////////////////////////////
    // Setup Memory Mapping
    const mapped_file = try std.os.mmap(
        null,
        file_size,
        std.os.PROT.READ,
        std.os.MAP.PRIVATE,
        file.handle,
        0,
    );
    defer std.os.munmap(mapped_file);

    // Setup mincore page vector
    var vec = try allocator.alloc(u8, pages);
    defer allocator.free(vec);

    ///////////////////////////////////////////////////////////////////////////
    // Setup Dimensions
    std.debug.assert(vec.len == pages);
    std.debug.assert(vec.len * std.mem.page_size >= file_size);

    var res_x: u64 = default_res_x;
    var res_y: u64 = default_res_y;
    var tile_size = squareSize(pages, res_x, res_y);
    var tile_pad: u64 = if (tile_size < 16) 1 else 0;
    var max_pages = @min(vec.len, res_x * res_y);

    var pages_per_row = @divTrunc(res_x, tile_size);

    std.log.debug("File Size: {}", .{file_size});
    std.log.debug("Pages: {}", .{pages});
    std.log.debug("Tile Size: {}", .{tile_size});
    std.log.debug("Pages Per Row: {}", .{pages_per_row});

    ///////////////////////////////////////////////////////////////////////////
    // Init Raylib Window
    ray.SetTraceLogLevel(4);
    ray.SetTargetFPS(60);
    ray.InitWindow(@intCast(res_x), @intCast(res_y), window_title.ptr);
    ray.SetWindowState(ray.FLAG_WINDOW_RESIZABLE);

    var msg = Msg{ .ticks = 0, .msg = .none };

    // Main Loop
    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(ray.BLACK);

        if (ray.IsWindowResized()) {
            res_x = @intCast(ray.GetScreenWidth());
            res_y = @intCast(ray.GetScreenHeight());
            tile_size = squareSize(pages, res_x, res_y);
            pages_per_row = @divTrunc(res_x, tile_size);
            max_pages = @min(vec.len, res_x * res_y);
            tile_pad = if (tile_size < 16) 1 else 0;
            std.log.debug("Window: {}x{}", .{ res_x, res_y });
            std.log.debug("Tile Size: {}", .{tile_size});
            std.log.debug("Pages Per Row: {}", .{pages_per_row});
        }

        // Fetch Loaded Pages And Update Page Texture
        try std.os.mincore(mapped_file.ptr, file_size, vec.ptr);

        // This could probably be done in a GLSL shader with the page
        // vector passed in as a texture map
        for (vec[0..max_pages], 0..) |v, i| {
            const col: usize = i % pages_per_row;
            const row: usize = @divTrunc(i, pages_per_row);
            ray.DrawRectangle(
                @intCast(col * tile_size),
                @intCast(row * tile_size),
                @intCast(tile_size),
                @intCast(tile_size),
                if (v & 0x1 == 1) ray.GREEN else ray.WHITE,
            );
            if (tile_size > 3) {
                ray.DrawRectangleLines(
                    @intCast(col * tile_size),
                    @intCast(row * tile_size),
                    @intCast(tile_size + tile_pad),
                    @intCast(tile_size + tile_pad),
                    ray.GRAY,
                );
            }
        }

        // Get Mouse Interaction
        if (ray.IsCursorOnScreen()) {
            const mouse_x = ray.GetMouseX();
            const mouse_y = ray.GetMouseY();

            // Highlight Current Page
            const mouse_tile_x = @divFloor(@as(u64, @intCast(mouse_x)), tile_size);
            const mouse_tile_y = @divFloor(@as(u64, @intCast(mouse_y)), tile_size);

            const mouse_tile = mouse_tile_x + mouse_tile_y * pages_per_row;

            if (mouse_tile_x < pages_per_row and mouse_tile < pages) {
                ray.DrawRectangle(
                    @intCast(mouse_tile_x * tile_size),
                    @intCast(mouse_tile_y * tile_size),
                    @intCast(tile_size),
                    @intCast(tile_size),
                    .{ .r = 255, .g = 96, .b = 32, .a = 128 },
                );

                // Load Byte From Current Page
                if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_LEFT)) {
                    const offset = offsetFromPageTile(mouse_tile_x, mouse_tile_y, pages_per_row);
                    if (offset < file_size) {
                        try file.seekTo(offset);
                        const byte = try reader.readByte();
                        _ = byte;
                    }
                } else if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_RIGHT)) {
                    const offset = offsetFromPageTile(mouse_tile_x, mouse_tile_y, pages_per_row);
                    if (offset < file_size) {
                        // this is needed to prevent the optimizer from removing this code
                        var byte: u8 = undefined;
                        const b: *volatile u8 = &byte;
                        b.* = mapped_file[offset];
                    }
                }
            }

            if (ray.IsKeyPressed(ray.KEY_F1)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.NORMAL);
                msg = .{ .msg = .normal, .ticks = 30 };
            } else if (ray.IsKeyPressed(ray.KEY_F2)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.SEQUENTIAL);
                msg = .{ .msg = .sequential, .ticks = 30 };
            } else if (ray.IsKeyPressed(ray.KEY_F3)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.RANDOM);
                msg = .{ .msg = .random, .ticks = 30 };
            } else if (ray.IsKeyPressed(ray.KEY_DELETE)) {
                flush();
            }
        }

        if (msg.msg != .none) {
            try msg.draw();
            msg.ticks -|= 1;
            if (msg.ticks == 0) msg.msg = .none;
        }
        //ray.DrawFPS(10, 10);
    }
    return 0;
}
