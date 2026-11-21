#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float iTime;
    vec2 res;
    float dark;
};

// Liquid: soft colour fields drifting into each other, like macOS's
// gradient wallpapers. hearth built-in wallpaper shader.
vec3 palette(float i) {
    vec3 a = mix(vec3(0.98, 0.62, 0.52), vec3(0.16, 0.10, 0.42), dark);
    vec3 b = mix(vec3(0.55, 0.70, 1.00), vec3(0.02, 0.32, 0.55), dark);
    vec3 c = mix(vec3(0.99, 0.85, 0.60), vec3(0.55, 0.12, 0.45), dark);
    vec3 d = mix(vec3(0.75, 0.62, 0.98), vec3(0.05, 0.05, 0.14), dark);
    return i < 1.0 ? a : i < 2.0 ? b : i < 3.0 ? c : d;
}
void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = iTime * 0.05;
    // Domain warp for the liquid feel.
    p += 0.12 * vec2(sin(p.y * 2.3 + t * 2.0), cos(p.x * 1.7 - t * 1.6));
    vec3 col = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        vec2 c = vec2(aspect * (0.5 + 0.42 * sin(t * (0.7 + 0.13 * fi) + fi * 1.9)),
                      0.5 + 0.40 * cos(t * (0.9 + 0.11 * fi) + fi * 2.7));
        float d = length(p - c);
        float w = 1.0 / pow(d * d + 0.04, 1.3);
        col += palette(fi) * w;
        wsum += w;
    }
    col /= wsum;
    // Fine grain keeps the gradients from banding.
    float g = fract(sin(dot(qt_TexCoord0 * res, vec2(12.9898, 78.233))) * 43758.5453);
    col += (g - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
