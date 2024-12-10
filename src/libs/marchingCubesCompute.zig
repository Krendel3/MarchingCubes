const std = @import("std");
const gl = @import("zgl");
const shaders = @import("shaders.zig");
const glib = @import("glib.zig");
const int3 = glib.int3;
const vec3 = glib.vec3;
const main = @import("../main.zig");

const w = u8; //weight type
const point_axis = 24;
pub const point_chunk = point_axis * point_axis * point_axis;

const voxel_axis = point_axis - 1;
const voxel_chunk = voxel_axis * voxel_axis * voxel_axis;
const max_vertex_count = voxel_chunk * 9 * 5;

const chunk_size: f32 = 32;
//chunking
var weight_map: std.AutoHashMap(int3, []align(1) w) = undefined;
pub var chunk_map: std.AutoHashMap(int3, chunkData) = undefined;
const render_distance: u8 = 5;
var offsets: []int3 = undefined;
const max_updates_per_frame = 3;

const seed = 28616;
const freqeuncy = 0.03;
const amplitude: f32 = 10;
pub const iso: w = 128;

//shader
var vao: gl.VertexArray = undefined;
var weight_buffer: gl.Buffer = undefined;
var vertex_buffer: gl.Buffer = undefined;
var vertex_counter_buffer: gl.Buffer = undefined;

var noise_shader: gl.Program = undefined;
var mesh_shader: gl.Program = undefined;
var terraform_shader: gl.Program = undefined;

var allocator: std.mem.Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;

pub const ChunkIdIterator = struct {
    bitmask: u8,
    corner_id: int3,
    var index: u8 = 0;

    const Self = @This();
    pub fn next(self: *Self) !?int3 {
        while (self.bitmask >> @truncate(index) & 1 == 0) {
            if (index >= 7) {
                index = 0;
                return null;
            }
            index += 1;
        }
        if (index > 7) {
            index = 0;
            return null;
        }
        defer index += 1;
        const c = index2coordS(index, 2) + self.corner_id;
        try getWeightsTerraform(c);
        return c;
    }
};

//assign separate vao
pub const chunkData = struct {
    vertices: []f32 = undefined,
    const Self = @This();

    pub fn bufferData(self: Self) !void {
        gl.namedBufferSubData(
            vertex_buffer,
            0,
            f32,
            @alignCast(self.vertices),
        );
    }
    pub fn draw(self: Self) !void {
        if (self.vertices.len > max_vertex_count) return;
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
pub fn loop(player_pos: vec3) !void {
    const player_coord = v2i(player_pos * glib.splat(vec3, 1.0 / chunk_size));
    var count: u32 = 0;

    for (offsets) |c| {
        const global = c + player_coord;
        const ptr = chunk_map.getPtr(global);
        if (ptr == null) {
            try chunk_map.put(global, .{});

            const new_ptr = chunk_map.getPtr(global).?;
            try updateChunk(new_ptr, global);
            count += 1;
            if (count >= max_updates_per_frame) break;
            //stop after a couple of chunks were updated
        }
    }

    var to_delete = std.ArrayList(int3).init(allocator);
    defer to_delete.deinit();

    var iter = chunk_map.iterator();
    //leave onle chunk_map remove active_chunks
    while (iter.next()) |c| {
        const cid = c.key_ptr.*;
        if (glib.sqrMagnitude(cid - player_coord) > render_distance * render_distance * 2) {
            try to_delete.append(cid);
        }
    }
    for (to_delete.items) |c| {
        _ = chunk_map.remove(c);
    }
}
pub fn drawChunks() !void {
    var iter = chunk_map.iterator();
    var count: usize = 0;
    while (iter.next()) |c| {
        try c.value_ptr.*.draw();
        count += 1;
    }
    std.debug.print("{d} = tris {d} \n", .{ count, offsets.len });
}
pub fn updateChunk(chunk: *chunkData, chunkID: int3) !void {
    setWeights(chunkID);
    try getMeshIndirect(chunkID, chunk);
}
//radius is clamped to chunkSize
//should return chunkIDS of meshes that can be updated should be free by the reciever
pub fn carve(point: glib.vec3, radius: f32) ChunkIdIterator {
    shaders.setAttribute(@as([]const [3]f32, (&point)[0..1]), "point", terraform_shader, gl.uniform3fv);
    shaders.setAttribute(@as(f32, radius), "radius", terraform_shader, gl.uniform1f);

    const bitmask = getNearChunks(point, std.math.clamp(radius, 0.0001, chunk_size * 0.5 - 0.0001));
    const cid = v2i((point - glib.splat(vec3, radius)) / glib.splat(vec3, chunk_size));

    return ChunkIdIterator{ .bitmask = bitmask, .corner_id = cid };
}
// could support any radius if i really wanted
pub fn getNearChunks(point: glib.vec3, radius: f32) u8 {
    var result: u8 = 0;
    const corner = point - glib.splat(vec3, radius);
    const corner_id = (std.math.floor((corner) / glib.splat(vec3, chunk_size)));
    return for (0..2) |x| {
        for (0..2) |y| {
            for (0..2) |z| {
                const id_offset = i2v(@as(int3, @intCast(@Vector(3, usize){ x, y, z })));
                const new_pos = corner + id_offset * glib.splat(vec3, chunk_size);
                const new_id = (std.math.floor((new_pos) / glib.splat(vec3, chunk_size)));
                const id = new_id - corner_id;
                result |= (@as(u8, 1) << @as(u3, @intFromFloat(id[0] + (id[1] + id[2] * 2) * 2)));
            }
        }
    } else result;
}
pub fn getWeightsTerraform(chunkID: int3) !void {
    setWeights(chunkID);
    gl.useProgram(terraform_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);
    const chunkIDF = i2v(chunkID);
    shaders.setAttribute(@as([]const [3]f32, (&chunkIDF)[0..1]), "chunkID", terraform_shader, gl.uniform3fv);

    const group_count: c_uint = point_axis / 8;

    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);

    try putInWeightMap(chunkID, gl.mapBuffer(.shader_storage_buffer, w, .read_only));

    _ = gl.unmapBuffer(.shader_storage_buffer);
}
fn putInWeightMap(chunkID: int3, weights: [*]w) !void {
    const grp = try weight_map.getOrPut(chunkID);
    if (!grp.found_existing) grp.value_ptr.* = try arena.allocator().alloc(w, point_chunk);
    @memcpy(grp.value_ptr.*, weights);
}
pub fn clearWeights() void {
    gl.namedBufferData(weight_buffer, w, @alignCast(&([_]w{0} ** point_chunk)), .dynamic_draw);
}
pub fn setWeights(chunkID: int3) void {
    if (weight_map.get(chunkID)) |weights| {
        gl.namedBufferData(weight_buffer, w, @constCast(weights), .dynamic_draw);
    } else calculateWeights(chunkID);
}

pub fn calculateWeights(chunkID: int3) void {
    clearWeights();
    gl.useProgram(noise_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);

    const chunkIDF = i2v(chunkID);
    shaders.setAttribute(@as([]const [3]f32, (&chunkIDF)[0..1]), "chunkID", noise_shader, gl.uniform3fv);

    const group_count: c_uint = point_axis / 8;

    gl.binding.dispatchCompute(group_count, group_count, group_count);
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);
}

