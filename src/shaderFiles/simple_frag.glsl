#version 430 core
out vec4 col;
flat in float rand;

void main(){

    col = vec4(0.6,0.0,1.0,1.0) * rand;
}
