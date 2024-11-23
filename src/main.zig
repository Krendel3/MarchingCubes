const std = @import("std");

const glfw = @import("zglfw");
const gl = @import("zgl");
const zm = @import("zmath");

const marchCompute = @import("libs/marchingCubesCompute.zig");
const shaders = @import("shaders.zig");
const glib = @import("glib.zig");

const lvec2 = @Vector(2, f64);
// global

var window: *glfw.Window = undefined;

var camera_transform: glib.transform = .{ .pos = glib.vec3{ 0, 0, -4 } };
var camera_data: glib.cameraData = .{};
const player_speed: f32 = 30;
const mouse_sensitivity: f32 = 4;

var cube_transform: glib.transform = .{ .pos = .{ 0, 0, 0 } };
var program: gl.Program = undefined;
var vbo: gl.Buffer = undefined;
var vao: gl.VertexArray = undefined;
var ibo: gl.Buffer = undefined;

//march
var march_vao: gl.VertexArray = undefined;
var march_vbo: gl.Buffer = undefined;
var march_shader: gl.Program = undefined;
var weights_buffer: gl.Buffer = undefined;
//mouse input
var mouse_pos: lvec2 = .{ 0, 0 };
var mouse_delta: glib.vec2 = .{ 0, 0 };

var cam_rotation_xy: glib.vec2 = .{ 0, 0 };

var light_dir = glib.normalize(glib.vec3{ 0.15, -0.4, 0.25 });
var first_frame = true;

//time
var time: f64 = 0.0;
var prev_time: f64 = 0.0;
var delta_time: f64 = 0.0;
var frame_counter: u8 = 0;
var delta_sum: f64 = 0;
const fps_sample_count: u8 = 60;

const vertices = [_]f32{
    //front verts
    0.5, 0.5, 0, //tr
    0, 1, 0, //top normal
    0.5, -0.5, 0, //br
    0, 0, -1, //front normal
    -0.5, 0.5, 0, //tl
    0, 0, 0, //unused normal
    -0.5, -0.5, 0, //bl
    -1, 0, 0, //left normal
    //back verts
    0.5, 0.5, 1, //tr
    1, 0, 0, //right normal
    0.5, -0.5, 1, //br
    0, 0, 0, //unused normal
    -0.5, 0.5, 1, //tl
    0, 0, 1, //back normal
    -0.5, -0.5, 1, //bl
    0, -1, 0, //bottom normal
};

const indices = [_]u8{
    //front
    2, 0, 1,
    3, 2, 1,
    //back
    5, 4, 6,
    7, 5, 6,
    //top
    6, 4, 0,
    2, 6, 0,
    //bottom
    1, 5, 7,
    3, 1, 7,
    //left
    6, 2, 3,
    7, 6, 3,
    //right
    1, 0, 4,
    5, 1, 4,
};

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

    march_vao = gl.genVertexArray();
    defer gl.deleteVertexArray(march_vao);
    march_vbo = gl.genBuffer();
    defer gl.deleteBuffer(march_vbo);

    vao = gl.genVertexArray();
    defer gl.deleteVertexArray(vao);
    vbo = gl.genBuffer();
    defer gl.deleteBuffer(vbo);
    ibo = gl.genBuffer();
    defer gl.deleteBuffer(ibo);

    //cube
    {
        gl.bindVertexArray(vao);
        defer gl.bindVertexArray(.invalid);
        gl.bindBuffer(vbo, .array_buffer);
        defer gl.bindBuffer(.invalid, .array_buffer);
        gl.bindBuffer(ibo, .element_array_buffer);
        defer gl.bindBuffer(.invalid, .element_array_buffer);

        gl.bufferData(
            .array_buffer,
            f32,
            @as([]align(1) const f32, try std.math.alignCast(1, vertices[0..])),
            .static_draw,
        );
        gl.bufferData(
            .element_array_buffer,
            u8,
            @as([]align(1) const u8, try std.math.alignCast(1, indices[0..])),
            .static_draw,
        );

        //positions
        gl.vertexAttribPointer(0, 3, .float, false, 6 * 4, 0);
        //normals
        gl.vertexAttribPointer(1, 3, .float, false, 6 * 4, 3 * 4);

        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
    }
    //march
    {
        gl.bindVertexArray(march_vao);
        defer gl.bindVertexArray(.invalid);
        gl.bindBuffer(march_vbo, .array_buffer);
        defer gl.bindBuffer(.invalid, .array_buffer);

        gl.vertexAttribPointer(0, 3, .half_float, false, 3 * 2, 0);
        gl.enableVertexAttribArray(0);
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    program = try shaders.shaderProgramFromFiles("triangle", &allocator);
    march_shader = try shaders.shaderProgramFromFiles("simple", &allocator);

    //lock and hide cursor
    window.setInputMode(.cursor, .disabled);

    //set the clockwise winding order
    gl.frontFace(.cw);

    //enable culling,depth testing
    gl.enable(.cull_face);
    //gl.enable(.depth_test);

    //vsync
    glfw.swapInterval(0);
    //const weights
    //std.debug.print("{d} \n", .{verts.len});

    var timer = try std.time.Timer.start();

    try marchCompute.init(&allocator);
    while (!window.shouldClose()) {
        glfw.pollEvents();
        //clear
        time = @as(f64, @floatFromInt(timer.read())) / @as(f64, @floatFromInt(std.time.ns_per_s));
        delta_time = time - prev_time;
        delta_sum += delta_time;

        prev_time = time;
        frame_counter += 1;

        if (frame_counter >= fps_sample_count) try showFps();

        try playerLoop();
        renderLoop();
    }
}
var testicle: f32 = 0;
var march_verts: usize = 0;

