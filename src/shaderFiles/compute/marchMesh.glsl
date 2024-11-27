#version 430 core
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const uint edgeConnections[12][2] ={
    { 0, 1 }, { 1, 2 }, { 2, 3 }, { 3, 0 },
    { 4, 5 }, { 5, 6 }, { 6, 7 }, { 7, 4 },
    { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 }
};

const vec3 cornerOffsets[8] = {
    vec3( 0, 0, 1 ),
    vec3( 1, 0, 1 ),
    vec3( 1, 0, 0 ),
    vec3( 0, 0, 0 ),
    vec3( 0, 1, 1 ),
    vec3( 1, 1, 1 ),
    vec3( 1, 1, 0 ),
    vec3( 0, 1, 0 )
};
const uint triTable[256][16] = {
    {12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 1, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 8, 3, 9, 8, 1, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 1, 2, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 2, 10, 0, 2, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 8, 3, 2, 10, 8, 10, 9, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 11, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 11, 2, 8, 11, 0, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 9, 0, 2, 3, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 11, 2, 1, 9, 11, 9, 8, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 10, 1, 11, 10, 3, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 10, 1, 0, 8, 10, 8, 11, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 9, 0, 3, 11, 9, 11, 10, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 8, 10, 10, 8, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 7, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 3, 0, 7, 3, 4, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 1, 9, 8, 4, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 1, 9, 4, 7, 1, 7, 3, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 8, 4, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 4, 7, 3, 0, 4, 1, 2, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 2, 10, 9, 0, 2, 8, 4, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, 12, 12, 12, 12 },
    { 8, 4, 7, 3, 11, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 4, 7, 11, 2, 4, 2, 0, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 0, 1, 8, 4, 7, 2, 3, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, 12, 12, 12, 12 },
    { 3, 10, 1, 3, 11, 10, 7, 8, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, 12, 12, 12, 12 },
    { 4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, 12, 12, 12, 12 },
    { 4, 7, 11, 4, 11, 9, 9, 11, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 5, 4, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 5, 4, 0, 8, 3, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 5, 4, 1, 5, 0, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 5, 4, 8, 3, 5, 3, 1, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 9, 5, 4, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 0, 8, 1, 2, 10, 4, 9, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 2, 10, 5, 4, 2, 4, 0, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 10, 5, 3, 2, 5, 3, 5, 4, 3, 4, 8, 12, 12, 12, 12 },
    { 9, 5, 4, 2, 3, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 11, 2, 0, 8, 11, 4, 9, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 5, 4, 0, 1, 5, 2, 3, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 1, 5, 2, 5, 8, 2, 8, 11, 4, 8, 5, 12, 12, 12, 12 },
    { 10, 3, 11, 10, 1, 3, 9, 5, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 9, 5, 0, 8, 1, 8, 10, 1, 8, 11, 10, 12, 12, 12, 12 },
    { 5, 4, 0, 5, 0, 11, 5, 11, 10, 11, 0, 3, 12, 12, 12, 12 },
    { 5, 4, 8, 5, 8, 10, 10, 8, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 7, 8, 5, 7, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 3, 0, 9, 5, 3, 5, 7, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 7, 8, 0, 1, 7, 1, 5, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 5, 3, 3, 5, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 7, 8, 9, 5, 7, 10, 1, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 1, 2, 9, 5, 0, 5, 3, 0, 5, 7, 3, 12, 12, 12, 12 },
    { 8, 0, 2, 8, 2, 5, 8, 5, 7, 10, 5, 2, 12, 12, 12, 12 },
    { 2, 10, 5, 2, 5, 3, 3, 5, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 9, 5, 7, 8, 9, 3, 11, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 5, 7, 9, 7, 2, 9, 2, 0, 2, 7, 11, 12, 12, 12, 12 },
    { 2, 3, 11, 0, 1, 8, 1, 7, 8, 1, 5, 7, 12, 12, 12, 12 },
    { 11, 2, 1, 11, 1, 7, 7, 1, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 5, 8, 8, 5, 7, 10, 1, 3, 10, 3, 11, 12, 12, 12, 12 },
    { 5, 7, 0, 5, 0, 9, 7, 11, 0, 1, 0, 10, 11, 10, 0, 12 },
    { 11, 10, 0, 11, 0, 3, 10, 5, 0, 8, 0, 7, 5, 7, 0, 12 },
    { 11, 10, 5, 7, 11, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 6, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 5, 10, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 0, 1, 5, 10, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 8, 3, 1, 9, 8, 5, 10, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 6, 5, 2, 6, 1, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 6, 5, 1, 2, 6, 3, 0, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 6, 5, 9, 0, 6, 0, 2, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 9, 8, 5, 8, 2, 5, 2, 6, 3, 2, 8, 12, 12, 12, 12 },
    { 2, 3, 11, 10, 6, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 0, 8, 11, 2, 0, 10, 6, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 1, 9, 2, 3, 11, 5, 10, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 10, 6, 1, 9, 2, 9, 11, 2, 9, 8, 11, 12, 12, 12, 12 },
    { 6, 3, 11, 6, 5, 3, 5, 1, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 11, 0, 11, 5, 0, 5, 1, 5, 11, 6, 12, 12, 12, 12 },
    { 3, 11, 6, 0, 3, 6, 0, 6, 5, 0, 5, 9, 12, 12, 12, 12 },
    { 6, 5, 9, 6, 9, 11, 11, 9, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 10, 6, 4, 7, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 3, 0, 4, 7, 3, 6, 5, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 9, 0, 5, 10, 6, 8, 4, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 6, 5, 1, 9, 7, 1, 7, 3, 7, 9, 4, 12, 12, 12, 12 },
    { 6, 1, 2, 6, 5, 1, 4, 7, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 5, 5, 2, 6, 3, 0, 4, 3, 4, 7, 12, 12, 12, 12 },
    { 8, 4, 7, 9, 0, 5, 0, 6, 5, 0, 2, 6, 12, 12, 12, 12 },
    { 7, 3, 9, 7, 9, 4, 3, 2, 9, 5, 9, 6, 2, 6, 9, 12 },
    { 3, 11, 2, 7, 8, 4, 10, 6, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 10, 6, 4, 7, 2, 4, 2, 0, 2, 7, 11, 12, 12, 12, 12 },
    { 0, 1, 9, 4, 7, 8, 2, 3, 11, 5, 10, 6, 12, 12, 12, 12 },
    { 9, 2, 1, 9, 11, 2, 9, 4, 11, 7, 11, 4, 5, 10, 6, 12 },
    { 8, 4, 7, 3, 11, 5, 3, 5, 1, 5, 11, 6, 12, 12, 12, 12 },
    { 5, 1, 11, 5, 11, 6, 1, 0, 11, 7, 11, 4, 0, 4, 11, 12 },
    { 0, 5, 9, 0, 6, 5, 0, 3, 6, 11, 6, 3, 8, 4, 7, 12 },
    { 6, 5, 9, 6, 9, 11, 4, 7, 9, 7, 11, 9, 12, 12, 12, 12 },
    { 10, 4, 9, 6, 4, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 10, 6, 4, 9, 10, 0, 8, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 0, 1, 10, 6, 0, 6, 4, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 3, 1, 8, 1, 6, 8, 6, 4, 6, 1, 10, 12, 12, 12, 12 },
    { 1, 4, 9, 1, 2, 4, 2, 6, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 0, 8, 1, 2, 9, 2, 4, 9, 2, 6, 4, 12, 12, 12, 12 },
    { 0, 2, 4, 4, 2, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 3, 2, 8, 2, 4, 4, 2, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 4, 9, 10, 6, 4, 11, 2, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 2, 2, 8, 11, 4, 9, 10, 4, 10, 6, 12, 12, 12, 12 },
    { 3, 11, 2, 0, 1, 6, 0, 6, 4, 6, 1, 10, 12, 12, 12, 12 },
    { 6, 4, 1, 6, 1, 10, 4, 8, 1, 2, 1, 11, 8, 11, 1, 12 },
    { 9, 6, 4, 9, 3, 6, 9, 1, 3, 11, 6, 3, 12, 12, 12, 12 },
    { 8, 11, 1, 8, 1, 0, 11, 6, 1, 9, 1, 4, 6, 4, 1, 12 },
    { 3, 11, 6, 3, 6, 0, 0, 6, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 6, 4, 8, 11, 6, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 10, 6, 7, 8, 10, 8, 9, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 7, 3, 0, 10, 7, 0, 9, 10, 6, 7, 10, 12, 12, 12, 12 },
    { 10, 6, 7, 1, 10, 7, 1, 7, 8, 1, 8, 0, 12, 12, 12, 12 },
    { 10, 6, 7, 10, 7, 1, 1, 7, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 6, 1, 6, 8, 1, 8, 9, 8, 6, 7, 12, 12, 12, 12 },
    { 2, 6, 9, 2, 9, 1, 6, 7, 9, 0, 9, 3, 7, 3, 9, 12 },
    { 7, 8, 0, 7, 0, 6, 6, 0, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 3, 2, 6, 7, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 3, 11, 10, 6, 8, 10, 8, 9, 8, 6, 7, 12, 12, 12, 12 },
    { 2, 0, 7, 2, 7, 11, 0, 9, 7, 6, 7, 10, 9, 10, 7, 12 },
    { 1, 8, 0, 1, 7, 8, 1, 10, 7, 6, 7, 10, 2, 3, 11, 12 },
    { 11, 2, 1, 11, 1, 7, 10, 6, 1, 6, 7, 1, 12, 12, 12, 12 },
    { 8, 9, 6, 8, 6, 7, 9, 1, 6, 11, 6, 3, 1, 3, 6, 12 },
    { 0, 9, 1, 11, 6, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 8, 0, 7, 0, 6, 3, 11, 0, 11, 6, 0, 12, 12, 12, 12 },
    { 7, 11, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 6, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 0, 8, 11, 7, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 1, 9, 11, 7, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 1, 9, 8, 3, 1, 11, 7, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 1, 2, 6, 11, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 3, 0, 8, 6, 11, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 9, 0, 2, 10, 9, 6, 11, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 6, 11, 7, 2, 10, 3, 10, 8, 3, 10, 9, 8, 12, 12, 12, 12 },
    { 7, 2, 3, 6, 2, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 7, 0, 8, 7, 6, 0, 6, 2, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 7, 6, 2, 3, 7, 0, 1, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 6, 2, 1, 8, 6, 1, 9, 8, 8, 7, 6, 12, 12, 12, 12 },
    { 10, 7, 6, 10, 1, 7, 1, 3, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 7, 6, 1, 7, 10, 1, 8, 7, 1, 0, 8, 12, 12, 12, 12 },
    { 0, 3, 7, 0, 7, 10, 0, 10, 9, 6, 10, 7, 12, 12, 12, 12 },
    { 7, 6, 10, 7, 10, 8, 8, 10, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 6, 8, 4, 11, 8, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 6, 11, 3, 0, 6, 0, 4, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 6, 11, 8, 4, 6, 9, 0, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 4, 6, 9, 6, 3, 9, 3, 1, 11, 3, 6, 12, 12, 12, 12 },
    { 6, 8, 4, 6, 11, 8, 2, 10, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 3, 0, 11, 0, 6, 11, 0, 4, 6, 12, 12, 12, 12 },
    { 4, 11, 8, 4, 6, 11, 0, 2, 9, 2, 10, 9, 12, 12, 12, 12 },
    { 10, 9, 3, 10, 3, 2, 9, 4, 3, 11, 3, 6, 4, 6, 3, 12 },
    { 8, 2, 3, 8, 4, 2, 4, 6, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 4, 2, 4, 6, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 9, 0, 2, 3, 4, 2, 4, 6, 4, 3, 8, 12, 12, 12, 12 },
    { 1, 9, 4, 1, 4, 2, 2, 4, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 1, 3, 8, 6, 1, 8, 4, 6, 6, 10, 1, 12, 12, 12, 12 },
    { 10, 1, 0, 10, 0, 6, 6, 0, 4, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 6, 3, 4, 3, 8, 6, 10, 3, 0, 3, 9, 10, 9, 3, 12 },
    { 10, 9, 4, 6, 10, 4, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 9, 5, 7, 6, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 4, 9, 5, 11, 7, 6, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 0, 1, 5, 4, 0, 7, 6, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 7, 6, 8, 3, 4, 3, 5, 4, 3, 1, 5, 12, 12, 12, 12 },
    { 9, 5, 4, 10, 1, 2, 7, 6, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 6, 11, 7, 1, 2, 10, 0, 8, 3, 4, 9, 5, 12, 12, 12, 12 },
    { 7, 6, 11, 5, 4, 10, 4, 2, 10, 4, 0, 2, 12, 12, 12, 12 },
    { 3, 4, 8, 3, 5, 4, 3, 2, 5, 10, 5, 2, 11, 7, 6, 12 },
    { 7, 2, 3, 7, 6, 2, 5, 4, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 5, 4, 0, 8, 6, 0, 6, 2, 6, 8, 7, 12, 12, 12, 12 },
    { 3, 6, 2, 3, 7, 6, 1, 5, 0, 5, 4, 0, 12, 12, 12, 12 },
    { 6, 2, 8, 6, 8, 7, 2, 1, 8, 4, 8, 5, 1, 5, 8, 12 },
    { 9, 5, 4, 10, 1, 6, 1, 7, 6, 1, 3, 7, 12, 12, 12, 12 },
    { 1, 6, 10, 1, 7, 6, 1, 0, 7, 8, 7, 0, 9, 5, 4, 12 },
    { 4, 0, 10, 4, 10, 5, 0, 3, 10, 6, 10, 7, 3, 7, 10, 12 },
    { 7, 6, 10, 7, 10, 8, 5, 4, 10, 4, 8, 10, 12, 12, 12, 12 },
    { 6, 9, 5, 6, 11, 9, 11, 8, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 6, 11, 0, 6, 3, 0, 5, 6, 0, 9, 5, 12, 12, 12, 12 },
    { 0, 11, 8, 0, 5, 11, 0, 1, 5, 5, 6, 11, 12, 12, 12, 12 },
    { 6, 11, 3, 6, 3, 5, 5, 3, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 10, 9, 5, 11, 9, 11, 8, 11, 5, 6, 12, 12, 12, 12 },
    { 0, 11, 3, 0, 6, 11, 0, 9, 6, 5, 6, 9, 1, 2, 10, 12 },
    { 11, 8, 5, 11, 5, 6, 8, 0, 5, 10, 5, 2, 0, 2, 5, 12 },
    { 6, 11, 3, 6, 3, 5, 2, 10, 3, 10, 5, 3, 12, 12, 12, 12 },
    { 5, 8, 9, 5, 2, 8, 5, 6, 2, 3, 8, 2, 12, 12, 12, 12 },
    { 9, 5, 6, 9, 6, 0, 0, 6, 2, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 5, 8, 1, 8, 0, 5, 6, 8, 3, 8, 2, 6, 2, 8, 12 },
    { 1, 5, 6, 2, 1, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 3, 6, 1, 6, 10, 3, 8, 6, 5, 6, 9, 8, 9, 6, 12 },
    { 10, 1, 0, 10, 0, 6, 9, 5, 0, 5, 6, 0, 12, 12, 12, 12 },
    { 0, 3, 8, 5, 6, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 5, 6, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 5, 10, 7, 5, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 5, 10, 11, 7, 5, 8, 3, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 11, 7, 5, 10, 11, 1, 9, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 10, 7, 5, 10, 11, 7, 9, 8, 1, 8, 3, 1, 12, 12, 12, 12 },
    { 11, 1, 2, 11, 7, 1, 7, 5, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 1, 2, 7, 1, 7, 5, 7, 2, 11, 12, 12, 12, 12 },
    { 9, 7, 5, 9, 2, 7, 9, 0, 2, 2, 11, 7, 12, 12, 12, 12 },
    { 7, 5, 2, 7, 2, 11, 5, 9, 2, 3, 2, 8, 9, 8, 2, 12 },
    { 2, 5, 10, 2, 3, 5, 3, 7, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 2, 0, 8, 5, 2, 8, 7, 5, 10, 2, 5, 12, 12, 12, 12 },
    { 9, 0, 1, 5, 10, 3, 5, 3, 7, 3, 10, 2, 12, 12, 12, 12 },
    { 9, 8, 2, 9, 2, 1, 8, 7, 2, 10, 2, 5, 7, 5, 2, 12 },
    { 1, 3, 5, 3, 7, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 7, 0, 7, 1, 1, 7, 5, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 0, 3, 9, 3, 5, 5, 3, 7, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 8, 7, 5, 9, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 8, 4, 5, 10, 8, 10, 11, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 5, 0, 4, 5, 11, 0, 5, 10, 11, 11, 3, 0, 12, 12, 12, 12 },
    { 0, 1, 9, 8, 4, 10, 8, 10, 11, 10, 4, 5, 12, 12, 12, 12 },
    { 10, 11, 4, 10, 4, 5, 11, 3, 4, 9, 4, 1, 3, 1, 4, 12 },
    { 2, 5, 1, 2, 8, 5, 2, 11, 8, 4, 5, 8, 12, 12, 12, 12 },
    { 0, 4, 11, 0, 11, 3, 4, 5, 11, 2, 11, 1, 5, 1, 11, 12 },
    { 0, 2, 5, 0, 5, 9, 2, 11, 5, 4, 5, 8, 11, 8, 5, 12 },
    { 9, 4, 5, 2, 11, 3, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 5, 10, 3, 5, 2, 3, 4, 5, 3, 8, 4, 12, 12, 12, 12 },
    { 5, 10, 2, 5, 2, 4, 4, 2, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 10, 2, 3, 5, 10, 3, 8, 5, 4, 5, 8, 0, 1, 9, 12 },
    { 5, 10, 2, 5, 2, 4, 1, 9, 2, 9, 4, 2, 12, 12, 12, 12 },
    { 8, 4, 5, 8, 5, 3, 3, 5, 1, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 4, 5, 1, 0, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 8, 4, 5, 8, 5, 3, 9, 0, 5, 0, 3, 5, 12, 12, 12, 12 },
    { 9, 4, 5, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 11, 7, 4, 9, 11, 9, 10, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 8, 3, 4, 9, 7, 9, 11, 7, 9, 10, 11, 12, 12, 12, 12 },
    { 1, 10, 11, 1, 11, 4, 1, 4, 0, 7, 4, 11, 12, 12, 12, 12 },
    { 3, 1, 4, 3, 4, 8, 1, 10, 4, 7, 4, 11, 10, 11, 4, 12 },
    { 4, 11, 7, 9, 11, 4, 9, 2, 11, 9, 1, 2, 12, 12, 12, 12 },
    { 9, 7, 4, 9, 11, 7, 9, 1, 11, 2, 11, 1, 0, 8, 3, 12 },
    { 11, 7, 4, 11, 4, 2, 2, 4, 0, 12, 12, 12, 12, 12, 12, 12 },
    { 11, 7, 4, 11, 4, 2, 8, 3, 4, 3, 2, 4, 12, 12, 12, 12 },
    { 2, 9, 10, 2, 7, 9, 2, 3, 7, 7, 4, 9, 12, 12, 12, 12 },
    { 9, 10, 7, 9, 7, 4, 10, 2, 7, 8, 7, 0, 2, 0, 7, 12 },
    { 3, 7, 10, 3, 10, 2, 7, 4, 10, 1, 10, 0, 4, 0, 10, 12 },
    { 1, 10, 2, 8, 7, 4, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 9, 1, 4, 1, 7, 7, 1, 3, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 9, 1, 4, 1, 7, 0, 8, 1, 8, 7, 1, 12, 12, 12, 12 },
    { 4, 0, 3, 7, 4, 3, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 4, 8, 7, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 10, 8, 10, 11, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 0, 9, 3, 9, 11, 11, 9, 10, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 1, 10, 0, 10, 8, 8, 10, 11, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 1, 10, 11, 3, 10, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 2, 11, 1, 11, 9, 9, 11, 8, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 0, 9, 3, 9, 11, 1, 2, 9, 2, 11, 9, 12, 12, 12, 12 },
    { 0, 2, 11, 8, 0, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 3, 2, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 3, 8, 2, 8, 10, 10, 8, 9, 12, 12, 12, 12, 12, 12, 12 },
    { 9, 10, 2, 0, 9, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 2, 3, 8, 2, 8, 10, 0, 1, 8, 1, 10, 8, 12, 12, 12, 12 },
    { 1, 10, 2, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 1, 3, 8, 9, 1, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 9, 1, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 0, 3, 8, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
    { 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12 }
};



uniform uint chunkSize;
uniform vec3 chunkID;
layout(std430,binding = 0) buffer chunkWeights
{
    uint weights[];
} weightsBuffer;
layout(std430,binding = 1) buffer triangleBuffer
{
    float tris[][9];
} triangles;
layout(binding = 2,offset = 0) uniform atomic_uint counter;
uint index(uvec3 v){
    return (v.x + (v.y + v.z * chunkSize) * chunkSize);
}
float max3 (uvec3 v) {
  return max (max (v.x, v.y), v.z);
}
uint modula(uint a,uint b){
    return uint(a - (b * floor(a/b)));
}
uint getWeightsOffset(uvec3 coord){
    uvec3 newCoord = coord + gl_GlobalInvocationID;
    uint localIndex = modula(newCoord.x,4);
    return 255 & (weightsBuffer.weights[index(newCoord) / 4] >> (8 * localIndex));
}

vec3 interpolate(vec3 x,vec3 y,uint xv, uint yv){
    return mix(x,y,vec3(.5,.5,.5));
}
void main(){
    if(max3(gl_GlobalInvocationID) >= (chunkSize - 1)) return;
    
    uint iso = 128;

    uint cubeValues[8] = {
        getWeightsOffset(uvec3(0,0,1)),
        getWeightsOffset(uvec3(1,0,1)),
        getWeightsOffset(uvec3(1,0,0)),
        getWeightsOffset(uvec3(0,0,0)),
        getWeightsOffset(uvec3(0,1,1)),
        getWeightsOffset(uvec3(1,1,1)),
        getWeightsOffset(uvec3(1,1,0)),
        getWeightsOffset(uvec3(0,1,0)),
    };
    uint cubeIndex = 0;
    cubeIndex |= uint(cubeValues[0] > iso) * 1;
    cubeIndex |= uint(cubeValues[1] > iso) * 2;
    cubeIndex |= uint(cubeValues[2] > iso) * 4;
    cubeIndex |= uint(cubeValues[3] > iso) * 8;
    cubeIndex |= uint(cubeValues[4] > iso) * 16;
    cubeIndex |= uint(cubeValues[5] > iso) * 32;
    cubeIndex |= uint(cubeValues[6] > iso) * 64;
    cubeIndex |= uint(cubeValues[7] > iso) * 128;
    
    vec3 offset = vec3(chunkID) * float(chunkSize-1) + vec3(gl_GlobalInvocationID);
    uint edges[16] = triTable[cubeIndex];
    for (int i = 0; edges[i] != 12; i +=3){
        uint e00 = edgeConnections[edges[i]][0];
        uint e01 = edgeConnections[edges[i]][1];
        uint e10 = edgeConnections[edges[i + 1]][0];
        uint e11 = edgeConnections[edges[i + 1]][1];
        uint e20 = edgeConnections[edges[i + 2]][0];
        uint e21 = edgeConnections[edges[i + 2]][1];
        float arr[9];
        vec3 v0 = interpolate(cornerOffsets[e00],cornerOffsets[e01],1,1) + offset;
        arr[0] = v0.x;arr[1] = v0.y;arr[2] = v0.z;
        vec3 v1 = interpolate(cornerOffsets[e10],cornerOffsets[e11],1,1) + offset;
        arr[3] = v1.x;arr[4] = v1.y;arr[5] = v1.z;
        vec3 v2 = interpolate(cornerOffsets[e20],cornerOffsets[e21],1,1) + offset;
        arr[6] = v2.x;arr[7] = v2.y;arr[8] = v2.z;
        uint index = atomicCounterIncrement(counter);
        triangles.tris[index] = arr;
    }
    
}
