const std = @import("std");

const ray = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
});

const default_res_x = 1200;
const default_res_y = 1000;

const shader_glsl =
    \\#version 430
    \\
    \\// Provided by raylib
    \\
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\out vec4 finalColor;
    \\
    \\// Provided by program
    \\
    \\// SSBO
    \\layout(std430, binding = 1) readonly restrict buffer data
    \\{
    \\    uint dataArray[];
    \\};
    \\uniform int tile_size;
    \\uniform int total_tiles;
    \\uniform int res_x;
    \\uniform int res_y;
    \\
    \\void main() {
    \\
    \\uint row = uint(floor((fragTexCoord.y * res_y)/tile_size));
    \\uint col = uint(floor((fragTexCoord.x * res_x)/tile_size));
    \\uint tiles_per_row = res_x / tile_size;
    \\uint tile = row * tiles_per_row + col;
    \\uint element = tile / 4;
    \\uint offset = (tile % 4) * 8;
    \\uint val = (dataArray[element] >> offset) & 255;
    \\finalColor = vec4(0.0, 0.0, 0.0, 1.0);
    \\
    // If we pass u8's we need to shift the GLSL uint to get the u8
    // Assuming dataArray = [_]u8{0,1,2,3,4,5,6,...};
    //\\ ((dataArray[0] >> 24 ) & 255) == 3
    //\\ ((dataArray[0] >> 16 ) & 255) == 2
    //\\ ((dataArray[0] >>  8 ) & 255) == 1
    //\\ ((dataArray[0] >>  0 ) & 255) == 0
    \\if (tile < total_tiles && col < tiles_per_row) {
    \\  if ((val & 1) == 1) { 
    \\    finalColor = vec4(0.0, 1.0, 0.0, 1.0);
    \\  } else {
    \\    finalColor = vec4(1.0, 1.0, 1.0, 1.0);
    \\  }
    \\}
    \\}
;

const Msg = struct {
    duration: f32 = 1.0,
    elapsed: f32 = 0.0,
    msg: enum {
        none,
        normal,
        sequential,
        random,
    } = .none,
    fn draw(self: Msg) void {
        switch (self.msg) {
            .normal => ray.DrawText("madvise normal", 30, 30, 48, ray.BLUE),
            .sequential => ray.DrawText("madvise sequential", 30, 30, 48, ray.BLUE),
            .random => ray.DrawText("madvise random", 30, 30, 48, ray.BLUE),
            .none => return,
        }
    }
};

fn offsetFromPageTile(tile_x: i32, tile_y: i32, pages_in_row: i32) i32 {
    return (tile_x + (tile_y * pages_in_row)) * @as(i32, @intCast(std.mem.page_size));
}

// From https://math.stackexchange.com/questions/466198/algorithm-to-get-the-maximum-size-of-n-squares-that-fit-into-a-rectangle-with-a
fn squareSize(n: i32, x: i32, y: i32) i32 {
    // we could use @Vector for this
    const n_f = @as(f32, @floatFromInt(n));
    const x_f = @as(f32, @floatFromInt(x));
    const y_f = @as(f32, @floatFromInt(y));
    const px = @ceil(@sqrt(n_f * x_f / y_f));
    const py = @ceil(@sqrt(n_f * y_f / x_f));
    const sx = if (@floor(px * y_f / x_f) * px < n_f) y_f / @ceil(px * y_f / x_f) else x_f / px;
    const sy = if (@floor(px * x_f / y_f) * py < n_f) x_f / @ceil(py * x_f / y_f) else y_f / py;
    return @intFromFloat(@max(sx, sy, 1.0));
}

