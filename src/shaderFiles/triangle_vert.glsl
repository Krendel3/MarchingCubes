#version 410 core
uniform mat4 matrix;
uniform vec3 lightDir;

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 normal;

out vec3 worldPos;

flat out vec3 diffuse_color;
flat out vec3 f_normal;


void main() {
   gl_Position = vec4(position, 1.0f) * matrix;

   float NdotL = max(0,dot(normal, -lightDir)); 
   diffuse_color = vec3(NdotL); 

   worldPos = position;
   f_normal = normal;
}
