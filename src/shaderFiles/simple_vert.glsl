#version 430 core
uniform mat4 matrix;
in vec3 position;
flat out float rand;
float permhash(vec3 p) {
  return fract(sin(dot(p, vec3(12.9898, 78.233,23.789))) * 43758.5453);
}
void main() {
   gl_Position = vec4(position, 1.0f) * matrix;
   rand = permhash(position) * .5 + .5;
}