fn flush() void {
    std.os.sync();
    const drop_caches = std.fs.openFileAbsoluteZ("/proc/sys/vm/drop_caches", .{ .mode = .write_only }) catch |err| switch (err) {
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

fn generateGridOverlay(
    res_x: i32,
    res_y: i32,
    tile_size: i32,
    pad: i32,
    pages: i32,
) ray.RenderTexture {
    const tex = ray.LoadRenderTexture(res_x, res_y);
    const tiles_per_row = @as(u32, @intCast(@divTrunc(res_x, tile_size)));
    {
        ray.BeginTextureMode(tex);
        defer ray.EndTextureMode();
        ray.ClearBackground(ray.BLANK);

        for (0..@intCast(pages)) |i| {
            const col: usize = i % tiles_per_row;
            const row: usize = @divTrunc(i, tiles_per_row);
            ray.DrawRectangleLines(
                @as(i32, @intCast(col)) * tile_size,
                @as(i32, @intCast(row)) * tile_size,
                tile_size + pad,
                tile_size + pad,
                ray.GRAY,
            );
        }
    }
    ray.SetTextureFilter(tex.texture, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(tex.texture, ray.TEXTURE_WRAP_CLAMP);
    return tex;
}

fn generateShaderTex(res_x: i32, res_y: i32) ray.Texture {
    var img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    ray.ImageFormat(&img, ray.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    const tex = ray.LoadTextureFromImage(img);
    ray.UnloadImage(img);
    return tex;
}

pub fn main() !u8 {

    // Setup Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    ///////////////////////////////////////////////////////////////////////////
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

    ///////////////////////////////////////////////////////////////////////////
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
    const vec = try allocator.alloc(u8, pages);
    defer allocator.free(vec);
    for (vec) |*v| {
        v.* = 0;
    }

    std.debug.assert(vec.len == pages);
    std.debug.assert(vec.len * std.mem.page_size >= file_size);

    ///////////////////////////////////////////////////////////////////////////
    // Setup Window Dimensions
    var res_x: i32 = default_res_x;
    var res_y: i32 = default_res_y;
    var tile_size: i32 = squareSize(@intCast(pages), res_x, res_y);
    var tile_pad: i32 = if (tile_size < 16) 1 else 0;
    var max_pages: i32 = @min(@as(i32, @intCast(vec.len)), res_x * res_y);

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

    var msg = Msg{};

    const shader = ray.LoadShaderFromMemory(null, shader_glsl);
    defer ray.UnloadShader(shader);

    const res_x_loc = ray.GetShaderLocation(shader, "res_x");
    const res_y_loc = ray.GetShaderLocation(shader, "res_y");
    const tile_size_loc = ray.GetShaderLocation(shader, "tile_size");
    const total_tiles_loc = ray.GetShaderLocation(shader, "total_tiles");

    ray.SetShaderValue(shader, res_x_loc, &res_x, ray.SHADER_UNIFORM_INT);
    ray.SetShaderValue(shader, res_y_loc, &res_y, ray.SHADER_UNIFORM_INT);
    ray.SetShaderValue(shader, tile_size_loc, &tile_size, ray.SHADER_UNIFORM_INT);
    ray.SetShaderValue(shader, total_tiles_loc, &max_pages, ray.SHADER_UNIFORM_INT);

    const ssbo = ray.rlLoadShaderBuffer(@intCast(vec.len), vec.ptr, ray.RL_DYNAMIC_DRAW);
    defer ray.rlUnloadShaderBuffer(ssbo);
    ray.rlBindShaderBuffer(ssbo, 1);

    const tex = generateShaderTex(res_x, res_y);
    var outline_rtex = generateGridOverlay(res_x, res_y, tile_size, tile_pad, max_pages);

    ///////////////////////////////////////////////////////////////////////////
    // Main Loop
    while (!ray.WindowShouldClose()) {

        // Handle resizing of window
        if (ray.IsWindowResized()) {
            res_x = @intCast(ray.GetScreenWidth());
            res_y = @intCast(ray.GetScreenHeight());
            tile_size = squareSize(@intCast(pages), res_x, res_y);
            pages_per_row = @divTrunc(res_x, tile_size);
            max_pages = @min(res_x * res_y, @as(i32, @intCast(vec.len)));
            tile_pad = if (tile_size < 16) 1 else 0;
            if (tile_size > 3) {
                ray.UnloadRenderTexture(outline_rtex);
                outline_rtex = generateGridOverlay(res_x, res_y, tile_size, tile_pad, max_pages);
            }

            ray.SetShaderValue(shader, res_x_loc, &res_x, ray.SHADER_UNIFORM_INT);
            ray.SetShaderValue(shader, res_y_loc, &res_y, ray.SHADER_UNIFORM_INT);
            ray.SetShaderValue(shader, tile_size_loc, &tile_size, ray.SHADER_UNIFORM_INT);
            ray.SetShaderValue(shader, total_tiles_loc, &max_pages, ray.SHADER_UNIFORM_INT);

            std.log.debug("Window: {}x{}", .{ res_x, res_y });
            std.log.debug("Tile Size: {}", .{tile_size});
            std.log.debug("Tile Pad: {}", .{tile_pad});
            std.log.debug("Pages Per Row: {}", .{pages_per_row});
            std.log.debug("Max Pages: {}", .{max_pages});
        }

        // Fetch Loaded Pages And Update Page Texture
        try std.os.mincore(mapped_file.ptr, file_size, vec.ptr);
        ray.rlUpdateShaderBuffer(ssbo, vec.ptr, @intCast(vec.len), 0);

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);

        {
            ray.BeginShaderMode(shader);
            defer ray.EndShaderMode();
            ray.DrawTexturePro(
                tex,
                .{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(tex.width),
                    .height = @floatFromInt(tex.height),
                },
                .{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(res_x),
                    .height = @floatFromInt(res_y),
                },
                .{ .x = 0, .y = 0 },
                0.0,
                ray.WHITE,
            );
        }

        if (tile_size > 3) {
            ray.DrawTextureRec(
                outline_rtex.texture,
                .{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @floatFromInt(outline_rtex.texture.width),
                    .height = @floatFromInt(-outline_rtex.texture.height),
                },
                .{ .x = 0, .y = 0 },
                ray.WHITE,
            );
        }

        //// Get Mouse Interaction
        if (ray.IsCursorOnScreen()) {
            const mouse_x = ray.GetMouseX();
            const mouse_y = ray.GetMouseY();

            // Highlight Current Page
            const mouse_tile_x = @divFloor(mouse_x, tile_size);
            const mouse_tile_y = @divFloor(mouse_y, tile_size);

            const mouse_tile = mouse_tile_x + mouse_tile_y * pages_per_row;

            if (mouse_tile_x < pages_per_row and mouse_tile < pages) {
                ray.DrawRectangle(
                    mouse_tile_x * tile_size,
                    mouse_tile_y * tile_size,
                    tile_size,
                    tile_size,
                    .{ .r = 255, .g = 96, .b = 32, .a = 128 },
                );

                // Load Byte From Current Page
                if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_LEFT)) {
                    const offset = offsetFromPageTile(mouse_tile_x, mouse_tile_y, pages_per_row);
                    if (offset < file_size) {
                        try file.seekTo(@intCast(offset));
                        const byte = try reader.readByte();
                        _ = byte;
                    }
                    std.log.debug("LMB @ {},{} = {}", .{ mouse_tile_x, mouse_tile_y, offset });
                } else if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_RIGHT)) {
                    const offset = offsetFromPageTile(mouse_tile_x, mouse_tile_y, pages_per_row);
                    if (offset < file_size) {
                        // this is needed to prevent the optimizer from removing this code
                        var byte: u8 = undefined;
                        const b: *volatile u8 = &byte;
                        b.* = mapped_file[@intCast(offset)];
                    }
                    std.log.debug("RMB @ {},{} = {}", .{ mouse_tile_x, mouse_tile_y, offset });
                }
            }

            if (ray.IsKeyPressed(ray.KEY_F1)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.NORMAL);
                msg = .{ .msg = .normal };
            } else if (ray.IsKeyPressed(ray.KEY_F2)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.SEQUENTIAL);
                msg = .{ .msg = .sequential };
            } else if (ray.IsKeyPressed(ray.KEY_F3)) {
                try std.os.madvise(mapped_file.ptr, mapped_file.len, std.os.MADV.RANDOM);
                msg = .{ .msg = .random };
            } else if (ray.IsKeyPressed(ray.KEY_DELETE)) {
                flush();
            }
        }

        if (msg.msg != .none) {
            msg.draw();
            msg.elapsed += ray.GetFrameTime();
            if (msg.elapsed > msg.duration) msg = .{};
        }
        //ray.DrawFPS(10, 10);
        ray.EndDrawing();

        if (ray.IsKeyPressed(ray.KEY_ENTER)) {
            const img = ray.LoadImageFromScreen();
            defer ray.UnloadImage(img);
            const status = ray.ExportImage(img, "capture.png");
            std.log.info("Saved 'capture.png' {}", .{status});
        }
    }

    ray.UnloadRenderTexture(outline_rtex);
    ray.UnloadTexture(tex);

    return 0;
}
