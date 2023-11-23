const std = @import("std");

const ray = @cImport(
{
//    @cDefine("GRAPHICS_API_OPENGL_43", "1");
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
}
);
//const rlgl = @cImport(
//};
// RayLib uses normalized textures, GL_R
// only for SSBO does it pass RL_R8UI
// https://www.khronos.org/opengl/wiki/Image_Format
const shader_glsl = 
    \\#version 430
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\uniform sampler2D rgba_tex;
    \\
    \\out vec4 finalColor;
    \\
    \\layout(std430, binding = 1) readonly restrict buffer data
    \\{
    \\    uint dataArray[];
    \\};
    \\uniform uint size;
    \\
    \\void main() {
    \\
    \\vec4 rgba = texelFetch(rgba_tex, ivec2(1,0), 0);
    //\\vec4 rgba = texture(rgba_tex, fragTexCoord);
    \\rgba.a = 1.0;
    \\ivec2 tex_size = textureSize(rgba_tex, 0);
    \\ivec4 rgba8 = ivec4(round(rgba*255));
    \\
    \\finalColor = vec4(0.0, 0.0, 0.0, 1.0);
    //\\finalColor = rgba;
    // If we pass u8's we need to shift the GLSL uint to get the u8
    \\if (((dataArray[0] >> 24 ) & 255) == 3) finalColor.r = 1;
    \\if (((dataArray[0] >> 16 ) & 255) == 2) finalColor.g = 1;
    \\if (((dataArray[0] >> 8 ) & 255) == 1) finalColor.b = 1;
    \\if (((dataArray[0] >> 0 ) & 255) == 0) finalColor.b = 1;
    \\if ((dataArray[2] & 255 ) == 2) finalColor.b = 1;
    //\\if (((dataArray[2] >> 8) & 255) == 2) finalColor.g = 1;
    //\\if (((dataArray[3] >> 16) & 255) == 3) finalColor.b = 1;
    \\}
;

const res_x = 400;
const res_y = 240;
const tile_size = 20;

const tile_pad = if (tile_size < 16) 1 else 0;
const tiles_per_row = @divExact(res_x, tile_size);
const tiles_per_col = @divExact(res_y, tile_size);
const max_tiles = tiles_per_row * tiles_per_col;

pub fn main() !u8 {

    // Setup Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();
    const vec = try allocator.alloc(u8, max_tiles);
    defer allocator.free(vec);

    for (vec, 0..) |*v, i| {
        v.* = @intCast(@mod(i, 256));
    }

    ///////////////////////////////////////////////////////////////////////////
    // Init Raylib Window
    ray.SetTraceLogLevel(0);
    ray.SetTargetFPS(60);
    ray.InitWindow(@intCast(res_x), @intCast(res_y), "Buffy");
    defer ray.CloseWindow();
    
    const img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    //ray.ImageFormat(&img, ray.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    const tex = ray.LoadTextureFromImage(img);
    defer ray.UnloadTexture(tex);
    ray.UnloadImage(img);

    //const img_rgb = ray.GenImageColor(16, 16, ray.WHITE);
    //const rgb = ray.LoadTextureFromImage(img_rgb);
    //ray.UnloadImage(img_rgb);
    const rgb = ray.LoadTexture("r8g8b8.png");
    defer ray.UnloadTexture(rgb);
    //const rgba = ray.LoadTexture("r8g8b8a8.png");
    //const grayscale = ray.LoadTexture("grayscale.png");
    ray.SetTextureFilter(rgb, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(rgb, ray.TEXTURE_WRAP_CLAMP);
    //std.log.info("{} {} {}", .{ rgb.format, rgba.format, grayscale.format });
    std.log.info("{} {} {}", .{ rgb.width, rgb.height, rgb.id });

    const shader = ray.LoadShaderFromMemory(null, shader_glsl);
    defer ray.UnloadShader(shader);

    const rgba_tex_loc = ray.GetShaderLocation(shader, "rgba_tex");

    var data = [_]u8{0,1,2,3,4,5,6,7,8,9,10,11};
    var data2 = [_]u8{0}**12;
    const ssbo = ray.rlLoadShaderBuffer(@sizeOf(@TypeOf(data)), &data, ray.RL_DYNAMIC_DRAW);
    ray.rlReadShaderBuffer(ssbo, &data2, 1, 0);
    ray.rlUpdateShaderBuffer(ssbo, &data, @sizeOf(@TypeOf(data)), 0);
    std.log.info("hmm {} {}", .{ssbo, data2[0]});
    std.log.info("{} {}", .{@sizeOf(@TypeOf(data)), ray.rlGetShaderBufferSize(ssbo)});
    defer ray.rlUnloadShaderBuffer(ssbo);
    // Main Loop
    while (!ray.WindowShouldClose()) {
        
        ray.rlBindShaderBuffer(ssbo, 1);
        
        ray.BeginDrawing();

        ray.ClearBackground(ray.BLACK);

        {
            ray.BeginShaderMode(shader);
            ray.SetShaderValueTexture(shader, rgba_tex_loc, rgb); 
            defer ray.EndShaderMode();
            //ray.DrawRectangle(0,0,400,240,ray.WHITE);
            ray.DrawTexture(tex, 0, 0, ray.WHITE);
        }
        // This could probably be done in a GLSL shader with the page
        // vector passed in as a texture map
        //for (vec[0..max_tiles], 0..) |v, i| {
        //    const col: usize = i % tiles_per_row;
        //    const row: usize = @divTrunc(i, tiles_per_row);
        //    ray.DrawRectangle(
        //        @intCast(col * tile_size),
        //        @intCast(row * tile_size),
        //        @intCast(tile_size),
        //        @intCast(tile_size),
        //        if (v & 0x1 == 1) (if (row & 0x1 == 1) ray.BLUE else ray.GREEN) else ray.WHITE,
        //    );
        //    if (tile_size > 3) {
        //        ray.DrawRectangleLines(
        //            @intCast(col * tile_size),
        //            @intCast(row * tile_size),
        //            @intCast(tile_size + tile_pad),
        //            @intCast(tile_size + tile_pad),
        //            ray.GRAY,
        //        );
        //    }
        //}

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

        //ray.DrawFPS(10, 10);
        ray.EndDrawing();
    }
    return 0;
}
