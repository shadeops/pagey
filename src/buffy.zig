const std = @import("std");

const ray = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
});

//const res_x = 400;
//const res_y = 240;
//const tile_size = 20;
const res_x = 1600;
const res_y = 1200;
const tile_size = 5;

const tile_pad = if (tile_size < 16) 1 else 0;
const tiles_per_row = @divExact(res_x, tile_size);
const tiles_per_col = @divExact(res_y, tile_size);
const max_tiles = tiles_per_row * tiles_per_col - 2000;

const mode = 0;

const shader_glsl =
    \\#version 430
    \\
    \\// Provided by raylib
    \\
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\uniform sampler2D texture0;
    \\
    \\out vec4 finalColor;
    \\
    \\
    \\// Provided by program
    \\
    \\// SSBO
    \\layout(std430, binding = 1) readonly restrict buffer data
    \\{
    \\    uint dataArray[];
    \\};
    \\uniform int tile_size;
    \\
    \\void main() {
    \\
    \\ivec2 tex_size = textureSize(texture0, 0);
    \\uint row = uint(floor((fragTexCoord.y * tex_size.y)/tile_size));
    \\uint col = uint(floor((fragTexCoord.x * tex_size.x)/tile_size));
    \\uint tiles_per_row = tex_size.x / tile_size;
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
    \\if (val == 1) finalColor.b = 1;
    \\}
;

pub fn main() !u8 {
    var prng = std.rand.DefaultPrng.init(42);
    const rand = prng.random();

    // Setup Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();
    const vec = try allocator.alloc(u8, max_tiles);
    defer allocator.free(vec);

    for (vec, 0..) |*v, i| {
        _ = i;
        v.* = if (rand.boolean()) 1 else 0;
    }
    ///////////////////////////////////////////////////////////////////////////
    // Init Raylib Window
    ray.SetTraceLogLevel(0);
    //ray.SetTargetFPS(60);
    ray.InitWindow(@intCast(res_x), @intCast(res_y), "Buffy");
    defer ray.CloseWindow();

    const img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    //ray.ImageFormat(&img, ray.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    const tex = ray.LoadTextureFromImage(img);
    defer ray.UnloadTexture(tex);
    ray.UnloadImage(img);

    const shader = ray.LoadShaderFromMemory(null, shader_glsl);
    defer ray.UnloadShader(shader);

    const tile_size_loc = ray.GetShaderLocation(shader, "tile_size");
    const tile_size_shd = @as(u32, @intCast(tile_size));
    ray.SetShaderValue(shader, tile_size_loc, &tile_size_shd, ray.SHADER_UNIFORM_INT);

    const ssbo = ray.rlLoadShaderBuffer(@intCast(vec.len), vec.ptr, ray.RL_DYNAMIC_DRAW);
    defer ray.rlUnloadShaderBuffer(ssbo);
    //ray.rlUpdateShaderBuffer(ssbo, &data, @sizeOf(@TypeOf(data)), 0);

    ray.rlBindShaderBuffer(ssbo, 1);

    const tile_img = ray.GenImageColor(tile_size, tile_size, ray.WHITE);
    const tile_tex = ray.LoadTextureFromImage(tile_img);
    defer ray.UnloadTexture(tile_tex);
    ray.UnloadImage(tile_img);

    const outline_tex = ray.LoadRenderTexture(res_x, res_y);
    {
        ray.BeginTextureMode(outline_tex);
        defer ray.EndTextureMode();

        for (0..max_tiles) |i| {
            const col: usize = i % tiles_per_row;
            const row: usize = @divTrunc(i, tiles_per_row);
            //if (tile_size > 3) {
            ray.DrawRectangleLines(
                @intCast(col * tile_size),
                @intCast(row * tile_size),
                @intCast(tile_size + tile_pad),
                @intCast(tile_size + tile_pad),
                ray.GRAY,
            );
            //}
        }
    }
    defer ray.UnloadRenderTexture(outline_tex);

    // Main Loop
    while (!ray.WindowShouldClose()) {
        for (vec, 0..) |*v, i| {
            _ = i;
            v.* = if (rand.boolean()) 1 else 0;
        }
        ray.rlUpdateShaderBuffer(ssbo, vec.ptr, @intCast(vec.len), 0);

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);

        switch (mode) {
            0 => {
                ray.BeginShaderMode(shader);
                defer ray.EndShaderMode();

                // must be set within a Shader mode as it gets reset at the end
                //ray.SetShaderValueTexture(shader, rgba_tex_loc, rgb);

                //ray.DrawRectangle(0,0,400,240,ray.WHITE);
                ray.DrawTexture(tex, 0, 0, ray.WHITE);
            },
            1 => {
                // This could probably be done in a GLSL shader with the page
                // vector passed in as a texture map
                for (vec[0..max_tiles], 0..) |v, i| {
                    const col: usize = i % tiles_per_row;
                    const row: usize = @divTrunc(i, tiles_per_row);
                    ray.DrawRectangle(
                        @intCast(col * tile_size),
                        @intCast(row * tile_size),
                        @intCast(tile_size),
                        @intCast(tile_size),
                        if (v & 0x1 == 1) ray.BLUE else ray.BLACK,
                    );
                }
            },
            2 => {
                // This could probably be done in a GLSL shader with the page
                // vector passed in as a texture map
                for (vec[0..max_tiles], 0..) |v, i| {
                    const col: usize = i % tiles_per_row;
                    const row: usize = @divTrunc(i, tiles_per_row);
                    ray.DrawTexture(
                        tile_tex,
                        @intCast(col * tile_size),
                        @intCast(row * tile_size),
                        if (v & 0x1 == 1) ray.BLUE else ray.BLACK,
                    );
                }
            },
            else => {},
        }

        ray.DrawTextureRec(
            outline_tex.texture,
            .{
                .x = 0.0,
                .y = 0.0,
                .width = @floatFromInt(outline_tex.texture.width),
                .height = @floatFromInt(-outline_tex.texture.height),
            },
            .{ .x = 0, .y = 0 },
            ray.WHITE,
        );
        //if (ray.IsCursorOnScreen()) {
        //    const mouse_x = ray.GetMouseX();
        //    const mouse_y = ray.GetMouseY();

        //    // Highlight Current Page
        //    const mouse_tile_x = @divFloor(@as(u64, @intCast(mouse_x)), tile_size);
        //    const mouse_tile_y = @divFloor(@as(u64, @intCast(mouse_y)), tile_size);

        //    const mouse_tile = mouse_tile_x + mouse_tile_y * tiles_per_row;

        //    if (mouse_tile_x < tiles_per_row and mouse_tile < max_tiles) {
        //        ray.DrawRectangle(
        //            @intCast(mouse_tile_x * tile_size),
        //            @intCast(mouse_tile_y * tile_size),
        //            @intCast(tile_size),
        //            @intCast(tile_size),
        //            .{ .r = 255, .g = 96, .b = 32, .a = 128 },
        //        );
        //    }
        //}

        ray.DrawFPS(10, 10);
        ray.EndDrawing();
    }
    return 0;
}
