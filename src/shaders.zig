const gl = @import("zgl");

const std = @import("std");
const shader_path = "./src/shaderFiles/";
const compute_shader_path = shader_path ++ "compute/";
pub fn computeProgramFromFile(comptime file_name: []const u8, allocator: *const std.mem.Allocator) !gl.Program {
    const source = try stringFromFile(compute_shader_path ++ file_name ++ ".glsl"[0..], allocator);

    defer allocator.free(source);
    const shader = compileShader(.compute, source);
    const program = gl.createProgram();
    gl.attachShader(program, shader);
    gl.linkProgram(program);
    return program;
}
pub fn computeProgramFromFiles(comptime file_name: []const u8, comptime include_name: []const u8, allocator: *const std.mem.Allocator) !gl.Program {
    const source = try stringFromFiles(
        compute_shader_path ++ file_name ++ ".glsl"[0..],
        compute_shader_path ++ "includes/" ++ include_name ++ ".glsl",
        allocator,
    );
    defer allocator.free(source);
    const shader = compileShader(.compute, source);
    const program = gl.createProgram();
    gl.attachShader(program, shader);
    gl.linkProgram(program);
    return program;
}
pub fn shaderProgramFromFiles(comptime file_name: []const u8, allocator: *const std.mem.Allocator) !gl.Program {
    const vert_result_string = try stringFromFile(shader_path ++ file_name ++ "_vert.glsl"[0..], allocator);
    const frag_result_string = try stringFromFile(shader_path ++ file_name ++ "_frag.glsl"[0..], allocator);
    defer allocator.free(vert_result_string);
    defer allocator.free(frag_result_string);
    return try constructShaderProgram(vert_result_string, frag_result_string);
}
fn compileShader(shader_type: gl.ShaderType, source: []u8) gl.Shader {
    const shader = gl.createShader(shader_type);
    gl.shaderSource(
        shader,
        1,
        &([1][]u8{source}),
    );
    gl.compileShader(shader);
    return shader;
}
fn constructShaderProgram(vert_str: []u8, frag_str: []u8) !gl.Program {
    const frag = compileShader(
        .fragment,
        frag_str,
    );
    defer gl.deleteShader(frag);
    const vert = compileShader(
        .vertex,
        vert_str,
    );
    defer gl.deleteShader(vert);

    const shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vert);
    gl.attachShader(shaderProgram, frag);
    gl.linkProgram(shaderProgram);
    return shaderProgram;
}

//frag file name = fn + _frag
//vert file name = fn + _vert

fn stringFromFile(comptime file_name: []const u8, allocator: *const std.mem.Allocator) ![]u8 {
    var file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();
    return file.readToEndAlloc(allocator.*, std.math.maxInt(usize));
}
fn stringFromFiles(comptime file_name: []const u8, comptime include_name: []const u8, allocator: *const std.mem.Allocator) ![]u8 {
    const include = try (try std.fs.cwd().openFile(include_name, .{})).readToEndAlloc(allocator.*, std.math.maxInt(usize));
    const main = try (try std.fs.cwd().openFile(file_name, .{})).readToEndAlloc(allocator.*, std.math.maxInt(usize));
    //var buffer : [sum_len + main_len:0]u8 = undefined;

    defer allocator.free(main);
    defer allocator.free(include);
    const buffer = try allocator.alloc(u8, include.len + main.len + 2); //2 for \n
    const endl = "\n";
    const version_line_end: usize = for (0..main.len - 1) |index| {
        //if (main[index] == "\n") break index + 2;
        if (std.mem.eql(u8, endl, main[index .. index + 2])) break index + 2;
    } else 0;
    //copy the glsl #version into the start if the buffer
    @memcpy(buffer[0..version_line_end], main[0..version_line_end]);
    const include_end = version_line_end + include.len;
    @memcpy(buffer[version_line_end..include_end], include);
    buffer[include_end] = "n"[0];
    buffer[include_end + 1] = "\\"[0];
    @memcpy(buffer[include_end + 2 ..], main[version_line_end..]);
    return buffer;
}
