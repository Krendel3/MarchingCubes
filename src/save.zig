const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zm = @import("zmath");

const shaders = @import("shaders.zig");
const glib = @import("glib.zig");
const march = @import("libs/marchingCubes.zig");

const gl = zopengl.wrapper;
const gl_b = zopengl.bindings;
const lvec2 = @Vector(2, f64);
// global

var window: *glfw.Window = undefined;

var camera_transform: glib.transform = .{ .pos = glib.vec3{ 0, 0, -4 } };
var camera_data: glib.cameraData = .{};
const player_speed: f32 = 0.2;
const mouse_sensitivity: f32 = 2;

var cube_transform: glib.transform = .{ .pos = .{ 0, 2, 0 } };
var program: gl.Program = undefined;
var vbo: gl.Buffer = undefined;
var vao: gl.VertexArrayObject = undefined;
var ibo: gl.Buffer = undefined;

//march
var march_vao: gl.VertexArrayObject = undefined;
var march_vbo: gl.Buffer = undefined;
var march_shader: gl.Program = undefined;
var verts: []f32 = undefined;

//mouse input
var mouse_pos: lvec2 = .{ 0, 0 };
var mouse_delta: glib.vec2 = .{ 0, 0 };

var cam_rotation_xy: glib.vec2 = .{ 0, 0 };

var lightDir = glib.normalize(glib.vec3{ 0.15, -0.4, 0.25 });
//glib.vec3{ -2, 0.5, -1.5 };
var first_frame = true;

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

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    gl.genVertexArray(&march_vao);
    defer gl.deleteVertexArray(&march_vao);
    gl.genBuffer(&march_vbo);
    defer gl.deleteBuffer(&march_vbo);

    gl.genVertexArray(&vao);
    defer gl.deleteVertexArray(&vao);
    gl.genBuffer(&vbo);
    defer gl.deleteBuffer(&vbo);
    gl.genBuffer(&ibo);
    defer gl.deleteBuffer(&ibo);
    //cube
    {
        gl.bindVertexArray(vao);
        defer gl.bindVertexArray(.{ .name = 0 });
        gl.bindBuffer(gl.BufferTarget.array_buffer, vbo);
        defer gl.bindBuffer(gl.BufferTarget.array_buffer, .{ .name = 0 });
        gl.bindBuffer(gl.BufferTarget.element_array_buffer, ibo);
        defer gl.bindBuffer(gl.BufferTarget.element_array_buffer, .{ .name = 0 });

        gl_b.bufferData(
            @as(c_uint, @intFromEnum(gl.BufferTarget.array_buffer)),
            @as(gl.Sizeiptr, @bitCast(@as(usize, @sizeOf(@TypeOf(vertices))))),
            &vertices,
            @intFromEnum(gl.BufferUsage.static_draw),
        );
        gl_b.bufferData(
            @as(c_uint, @intFromEnum(gl.BufferTarget.element_array_buffer)),
            @as(gl.Sizeiptr, indices.len),
            &indices,
            @intFromEnum(gl.BufferUsage.static_draw),
        );

        //postions
        gl.vertexAttribPointer(.{ .location = 0 }, 3, gl.VertexAttribType.float, gl.FALSE, 6 * @sizeOf(f32), 0);

        //normals
        gl.vertexAttribPointer(.{ .location = 1 }, 3, gl.VertexAttribType.float, gl.FALSE, 6 * @sizeOf(f32), 3 * @sizeOf(f32));

        gl_b.enableVertexAttribArray(0);
        gl_b.enableVertexAttribArray(1);
    }
    //march
    {
        gl.bindVertexArray(march_vao);
        defer gl.bindVertexArray(.{ .name = 0 });
        gl.bindBuffer(gl.BufferTarget.array_buffer, march_vbo);
        defer gl.bindBuffer(gl.BufferTarget.array_buffer, .{ .name = 0 });

        gl_b.bufferData(
            @as(c_uint, @intFromEnum(gl.BufferTarget.array_buffer)),
            @as(gl.Sizeiptr, @bitCast(verts.len * 4)),
            verts.ptr,
            @intFromEnum(gl.BufferUsage.static_draw),
        );
        gl.vertexAttribPointer(.{ .location = 0 }, 3, gl.VertexAttribType.float, gl.FALSE, 3 * @sizeOf(f32), 0);
        gl_b.enableVertexAttribArray(0);
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    program = .{ .name = try shaders.shaderProgramFromFiles("triangle", allocator) };
    march_shader = .{ .name = try shaders.shaderProgramFromFiles("simple", allocator) };

    //lock and hide cursor
    window.setInputMode(.cursor, .disabled);

    //set the clockwise winding order
    gl.frontFace(.cw);

    //enable culling,depth testing
    gl.enable(.cull_face);
    //gl.enable(.depth_test);

    //vsync
    glfw.swapInterval(1);
    //const weights
    //std.debug.print("{d} \n", .{verts.len});
    while (!window.shouldClose()) {
        glfw.pollEvents();
        //clear
        try playerLoop();
        renderLoop();
    }
}
var testicle: f32 = 0;

