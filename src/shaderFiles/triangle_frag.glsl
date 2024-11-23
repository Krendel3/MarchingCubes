#version 410 core
uniform vec3 camPos;
uniform vec3 lightDir;

flat in vec3 diffuse_color;
flat in vec3 f_normal;

in vec3 worldPos;

out vec4 f_Color;
void main() {
    float specularStrength = 0.1;
    float specularPow = 26.0;
    vec3 objectColor = vec3(0.9,0.9,1.0);
    vec3 ambient = vec3(0.15,0.15,0.18);

    //speculat calculation
    vec3 reflectedVector = normalize(reflect(lightDir, f_normal));
    vec3 worldToEyeVector = normalize(camPos - worldPos);
    float spec = max(0,dot(worldToEyeVector, reflectedVector));
    spec = pow(spec, specularPow);
    vec3 specular = vec3(spec * specularStrength);

    //Final color calculation
    vec3 result = (diffuse_color + specular + ambient) * objectColor;
    f_Color = vec4(result,1.0);
}
