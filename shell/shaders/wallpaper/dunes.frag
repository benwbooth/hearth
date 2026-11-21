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

// Dunes: layered hills under a sky that slowly turns, like macOS Sonoma's
// landscape. hearth built-in wallpaper shader.
float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) { float i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }
float ridge(float x, float seed) {
    return 0.55 * noise(x * 1.3 + seed) + 0.3 * noise(x * 3.1 + seed * 2.0) + 0.15 * noise(x * 7.0 + seed * 3.0);
}
void main() {
    vec2 uv = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y);
    float aspect = res.x / max(res.y, 1.0);
    float x = uv.x * aspect;
    float t = iTime * 0.01;
    vec3 skyHi = mix(vec3(0.45, 0.62, 0.90), vec3(0.06, 0.07, 0.20), dark);
    vec3 skyLo = mix(vec3(1.00, 0.80, 0.62), vec3(0.55, 0.25, 0.35), dark);
    vec3 col = mix(skyLo, skyHi, pow(uv.y, 0.7));
    // Sun / moon.
    vec2 sun = vec2(aspect * (0.7 + 0.05 * sin(t * 3.0)), 0.62);
    float sd = length(vec2(x, uv.y) - sun);
    col += mix(vec3(1.0, 0.9, 0.7), vec3(0.9, 0.85, 0.8), dark) * (smoothstep(0.06, 0.055, sd) + 0.25 * exp(-sd * 6.0));
    // Seven layers, far to near, each drifting a little faster.
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float depth = fi / 6.0;
        float h = 0.48 - depth * 0.38 + 0.16 * (ridge(x * (0.6 + depth) + t * (1.0 + 4.0 * depth), fi * 7.3) - 0.5);
        vec3 far = mix(vec3(0.92, 0.70, 0.60), vec3(0.32, 0.18, 0.32), dark);
        vec3 near = mix(vec3(0.42, 0.24, 0.30), vec3(0.04, 0.03, 0.07), dark);
        vec3 lc = mix(far, near, depth);
        // Lit crest.
        lc += mix(vec3(0.08, 0.05, 0.02), vec3(0.03, 0.02, 0.05), dark) * smoothstep(0.015, 0.0, h - uv.y);
        col = mix(col, lc, smoothstep(h + 0.0015, h - 0.0015, uv.y));
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
