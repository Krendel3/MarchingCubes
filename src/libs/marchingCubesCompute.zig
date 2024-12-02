const std = @import("std");
const gl = @import("zgl");
const shaders = @import("shaders.zig");
const glib = @import("glib.zig");
const int3 = glib.int3;
const vec3 = glib.vec3;
const main = @import("../main.zig");

const w = u8;//weight type
const point_axis = 24;
pub const point_chunk = point_axis * point_axis * point_axis;

const voxel_axis = point_axis - 1;
const voxel_chunk = voxel_axis * voxel_axis * voxel_axis;
const max_vertex_count = voxel_chunk * 9 * 5;

const chunkSize : f32 = 24;
//chunking
const weights_type = [point_chunk]w;
const MapType = std.AutoHashMap(int3, *chunkData); 
var weightMap : MapType = undefined;

//values

const seed = 28616;
const freqeuncy = 0.03;
const amplitude: f32 = 10;
pub const iso: w = 128;

//shader
pub var vao: gl.VertexArray = undefined;
var weight_buffer: gl.Buffer = undefined;
pub var vertex_buffer: gl.Buffer = undefined;
var vertex_counter_buffer: gl.Buffer = undefined;
var noise_shader: gl.Program = undefined;
var mesh_shader: gl.Program = undefined;
var allocator: *const std.mem.Allocator = undefined;
var arena : std.heap.ArenaAllocator = undefined;


//assign separate vao
pub const chunkData = struct {
    weights: weights_type = undefined,
    vertices: []f32 = undefined,
    const Self = @This();

    //dynamic/static read provides a major performace increase to my surprise
    pub fn bufferData(self: Self) !void {
        gl.namedBufferSubData(
            vertex_buffer,
            0,
            f32,
            @alignCast(self.vertices),
        );
    }
    pub fn draw(self : *Self) !void{
        try self.bufferData();
        gl.bindVertexArray(vao);
        gl.drawArrays(.triangles, 0, self.vertices.len);
    }

    pub fn free(self: Self) void {
        allocator.free(self.vertices);
    }
};
const marchError = error{
    noiseFailed,
    meshFailed,
};
pub fn updateChunk(chunk: *chunkData, chunkID: int3) !void {
    calculateWeights(chunkID);
    try getMeshIndirect(chunkID, chunk);
}
//radius is clamped to chunkSize
pub fn carve(point : glib.vec3,radius : f32, amount : w) void {
    _ = amount; //hardcode them in shader for now
    const chunks = getNearChunks(point, std.math.clamp(radius, 0.0001, chunkSize));
    
    for (0..27) |bit|{
        if (chunks >> @intCast(bit) & 1 == 0)continue;
        const c = index2coordS(bit, 3) - glib.splat(int3,1);
        _ = c;
        //std.debug.print("{d} \n",.{c});    
        // if(!weightMap.contains(c)) weightMap.put(c,undefined);
        // const ptr= weightMap.getPtr(c).?;
        // getWeights(c,ptr);
        // getMeshIndirect(c, ptr);
    }
}
pub fn getNearChunks(point : glib.vec3, radius : f32) u27{
    var result : u27 = 0;
    return 
    for (0..3) |x|{
    for (0..3) |y|{
    for (0..3) |z|{
        const chunk_off = i2v(@as(int3,@intCast(@Vector(3, usize){x,y,z})) - @as(int3,@splat(1))) * glib.splat(glib.vec3, radius);
        const id = std.math.floor((point + chunk_off) * glib.splat(glib.vec3,1/chunkSize)) + glib.splat(glib.vec3,1);
        result |= (@as(u27,1) << @as(u5,@intFromFloat(id[0] + (id[1] + id[2] * 3) * 3)));
    }}} else result;
}
pub fn getWeightsTerraform()void{}
pub fn setWeights(chunk: int3) void{
    if(weightMap.contains(chunk)){_ = 1;}
    else gl.namedBufferData(weight_buffer, u8, @alignCast(&([_]w{0} ** point_chunk)), .dynamic_draw);
}

