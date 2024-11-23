const gl = @import("zgl");

const std = @import("std");
pub fn computeProgramFromFile(comptime file_name: []const u8, allocator: *const std.mem.Allocator) !gl.Program {
    const shader_path = "./src/shaderFiles/compute/";
    const source = try stringFromFile(shader_path ++ file_name ++ ".glsl"[0..], allocator);
    defer allocator.free(source);
    //std.debug.print("{s} \n", .{source});
    const shader = compileShader(.compute, source);
    const program = gl.createProgram();
    gl.attachShader(program, shader);
    gl.linkProgram(program);
    return program;
}
pub fn shaderProgramFromFiles(comptime file_name: []const u8, allocator: *const std.mem.Allocator) !gl.Program {
    const shader_path = "./src/shaderFiles/";
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