fn playerLoop() !void {
    const weights = marchCompute.getWeights(.{ 0, 0, 0 });
    const verts: []f16 = marchCompute.constructMesh(weights);
    march_verts = verts.len;
    {
        gl.bindVertexArray(march_vao);
        defer gl.bindVertexArray(.invalid);
        gl.bindBuffer(march_vbo, .array_buffer);
        defer gl.bindBuffer(.invalid, .array_buffer);

        gl.bufferData(
            .array_buffer,
            f16,
            @as([]align(1) const f16, (try std.math.alignCast(1, verts.ptr))[0..verts.len]),
            .static_draw,
        );
    }
    //get mouse position and delta
    const y_rot_clamp: f32 = std.math.rad_per_deg * 90 - 0.001; // -epsilon
    handleMouseInput();
    handleKeyInput();
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
fn renderLoop() void {
    const size = window.getSize();
    const aspect_ratio = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1]));

    const w2c = glib.getWorldToClipMatrix(camera_transform, .{}, aspect_ratio);
    const world_to_clip = zm.mul(
        cube_transform.modelMatrix(),
        w2c,
    );

    //clear
    gl.clearColor(0.2, 0.2, 0.2, 1);
    gl.clear(.{ .color = true });

    //cube
    gl.useProgram(program);

    const matrix_attrib = gl.getUniformLocation(program, "matrix");
    gl.binding.uniformMatrix4fv(@intCast(matrix_attrib.?), @as(gl.SizeI, @intCast(1)), gl.binding.TRUE, zm.arrNPtr(&world_to_clip));

    const light_dir_attrib = gl.getUniformLocation(program, "lightDir");
    gl.uniform3fv(light_dir_attrib, &.{light_dir});

    const cam_pos_attrib = gl.getUniformLocation(program, "camPos");
    gl.uniform3fv(cam_pos_attrib, &.{camera_transform.pos});

    gl.bindVertexArray(vao);
    gl.bindBuffer(ibo, .element_array_buffer);
    gl.drawElements(.triangles, indices.len, .unsigned_byte, 0);
    //march
    gl.useProgram(march_shader);

    const march_matrix_attrib = gl.getUniformLocation(march_shader, "matrix");
    gl.binding.uniformMatrix4fv(@intCast(march_matrix_attrib.?), @as(gl.SizeI, @intCast(1)), gl.binding.TRUE, zm.arrNPtr(&w2c));

    gl.bindVertexArray(march_vao);
    gl.drawArrays(.triangles, 0, march_verts);
    window.swapBuffers();
}

fn handleKeyInput() void {
    if (window.getKey(.t) == .press) light_dir = glib.as(camera_transform.viewDir(), glib.vec3);
    if (window.getKey(.q) == .press) testicle += 0.01;
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