fn playerLoop() !void {
    //timer.reset();timer

    var timer = try std.time.Timer.start();
    const ptr = &(march.getWeights(.{ @intFromFloat(testicle), 0, 0 }));
    const noise_time = @as(f32, @floatFromInt(timer.read())) / @as(f32, @floatFromInt(std.time.ns_per_ms));
    timer.reset();
    verts = march.constructMesh(ptr);
    std.debug.print("noise - {d}, mesh - {d}\n", .{ noise_time, @as(f32, @floatFromInt(timer.read())) / @as(f32, @floatFromInt(std.time.ns_per_ms)) });
    {
        gl.bindVertexArray(march_vao);
        defer gl.bindVertexArray(.{ .name = 0 });
        gl.bindBuffer(gl.BufferTarget.array_buffer, march_vbo);
        defer gl.bindBuffer(gl.BufferTarget.array_buffer, .{ .name = 0 });

        gl_b.bufferData(
            @as(c_uint, @intFromEnum(gl.BufferTarget.array_buffer)),
            @as(gl.Sizeiptr, @bitCast(verts.len * 4)),
            verts.ptr,
            @intFromEnum(gl.BufferUsage.static_draw),
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
    gl_b.clearBufferfv(gl.COLOR, 0, &@as([4]f32, @splat(0.2)));
    gl_b.clear(gl.DEPTH_BUFFER_BIT);

    //cube
    gl.useProgram(program);

    const matrix_attrib = gl.getUniformLocation(program, "matrix");
    if (matrix_attrib != null) gl.uniformMatrix4fv(matrix_attrib.?, 1, gl.TRUE, zm.arrNPtr(&world_to_clip));

    const light_dir_attrib = gl.getUniformLocation(program, "lightDir");
    if (light_dir_attrib != null) gl.uniform3f(light_dir_attrib.?, lightDir[0], lightDir[1], lightDir[2]);

    const cam_pos_attrib = gl.getUniformLocation(program, "camPos");
    if (cam_pos_attrib != null) gl.uniform3f(cam_pos_attrib.?, camera_transform.pos[0], camera_transform.pos[1], camera_transform.pos[2]);

    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.BufferTarget.element_array_buffer, ibo);
    gl_b.drawElements(@intFromEnum(gl.PrimitiveType.triangles), indices.len, gl_b.UNSIGNED_BYTE, null);
    // //march
    gl.useProgram(march_shader);

    const march_matrix_attrib = gl.getUniformLocation(march_shader, "matrix");
    if (march_matrix_attrib != null) gl.uniformMatrix4fv(march_matrix_attrib.?, 1, gl.TRUE, zm.arrNPtr(&w2c));

    gl.bindVertexArray(march_vao);
    gl.drawArrays(gl.PrimitiveType.triangles, 0, @intCast(verts.len));
    // gl_b.drawArrays;
    window.swapBuffers();
}

fn handleKeyInput() callconv(.C) void {
    if (window.getKey(.t) == .press) lightDir = glib.as(camera_transform.viewDir(), glib.vec3);
    if (window.getKey(.q) == .press) testicle += 0.1;
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
    camera_transform.pos += glib.scale(glib.vec3{ new_dir[0], y_offset, new_dir[2] }, player_speed);
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
