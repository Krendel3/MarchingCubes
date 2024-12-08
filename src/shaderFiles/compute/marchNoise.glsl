#version 430 core
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
uniform uint chunkSize = 24;
uniform vec3 chunkID;
layout(std430,binding = 0) buffer chunkWeights
{
    uint weights[];
} weightsBuffer;
uint index(uvec3 v){
    return (v.x + (v.y + v.z * chunkSize) * chunkSize) >> 2;
}
float mod289(float x){return x - floor(x * (1.0 / 289.0)) * 289.0;}
vec4 mod289(vec4 x){return x - floor(x * (1.0 / 289.0)) * 289.0;}
vec4 perm(vec4 x){return mod289(((x * 34.0) + 1.0) * x);}
float getNoise(vec3 p){
    vec3 a = floor(p);
    vec3 d = p - a;
    d = d * d * (3.0 - 2.0 * d);

    vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
    vec4 k1 = perm(b.xyxy);
    vec4 k2 = perm(k1.xyxy + b.zzww);

    vec4 c = k2 + a.zzzz;
    vec4 k3 = perm(c);
    vec4 k4 = perm(c + 1.0);

    vec4 o1 = fract(k3 * (1.0 / 41.0));
    vec4 o2 = fract(k4 * (1.0 / 41.0));

    vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
    vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);

    return o4.y * d.y + o4.x * (1.0 - d.y);
}
uint remap(float f){
    return  uint(255 * (clamp(f,-1,1) * 0.5 + 0.5));
}
void main(){
    float freq = 0.075;
    float amp = 0.03;
    uint localIndex = gl_GlobalInvocationID.x & 3;
    vec3 pos = vec3(gl_GlobalInvocationID);
    pos += chunkID * float(chunkSize-1);
    uint value = remap(getNoise(pos * freq) * amp);
    atomicOr(weightsBuffer.weights[index(gl_GlobalInvocationID)],value << (localIndex * 8));
}
