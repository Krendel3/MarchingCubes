#version 410 core
uniform mat4 matrix;
in vec3 position;
void main() {
   gl_Position = vec4(position, 1.0f) * matrix;
}
