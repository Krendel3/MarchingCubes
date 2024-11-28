const std = @import("std");
const gl = @import("zgl");
const shaders = @import("../shaders.zig");
const glib = @import("../glib.zig");
const int3 = glib.int3;
const vec3 = glib.vec3;
const lookup = @import("marchingTable.zig");

const point_axis = 24;
pub const point_chunk = point_axis * point_axis * point_axis;

pub const weight_type: type = u16; //reasonable types are u8,u16,u32
pub const num_bytes_weights = point_chunk * @sizeOf(weight_type);

const voxel_axis = point_axis - 1;
const voxel_chunk = voxel_axis * voxel_axis * voxel_axis;
const max_vertex_count = voxel_chunk * 9 * 5;

const chunkSize = 16.0; //physical dimensions of a chunk

//values
//pass to a shader
const seed = 28616;
const freqeuncy = 0.03;
const amplitude: f32 = 10;
pub const iso: f32 = 0.5;

//shader
pub var vao: gl.VertexArray = undefined;
var weight_buffer: gl.Buffer = undefined;
pub var vertex_buffer: gl.Buffer = undefined;
var vertex_counter_buffer: gl.Buffer = undefined;
var noise_shader: gl.Program = undefined;
var mesh_shader: gl.Program = undefined;
var allocator: *const std.mem.Allocator = undefined;

var chunk_id_uniform_noise: ?u32 = undefined;
var chunk_id_uniform_mesh: ?u32 = undefined;

//assign separate vao
pub const chunkData = struct {
    weights: [point_chunk]weight_type = undefined,
    vertices: []f32 = undefined,
    const Self = @This();
    pub fn bufferData(self: Self) !void {
        gl.namedBufferData(
            vertex_buffer,
            f32,
            @alignCast(self.vertices),
            .dynamic_copy,
        );
    }

    pub fn free(self: Self) void {
        allocator.free(self.vertices);
    }
};
const marchError = error{
    noiseFailed,
    meshFailed,
};
pub fn init(alloc: *const std.mem.Allocator) !void {
    //initialize the weight buffer
    weight_buffer = gl.genBuffer();
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    gl.bufferUninitialized(.shader_storage_buffer, weight_type, point_chunk, .dynamic_copy);

    //initialize the vertex buffer
    vertex_buffer = gl.genBuffer();
    gl.bindBuffer(vertex_buffer, .shader_storage_buffer);
    gl.bufferUninitialized(.shader_storage_buffer, [3]glib.vec3, voxel_chunk * 5, .dynamic_copy);

    //initialize the atomic vertex counter buffer
    vertex_counter_buffer = gl.genBuffer();
    gl.bindBuffer(vertex_counter_buffer, .atomic_counter_buffer);
    gl.bufferUninitialized(.atomic_counter_buffer, c_uint, 1, .dynamic_draw);

    allocator = alloc;
    noise_shader = try shaders.computeProgramFromFile("marchNoise", allocator);
    mesh_shader = try shaders.computeProgramFromFile("marchMesh", allocator);

    gl.useProgram(noise_shader);
    var size_attrib = gl.getUniformLocation(noise_shader, "chunkSize");
    gl.uniform1ui(size_attrib, @as(u32, point_axis));
    chunk_id_uniform_noise = gl.getUniformLocation(noise_shader, "chunkID");

    gl.useProgram(mesh_shader);
    size_attrib = gl.getUniformLocation(mesh_shader, "chunkSize");
    gl.uniform1ui(size_attrib, @as(u32, point_axis));
    chunk_id_uniform_mesh = gl.getUniformLocation(mesh_shader, "chunkID");

    vao = gl.genVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(vertex_buffer, .array_buffer);
    gl.vertexAttribPointer(0, 3, .float, false, 3 * 4, 0);
    gl.enableVertexAttribArray(0);

    gl.namedBufferData(vertex_buffer, f32, @alignCast(&([_]f32{0} ** max_vertex_count)), .dynamic_copy);
}
pub fn calculateWeights(chunk: int3) void {
    gl.namedBufferData(weight_buffer, weight_type, @alignCast(&([_]weight_type{0} ** point_chunk)), .dynamic_copy);
    gl.useProgram(noise_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);

    const chunkIDF = i2v(chunk);
    gl.uniform3f(chunk_id_uniform_noise, chunkIDF[0], chunkIDF[1], chunkIDF[2]);

    const group_count: c_uint = point_axis / 8;

    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);
}

pub fn getWeights(chunk: int3) []weight_type {
    calculateWeights(chunk);
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    const result = gl.mapBuffer(.shader_storage_buffer, weight_type, .read_only);
    return @as([]weight_type, @as([*]align(2) weight_type, @alignCast(result))[0..point_chunk]);
}
pub fn getMeshIndirect(chunkID: int3, chunk: *chunkData) !void {
    gl.namedBufferData(vertex_buffer, u8, @alignCast(&([_]u8{0} ** max_vertex_count)), .dynamic_copy);

    gl.useProgram(mesh_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);
    gl.bindBufferBase(.shader_storage_buffer, 1, vertex_buffer);
    gl.bindBufferBase(.atomic_counter_buffer, 2, vertex_counter_buffer);

    const chunkIDF = i2v(chunkID);
    gl.uniform3f(chunk_id_uniform_mesh, chunkIDF[0], chunkIDF[1], chunkIDF[2]);

    const group_count: c_uint = (voxel_axis + 7) / 8;
    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);

    gl.bindBuffer(vertex_counter_buffer, .atomic_counter_buffer);
    const tri_count = gl.mapBuffer(
        .atomic_counter_buffer,
        u32,
        .read_only,
    );

    const num = tri_count[0] * 9;
    if (num == 0) {
        //doesnt like me using defer for some reason????
        _ = gl.unmapNamedBuffer(vertex_counter_buffer);
        gl.namedBufferData(vertex_counter_buffer, u32, @alignCast(&([1]u32{0})), .dynamic_read);
        return;
    }
    std.debug.print("{d} \n", .{num});
    _ = gl.unmapNamedBuffer(vertex_counter_buffer);
    gl.namedBufferData(vertex_counter_buffer, u32, @alignCast(&([1]u32{0})), .dynamic_read);
    chunk.vertices = try allocator.alloc(f32, num);
    @memcpy(
        chunk.vertices[0..],
        @as([]align(4) f32, @alignCast(gl.mapNamedBufferRange(vertex_buffer, f32, 0, num, .{ .read = true }))),
    );
    //@as([*]align(1) T, @ptrCast(ptr))
    _ = gl.unmapNamedBuffer(vertex_buffer);
}

pub fn i2v(i: int3) glib.vec3 {
    return glib.vec3{
        @floatFromInt(i[0]),
        @floatFromInt(i[1]),
        @floatFromInt(i[2]),
    };
}
