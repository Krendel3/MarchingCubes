const std = @import("std");
const gl = @import("zgl");
const glib = @import("../glib.zig");
const lookup = @import("marchingTable.zig");
const short3 = @Vector(3, f16);
const point_axis = 24;
pub const point_chunk = point_axis * point_axis * point_axis;
pub const weight_buffer_size = point_axis * point_axis * point_axis / 4;

const voxel_axis = point_axis - 1;
const voxel_chunk = voxel_axis * voxel_axis * voxel_axis;

const chunkSize = 16;

const chunkWeights = [point_chunk]u8;
//noise data

//values
const powers2 = computePowers();
const seed = 28616;
const freqeuncy = 0.03;
const amplitude: f16 = 10;
pub const iso: u8 = 128;

//shader
var weight_buffer: gl.Buffer = undefined;
var noise_shader: gl.Program = undefined;
var allocator: *const std.mem.Allocator = undefined;
var empty: [weight_buffer_size]u32 = undefined;

var chunk_id_uniform: ?u32 = undefined;

const marchError = error{
    noiseFailed,
};
pub fn init(alloc: *const std.mem.Allocator) !void {
    weight_buffer = gl.genBuffer();
    gl.bindBuffer(weight_buffer, .shader_storage_buffer);
    defer gl.bindBuffer(.invalid, .shader_storage_buffer);
    gl.bufferData(
        .shader_storage_buffer,
        u32,
        @as([]align(1) const u32, try std.math.alignCast(1, empty[0..])),
        .dynamic_copy,
    );
    allocator = alloc;
    noise_shader = try @import("../shaders.zig").computeProgramFromFile("marchNoise", allocator);

    gl.useProgram(noise_shader);
    const size_attrib = gl.getUniformLocation(noise_shader, "chunkSize");
    gl.uniform1ui(size_attrib, @as(u32, point_axis));
    chunk_id_uniform = gl.getUniformLocation(noise_shader, "chunkID");
}
pub fn getWeights(chunk: glib.int3) []u8 {
    gl.bindBufferBase(.shader_storage_buffer, 0, weight_buffer);
    gl.useProgram(noise_shader);

    const chunkIDF = i2v(chunk);
    gl.uniform3f(chunk_id_uniform, chunkIDF[0], chunkIDF[1], chunkIDF[2]);

    const group_count: c_uint = point_axis / 8;
    gl.binding.dispatchCompute(group_count, group_count, group_count);
    //wait for execution to finish
    gl.binding.memoryBarrier(gl.binding.SHADER_STORAGE_BARRIER_BIT);

    const result = gl.mapBufferRange(
        .shader_storage_buffer,
        u8,
        0,
        point_chunk,
        .{ .read = true },
    );
    _ = gl.unmapBuffer(.shader_storage_buffer);
    return result;
}

//C:\Users\daych\themolegame\THEMOLEGAME\Assets\Scripts\CaveGeneration\Compute
//returns vertices
//length = 5 (max vertex per voxel) * voxelChunk * 9(vertices in one triangle)
// allocate needed space for tris
pub fn constructMesh(weights: []u8) []f16 {
    var result = [_]f16{0} ** (5 * voxel_chunk * 9);
    var index_counter: usize = 0;
    for (0..voxel_chunk) |i| {
        const coord: glib.int3 = index2coordS(i, voxel_axis);
        const cube_values = [8]u8{
            weights[coord2index(coord[0], coord[1], coord[2] + 1)],
            weights[coord2index(coord[0] + 1, coord[1], coord[2] + 1)],
            weights[coord2index(coord[0] + 1, coord[1], coord[2])],
            weights[coord2index(coord[0], coord[1], coord[2])],
            weights[coord2index(coord[0], coord[1] + 1, coord[2] + 1)],
            weights[coord2index(coord[0] + 1, coord[1] + 1, coord[2] + 1)],
            weights[coord2index(coord[0] + 1, coord[1] + 1, coord[2])],
            weights[coord2index(coord[0], coord[1] + 1, coord[2])],
        };
        var cube_index: u8 = 0;
        for (0..8) |j| {
            if (cube_values[j] > iso) cube_index |= powers2[j];
        }
        const edges = lookup.tri_table[cube_index];
        var iter: u8 = 0;

        while (edges[iter] != 12) {
            const e00 = lookup.edge_connections[edges[iter]][0];
            const e01 = lookup.edge_connections[edges[iter]][1];
            const e10 = lookup.edge_connections[edges[iter + 1]][0];
            const e11 = lookup.edge_connections[edges[iter + 1]][1];
            const e20 = lookup.edge_connections[edges[iter + 2]][0];
            const e21 = lookup.edge_connections[edges[iter + 2]][1];
            var tri = interpolate(lookup.corner_offsets[e00], lookup.corner_offsets[e01]) + i2s(coord);
            for (0..3) |tri_index| result[index_counter + tri_index] = tri[tri_index];
            index_counter += 3;
            tri = interpolate(lookup.corner_offsets[e10], lookup.corner_offsets[e11]) + i2s(coord);
            for (0..3) |tri_index| result[index_counter + tri_index] = tri[tri_index];
            index_counter += 3;
            tri = interpolate(lookup.corner_offsets[e20], lookup.corner_offsets[e21]) + i2s(coord);
            for (0..3) |tri_index| result[index_counter + tri_index] = tri[tri_index];
            index_counter += 3;
            iter += 3;
        }
    }
    return result[0..index_counter];
}

fn interpolate(x: short3, y: short3) short3 {
    return std.math.lerp(x, y, glib.splat(short3, 0.5));
}
fn remap(val: f16) u8 {
    var value: f16 = (std.math.clamp(val, -1, 1) * 0.5 + 0.5) * 255;
    value = std.math.floor(value);
    return @as(u8, @intFromFloat(value));
}
fn coord2index(x: i32, y: i32, z: i32) usize {
    return coord2indexS(x, y, z, point_axis);
}
fn coord2indexS(x: i32, y: i32, z: i32, axis: i32) usize {
    return @intCast(x + (y + z * axis) * axis);
}

fn index2coord(i: usize) glib.int3 {
    return index2coordS(i, point_axis);
}
fn index2coordS(i: usize, axis: usize) glib.int3 {
    return .{
        @intCast(i % axis),
        @intCast(i / axis % axis),
        @intCast(i / (axis * axis) % axis),
    };
}
inline fn computePowers() [8]u8 {
    var res = [_]u8{0} ** 8;
    inline for (0..8) |i| {
        res[i] = std.math.pow(u8, 2, i);
    }
    return res;
}
pub fn i2s(i: glib.int3) short3 {
    return short3{
        @floatFromInt(i[0]),
        @floatFromInt(i[1]),
        @floatFromInt(i[2]),
    };
}
pub fn s2i(i: short3) glib.int3 {
    return glib.int3{
        @intFromFloat(i[0]),
        @intFromFloat(i[1]),
        @intFromFloat(i[2]),
    };
}
pub fn i2v(i: glib.int3) glib.vec3 {
    return glib.vec3{
        @floatFromInt(i[0]),
        @floatFromInt(i[1]),
        @floatFromInt(i[2]),
    };
}
