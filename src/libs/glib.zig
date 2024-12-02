const std = @import("std");
const zm = @import("zmath");
const gl = @import("zgl");
pub const vec2 = @Vector(2, f32);
pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);
pub const int3 = @Vector(3, i32);
pub const uint3 = @Vector(3, i32);

pub const transform = struct {
    rot: vec4 = zm.qidentity(),
    pos: vec3 = @splat(0),
    scl: vec3 = @splat(1),
    // alignment increases struct size by 8 bytes
    const Self = @This();
    pub fn viewDir(self: Self) vec4 {
        const t: vec4 = scale(zm.cross3(self.rot, vec4{ 0, 0, 1, 0 }), 2);
        return zm.normalize3(scale(t, self.rot[3]) + zm.cross3(self.rot, t) + vec4{ 0, 0, 1, 0 });
    }
    pub fn setRot(self: *Self, vec: anytype) void {
        if (@TypeOf(vec) == vec4) {
            self.rot = normalize(vec);
            return;
        }
        if (@TypeOf(vec) == vec3) {
            const quat = zm.quatFromRollPitchYawV(as(vec3{ vec[0], vec[1], vec[2] }, vec4));
            self.rot = normalize(quat);
        }
    }
    pub fn modelMatrix(self: *Self) zm.Mat {
        const tmat = zm.translationV(asFill(self.pos, vec4, 1));
        const rmat = zm.quatToMat(self.rot);
        //const smat = zm.translationV(self.pos);
        return zm.mul(tmat, rmat);
    }
};

pub const mesh = struct {
    const meshType = enum { indexed, unindexed };
    vao: gl.VertexArray,
    vbo: gl.Buffer,
    ibo: gl.Buffer,
    verts: []f32,
    indices: []u32,
};
pub const cameraData = struct {
    fov: f32 = 60,
    near: f32 = 0.3,
    far: f32 = 1000,
    const Self = @This();
    pub fn getPerspMatrix(self: Self, aspect_ratio: f32) zm.Mat {
        return zm.perspectiveFovLhGl(
            self.fov * std.math.pi / 180.0,
            aspect_ratio,
            self.near,
            self.far,
        );
    }
};
pub fn matToUniform(mat: zm.Mat) []const [4][4]f32 {
    return &.{matTo4x4(mat)};
}
pub fn matTo4x4(mat: zm.Mat) [4][4]f32 {
    //return .{ mat[0], mat[1], mat[2], mat[3] };
    return .{
        .{ mat[0][0], mat[1][0], mat[2][0], mat[3][0] },
        .{ mat[0][1], mat[1][1], mat[2][1], mat[3][1] },
        .{ mat[0][2], mat[1][2], mat[2][2], mat[3][2] },
        .{ mat[0][3], mat[1][3], mat[2][3], mat[3][3] },
    };
}
pub fn getWorldToViewMatrix(cam_transform: transform) zm.Mat {
    return zm.lookToLh(
        asFill(cam_transform.pos, vec4, 1.0),
        cam_transform.viewDir(),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
}
pub fn getWorldToClipMatrix(cam_transform: transform, cam_data: cameraData, aspect_ratio: f32) zm.Mat {
    //_ = cam_transform;
    return zm.mul(
        getWorldToViewMatrix(cam_transform),
        cam_data.getPerspMatrix(aspect_ratio),
    );
}

pub fn scale(vector: anytype, scalar: anytype) @TypeOf(vector) {
    std.debug.assert(@typeInfo(@TypeOf(vector)) == .vector);
    const scaleVec: @TypeOf(vector) = @splat(scalar);
    return vector * scaleVec;
}
pub fn asFill(vector: anytype, comptime target_type: type, fill: anytype) target_type {
    std.debug.assert(@typeInfo(@TypeOf(vector)) == .vector and @typeInfo(target_type) == .vector);

    const len = @typeInfo(target_type).vector.len;
    const s = @min(@typeInfo(@TypeOf(vector)).vector.len, len);
    const child = @typeInfo(target_type).vector.child;
    var array = [_]child{0} ** s;

    for (0..s) |element| {
        if (element >= len) break;
        array[element] = vector[element]; //castFunc.*
    }
    const result = @as(target_type, array ++ [_]child{fill} ** @max(0, len - s));
    return result;
}
pub fn as(vector: anytype, target_type: type) target_type {
    return asFill(vector, target_type, 1);
}

pub fn castSameType(val: anytype, t: type) t {
    const initial_t = @TypeOf(val);
    if (@sizeOf(initial_t) > @sizeOf(t)) {
        return @as(t, val);
    }
    return @as(t, @truncate(val));
}
pub fn normalize(vec: anytype) @TypeOf(vec) {
    std.debug.assert(@typeInfo(@TypeOf(vec)) == .vector);
    const smag = sqrMagnitude(vec);
    const mult: @typeInfo(@TypeOf(vec)).vector.child = if (smag > 0) 1.0 / @sqrt(smag) else 0;
    return vec * @as(@TypeOf(vec), @splat(mult));
}
pub fn magnitude(vec: anytype) @typeInfo(@TypeOf(vec)).vector.child {
    return @sqrt(sqrMagnitude(vec));
}
pub fn sqrMagnitude(vec: anytype) @typeInfo(@TypeOf(vec)).vector.child {
    std.debug.assert(@typeInfo(@TypeOf(vec)) == .vector);
    const t_info = @typeInfo(@TypeOf(vec));
    var sqr_mag: t_info.vector.child = 0.0;
    inline for (0..t_info.vector.len) |i| {
        sqr_mag += vec[i] * vec[i];
    }
    return sqr_mag;
}
pub fn dot(foo: anytype, bar: @TypeOf(foo)) @typeInfo(@TypeOf(foo)).vector.child {
    std.debug.assert(@typeInfo(@TypeOf(foo)) == .vector);
    const t_info = @typeInfo(@TypeOf(foo));
    var res: t_info.vector.child = 0;
    inline for (0..t_info.vector.len) |i| {
        res += foo[i] * bar[i];
    }
    return res;
}
pub fn splat(comptime vec: type, val: @typeInfo(vec).vector.child) vec {
    // std.debug.assert(@typeInfo(vec) == .vector);
    return @as(vec, @splat(val));
}
