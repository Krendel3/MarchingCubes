#version 430 core
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
uniform uint chunkSize = 24;
uniform vec3 chunkID;

uniform vec3 point;
uint amount = 1;
float radius = 10;

layout(std430,binding = 0) buffer chunkWeights
{
    uint weights[];
} weightsBuffer;
uint index(uvec3 v){
    return (v.x + (v.y + v.z * chunkSize) * chunkSize) >> 2;
}
void main(){
    uint localIndex = gl_GlobalInvocationID.x & 3;
    uint newVal = weightsBuffer.weights[index(gl_GlobalInvocationID)];
    newVal = (newVal << (localIndex * 8)) & 255 - 1;
    atomicExchange(weightsBuffer.weights[index(gl_GlobalInvocationID)],
    );
    ,value 
    atomicOr();
}
