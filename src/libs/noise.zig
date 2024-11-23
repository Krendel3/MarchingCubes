const std = @import("std");
const glib = @import("../glib.zig");
const zm = @import("zmath");
const vec3 = glib.vec3;
const vec4 = glib.vec4;
const int3 = glib.int3;
pub fn random3(v: int3, seed: i32) int3 {
    const minus = @as(i32, @intCast(@rem(@abs(seed), 2)));
    const fac: int3 = int3{ 11248723, 105436839 + seed - minus, 47869083 }; //45399083

    const s: i32 = v[0] *% fac[0] ^ v[1] *% fac[1] ^ v[2] *% fac[2];
    return glib.splat(int3, s) *% fac;
}
pub fn simplex3(pos: vec3, seed: i32) f32 {
    const c: glib.vec2 = .{ 1.0 / 6.0, 1.0 / 3.0 };

    const i = floor(pos + glib.splat(vec3, pos[0] * c[1] + pos[1] * c[1] + pos[2] * c[1]));
    const x0 = pos - i + glib.splat(vec3, i[0] * c[0] + i[1] * c[0] + i[2] * c[0]);

    const g = step(
        .{ x0[1], x0[2], x0[0] },
        x0,
    );
    const l = glib.splat(vec3, 1.0) - g;
    const i_1 = min(
        g,
        .{ l[1], l[2], l[0] },
    );
    const i_2 = max(
        g,
        .{ l[1], l[2], l[0] },
    );
    const x1: vec3 = x0 - i_1 + glib.splat(vec3, 1.0 * c[0]);
    const x2: vec3 = x0 - i_2 + glib.splat(vec3, 2.0 * c[0]);
    const x3: vec3 = x0 - i_1 + glib.splat(vec3, 1 + 3.0 * c[0]);
    // Permutations
    var rand = random3(v2i(i), seed);

    var p0 = i2v(rand);
    rand = random3(v2i(i + i_1), seed);
    var p1 = i2v(rand);
    rand = random3(v2i(i + i_2), seed);
    var p2 = i2v(rand);
    rand = random3(v2i(i + glib.splat(vec3, 1.0)), seed);
    var p3 = i2v(rand);

    const norm: vec4 = taylorInvSqrt(vec4{
        glib.sqrMagnitude(p0),
        glib.sqrMagnitude(p1),
        glib.sqrMagnitude(p2),
        glib.sqrMagnitude(p3),
    });
    p0 *= glib.splat(vec3, norm[0]);
    p1 *= glib.splat(vec3, norm[1]);
    p2 *= glib.splat(vec3, norm[2]);
    p3 *= glib.splat(vec3, norm[3]);

    var m = max04(vec4{
        glib.sqrMagnitude(x0),
        glib.sqrMagnitude(x1),
        glib.sqrMagnitude(x2),
        glib.sqrMagnitude(x3),
    });
    m = m * m;
    return 42.0 * glib.dot(m * m, vec4{
        glib.dot(p0, x0),
        glib.dot(p1, x1),
        glib.dot(p2, x2),
        glib.dot(p3, x3),
    });
}

fn min(x: vec3, y: vec3) vec3 {
    return vec3{
        @min(x[0], y[0]),
        @min(x[1], y[1]),
        @min(x[2], y[2]),
    };
}
fn max(x: vec3, y: vec3) vec3 {
    return vec3{
        @max(x[0], y[0]),
        @max(x[1], y[1]),
        @max(x[2], y[2]),
    };
}
fn max04(x: vec4) vec4 {
    return vec4{
        @max(x[0], 0),
        @max(x[1], 0),
        @max(x[2], 0),
        @max(x[3], 0),
    };
}
fn floor(x: vec3) vec3 {
    return vec3{
        std.math.floor(x[0]),
        std.math.floor(x[1]),
        std.math.floor(x[2]),
    };
}
fn step(y: vec3, x: vec3) vec3 {
    return vec3{
        stepF(y[0], x[0]),
        stepF(y[1], x[1]),
        stepF(y[2], x[2]),
    };
}
fn stepF(y: f32, x: f32) f32 {
    return @as(f32, @floatFromInt(@intFromBool(x >= y)));
}
fn taylorInvSqrt(r: vec4) vec4 {
    return glib.splat(vec4, 1.79284291400159) - glib.splat(vec4, 0.85373472095314) * r;
}
pub fn i2v(i: int3) vec3 {
    return vec3{
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