pub fn getWeights(chunkID: int3, chunk: *chunkData) void {
    calculateWeights(chunkID);
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    const result = gl.mapBuffer(.shader_storage_buffer, w, .read_only);
    defer _ = gl.unmapBuffer(.shader_storage_buffer);
    @memcpy(&chunk.weights, result);
}

pub fn getMeshIndirect(chunkID: int3, chunk: *chunkData) !void {
    gl.useProgram(mesh_shader);
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);
    gl.bindBufferBase(.shader_storage_buffer, 1, vertex_buffer);
    gl.bindBufferBase(.atomic_counter_buffer, 2, vertex_counter_buffer);

    const chunkIDF = i2v(chunkID);
    shaders.setAttribute(@as([]const [3]f32, (&chunkIDF)[0..1]), "chunkID", mesh_shader, gl.uniform3fv);

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
pub fn init(alloc: std.mem.Allocator) !void {
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
    arena = std.heap.ArenaAllocator.init(allocator);

    noise_shader = try shaders.computeProgramFromFile("marchNoise", allocator);
    mesh_shader = try shaders.computeProgramFromFile("marchMesh", allocator);
    terraform_shader = try shaders.computeProgramFromFile("marchTerraform", allocator);

    shaders.setAttribute(@as(u32, point_axis), "pointsChunk", noise_shader, gl.uniform1ui);
    shaders.setAttribute(@as(u32, point_axis), "pointsChunk", mesh_shader, gl.uniform1ui);
    shaders.setAttribute(@as(u32, point_axis), "pointsChunk", terraform_shader, gl.uniform1ui);

    shaders.setAttribute(chunk_size, "chunkSize", noise_shader, gl.uniform1f);
    shaders.setAttribute(chunk_size, "chunkSize", mesh_shader, gl.uniform1f);
    shaders.setAttribute(chunk_size, "chunkSize", terraform_shader, gl.uniform1f);

    vao = gl.genVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(vertex_buffer, .array_buffer);
    gl.vertexAttribPointer(0, 3, .float, false, 3 * 4, 0);
    gl.enableVertexAttribArray(0);

    weight_map = @TypeOf(weight_map).init(arena.allocator());
    chunk_map = @TypeOf(chunk_map).init(arena.allocator());
    offsets = try bakeOffsets(render_distance);
}

pub fn deinit() void {
    arena.deinit();
    weight_map.deinit();
    chunk_map.deinit();
}
pub fn i2v(i: int3) glib.vec3 {
    return glib.vec3{
        @floatFromInt(i[0]),
        @floatFromInt(i[1]),
        @floatFromInt(i[2]),
    };
}
pub fn v2i(i: vec3) int3 {
    return int3{
        @intFromFloat(i[0]),
        @intFromFloat(i[1]),
        @intFromFloat(i[2]),
    };
}
fn index2coordS(i: usize, axis: usize) int3 {
    return .{
        @intCast(i % axis),
        @intCast(i / axis % axis),
        @intCast(i / (axis * axis) % axis),
    };
}
pub fn bakeOffsets(rd: u8) ![]int3 {
    var list = std.ArrayList(int3).init(arena.allocator());
    const ird = @as(i32, @intCast(rd));

    for (0..rd * 2 + 1) |z| {
        for (0..rd * 2 + 1) |y| {
            for (0..rd * 2 + 1) |x| {
                const id = int3{ @as(i32, @intCast(x)) - ird, @as(i32, @intCast(y)) - ird, @as(i32, @intCast(z)) - ird };

                if (glib.sqrMagnitude(id) <= @as(i32, @intCast(rd * rd))) {
                    try list.append(id);
                }
            }
        }
    }
    //comptime lessThanFn: fn(@TypeOf(context), lhs:T, rhs:T)bool
    std.mem.sort(int3, list.items, {}, struct {
        pub fn less(ctx: void, l: int3, r: int3) bool {
            _ = ctx;
            return glib.sqrMagnitude(l) < glib.sqrMagnitude(r);
        }
    }.less);
    return list.items;
}
