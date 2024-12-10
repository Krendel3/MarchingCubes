const std = @import("std");

const glfw = @import("zglfw");
const gl = @import("zgl");
const zm = @import("zmath");

const march = @import("libs/marchingCubesCompute.zig");
const shaders = @import("libs/shaders.zig");
const glib = @import("libs/glib.zig");

const lvec2 = @Vector(2, f64);
// global

var window: *glfw.Window = undefined;

var camera_transform: glib.transform = .{ .pos = glib.vec3{ 12, 12, -4 } };
var camera_data: glib.cameraData = .{};
const player_speed: f32 = 30;
const mouse_sensitivity: f32 = 4;

//march
var march_shader: gl.Program = undefined;
var weights_buffer: gl.Buffer = undefined;
// const ch_dim = 3;
// var chunks = [_]march.chunkData{.{}} ** (ch_dim * ch_dim * ch_dim);

//mouse input
var mouse_pos: lvec2 = .{ 0, 0 };
var mouse_delta: glib.vec2 = .{ 0, 0 };

var cam_rotation_xy: glib.vec2 = .{ 0, 0 };

var light_dir = glib.normalize(glib.vec3{ 0.15, -0.4, 0.25 });
var first_frame = true;

//time
var timer: std.time.Timer = undefined;
var time: f64 = 0.0;
var prev_time: f64 = 0.0;
var delta_time: f64 = 0.0;
var frame_counter: u8 = 0;
var delta_sum: f64 = 0;
const fps_sample_count: u8 = 60;
var measure: f64 = 0;

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    window = try glfw.Window.create(2560, 1440, "march", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHintTyped(.context_version_major, gl_major);
    glfw.windowHintTyped(.context_version_minor, gl_minor);
    glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    glfw.windowHintTyped(.opengl_forward_compat, true);
    glfw.windowHintTyped(.client_api, .opengl_api);
    glfw.windowHintTyped(.doublebuffer, true);
    glfw.windowHintTyped(.center_cursor, true);

    try gl.loadExtensions(void, getProcAddressWrapper);

    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    march_shader = try shaders.shaderProgramFromFiles("simple", allocator);

    //lock and hide cursor
    window.setInputMode(.cursor, .disabled);

    //set the clockwise winding order
    gl.frontFace(.cw);

    //enable culling,depth testing
    gl.enable(.cull_face);
    gl.enable(.depth_test);
    gl.depthFunc(.less_or_equal);
    //vsync
    glfw.swapInterval(0);
    //const weights

    timer = try std.time.Timer.start();
    try march.init(allocator);
    defer march.deinit();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        //clear
        time = @as(f64, @floatFromInt(timer.read())) / @as(f64, @floatFromInt(std.time.ns_per_s));
        delta_time = time - prev_time;
        delta_sum += delta_time;

        prev_time = time;
        measure = time;
        frame_counter += 1;

        if (frame_counter >= fps_sample_count) try showFps();

        try playerLoop();

        try renderLoop();
    }
    //for (chunks) |ch| ch.free();
}
pub fn debugTime() void {
    const current = @as(f64, @floatFromInt(timer.read())) / @as(f64, @floatFromInt(std.time.ns_per_s));
    std.debug.print("{d} \n", .{(current - measure) * 1000});
    measure = current;
}
var testicle: f32 = 0;
fn playerLoop() !void {
    try march.loop(camera_transform.pos);

    //get mouse position and delta
    const y_rot_clamp: f32 = std.math.rad_per_deg * 90 - 0.001;
    handleMouseInput();
    try handleKeyInput();
    cam_rotation_xy = glib.vec2{
        std.math.clamp(cam_rotation_xy[0] + mouse_delta[1], -y_rot_clamp, y_rot_clamp),
        cam_rotation_xy[1] + mouse_delta[0],
    };

    camera_transform.setRot(glib.vec3{
        cam_rotation_xy[0],
        cam_rotation_xy[1],
        0,
    });
}
fn renderLoop() !void {
    const size = window.getSize();
    const aspect_ratio = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));

    const w2c = glib.getWorldToClipMatrix(camera_transform, .{}, aspect_ratio);

    //clear
    gl.clearColor(0.2, 0.2, 0.2, 1);
    gl.clear(.{ .color = true, .depth = true });

    //march
    gl.useProgram(march_shader);

    const march_matrix_attrib = gl.getUniformLocation(march_shader, "matrix");
    gl.binding.uniformMatrix4fv(@intCast(march_matrix_attrib.?), 1, gl.binding.TRUE, zm.arrNPtr(&w2c));

    //var iter = march.carve(camera_transform.pos, 12);
    //while (try iter.next()) |_| {}
    try march.drawChunks();

    window.swapBuffers();
}

fn handleKeyInput() !void {
    if (window.getKey(.t) == .press) light_dir = glib.as(camera_transform.viewDir(), glib.vec3);
    if (window.getKey(.q) == .press) {
        var iter = march.carve(camera_transform.pos, 12);
        while (try iter.next()) |c| {
            const ptr = march.chunk_map.getPtr(c) orelse break;
            try march.updateChunk(ptr, c);
        }
    }
    var y_offset: f32 = 0;
    var raw_move_dir: glib.vec3 = @splat(0);
    if (window.getKey(.w) == .press) raw_move_dir += glib.vec3{ 0.0, 0.0, 1.0 };
    if (window.getKey(.a) == .press) raw_move_dir += glib.vec3{ -1.0, 0.0, 0.0 };
    if (window.getKey(.s) == .press) raw_move_dir += glib.vec3{ 0.0, 0.0, -1.0 };
    if (window.getKey(.d) == .press) raw_move_dir += glib.vec3{ 1.0, 0.0, 0.0 };
    // get y rotation quaternion
    const quat = zm.quatFromRollPitchYaw(0, cam_rotation_xy[1], 0);
    // get new vector an vec4, not normalized
    const new_vec4 = zm.rotate(quat, glib.as(raw_move_dir, glib.vec4));
    //assign final dir
    const new_dir = glib.normalize(glib.as(new_vec4, glib.vec3));

    if (window.getKey(.space) == .press) y_offset += 1;
    if (window.getKey(.left_shift) == .press) y_offset += -1;
    camera_transform.pos += glib.scale(glib.vec3{ new_dir[0], y_offset, new_dir[2] }, player_speed * @as(f32, @floatCast(delta_time)));
}
fn handleMouseInput() void {
    const pos = window.getCursorPos();
    const size = window.getSize();
    const new_pos = pos / @as(lvec2, @splat(@as(f64, @floatFromInt(size[0]))));
    if (first_frame) {
        mouse_pos = new_pos;
        first_frame = false;
        return;
    }
    mouse_delta = @as(glib.vec2, @floatCast(new_pos - mouse_pos));
    mouse_pos = new_pos;
}
fn getProcAddressWrapper(comptime _: type, symbolName: [:0]const u8) ?*const anyopaque {
    return glfw.getProcAddress(symbolName);
}
fn showFps() !void {
    var buf: [64]u8 = undefined;
    const length = (try std.fmt.bufPrint(&buf, "fps: {d}, ms: {d}", .{ 1.0 / delta_sum * @as(f64, @floatFromInt(fps_sample_count)), 1000.0 * delta_sum / @as(f64, @floatFromInt(fps_sample_count)) })).len;
    buf[length] = 0;
    const sent: [:0]u8 = buf[0..length :0];
    window.setTitle(sent);
    frame_counter = 0;
    delta_sum = 0;
}
