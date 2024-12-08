#version 430 core
out vec4 col;
flat in float rand;

void main(){

    col = vec4(0.9,0.5,0.4,1.0) * rand;
}
