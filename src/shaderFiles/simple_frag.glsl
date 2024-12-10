#version 430 core
out vec4 col;
flat in float rand;

void main(){

    col = vec4(0.4,0.7,0.9,1.0) * rand * 1.1;
}