pub fn calculateWeights(chunkID: int3) void {
    setWeights(chunkID);
    gl.useProgram(noise_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);

    const chunkIDF = i2v(chunkID);
    shaders.setAttribute(@as([]const [3]f32,(&chunkIDF)[0..1]), "chunkID", noise_shader, gl.uniform3fv);

    const group_count: c_uint = point_axis / 8;

    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);
    //main.debugTime();
}

pub fn getWeights(chunkID: int3, chunk : *chunkData) void {
    calculateWeights(chunkID);
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    const result = gl.mapBuffer(.shader_storage_buffer, w, .read_only);
    defer _ = gl.unmapBuffer(.shader_storage_buffer);
    @memcpy(chunk.weight,result);
    return result;
}

pub fn getMeshIndirect(chunkID: int3, chunk: *chunkData) !void {
    gl.useProgram(mesh_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);
    gl.bindBufferBase(.shader_storage_buffer, 1, vertex_buffer);
    gl.bindBufferBase(.atomic_counter_buffer, 2, vertex_counter_buffer);

    const chunkIDF = i2v(chunkID);
    shaders.setAttribute(@as([]const [3]f32,(&chunkIDF)[0..1]), "chunkID", mesh_shader, gl.uniform3fv);

    const group_count: c_uint = (voxel_axis + 7) / 8;
    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);
    gl.bindBuffer(vertex_counter_buffer, .atomic_counter_buffer);
    const tri_count = gl.mapBuffer(
        .atomic_counter_buffer,
        u32,
        .read_write,
    );

    const num = tri_count[0] * 9;
    tri_count[0] = 0;
    _ = gl.unmapNamedBuffer(vertex_counter_buffer);

    chunk.vertices = try allocator.alloc(f32, num);
    gl.binding.getNamedBufferSubData(@intFromEnum(vertex_buffer), 0, num * 4, chunk.vertices.ptr);
    //main.debugTime(); 
}
pub fn init(alloc: *const std.mem.Allocator) !void {
    //initialize the weight buffer
    weight_buffer = gl.genBuffer();
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    gl.bufferUninitialized(.shader_storage_buffer, w, point_chunk, .dynamic_read);

    //initialize the vertex buffer
    vertex_buffer = gl.genBuffer();
    gl.bindBuffer(vertex_buffer, .shader_storage_buffer);
    gl.bufferUninitialized(.shader_storage_buffer, [3]glib.vec3, voxel_chunk * 5, .dynamic_read);

    //initialize the atomic vertex counter buffer
    vertex_counter_buffer = gl.genBuffer();
    gl.bindBuffer(vertex_counter_buffer, .atomic_counter_buffer);
    gl.bufferUninitialized(.atomic_counter_buffer, c_uint, 1, .dynamic_read);

    allocator = alloc;
    arena = std.heap.ArenaAllocator.init(allocator.*);
    
    
    noise_shader = try shaders.computeProgramFromFile("marchNoise", allocator);
    mesh_shader = try shaders.computeProgramFromFile("marchMesh", allocator);

    // gl.useProgram(noise_shader);
    // var size_attrib = gl.getUniformLocation(noise_shader, "chunkSize");
    // gl.uniform1ui(size_attrib, @as(u32, point_axis));
    shaders.setAttribute(@as(u32, point_axis), "chunkSize", noise_shader,gl.uniform1ui);

    shaders.setAttribute(@as(u32, point_axis), "chunkSize", mesh_shader,gl.uniform1ui);

    vao = gl.genVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(vertex_buffer, .array_buffer);
    gl.vertexAttribPointer(0, 3, .float, false, 3 * 4, 0);
    gl.enableVertexAttribArray(0);

    weightMap = MapType.init(arena.allocator());

}
pub fn deinit() void {
    arena.deinit();
    weightMap.deinit();
}
pub fn i2v(i: int3) glib.vec3 {
    return glib.vec3{
        @floatFromInt(i[0]),
        @floatFromInt(i[1]),
        @floatFromInt(i[2]),
    };
}
fn index2coordS(i: usize, axis: usize) int3 {
    return .{
        @intCast(i % axis),
        @intCast(i / axis % axis),
        @intCast(i / (axis * axis) % axis),
    };
}
