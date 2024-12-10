#version 430 core
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
uniform float chunkSize;
uniform uint pointsChunk = 24;
uniform vec3 chunkID;

uniform vec3 point;
uint amount = 255;
uniform float radius = 10;

layout(std430,binding = 0) buffer chunkWeights
{
    uint weights[];
} weightsBuffer;
uint index(uvec3 v){
    return (v.x + (v.y + v.z * pointsChunk) * pointsChunk) >> 2;
}
void main(){
    uint localIndex = gl_GlobalInvocationID.x & 3;
    vec3 pos = vec3(gl_GlobalInvocationID) * chunkSize / float(pointsChunk-1);
    pos += chunkID * chunkSize;
    if(distance(point,pos) > radius)return;
    atomicOr(weightsBuffer.weights[index(gl_GlobalInvocationID)],(255 << (localIndex * 8)));

}
