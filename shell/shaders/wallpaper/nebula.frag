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

// Nebula: drifting stars through soft gas clouds. hearth built-in
// wallpaper shader.
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.02; a *= 0.5; } return v; }
float stars(vec2 p, float scale) {
    vec2 g = floor(p * scale), f = fract(p * scale) - 0.5;
    float h = hash(g);
    vec2 o = vec2(hash(g + 1.3), hash(g + 7.1)) - 0.5;
    float d = length(f - o * 0.7);
    return step(0.93, h) * smoothstep(0.08, 0.0, d) * (0.5 + 0.5 * h);
}
void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = iTime * 0.015;
    float n = fbm(p * 1.6 + vec2(t, -t * 0.6) + fbm(p * 2.5 - t) * 0.8);
    vec3 a = mix(vec3(0.55, 0.65, 0.95), vec3(0.18, 0.05, 0.35), dark);
    vec3 b = mix(vec3(0.98, 0.70, 0.80), vec3(0.05, 0.30, 0.45), dark);
    vec3 base = mix(vec3(0.85, 0.88, 0.97), vec3(0.005, 0.005, 0.02), dark);
    vec3 col = base + mix(a, b, smoothstep(0.3, 0.8, n)) * smoothstep(0.35, 0.95, n) * mix(0.5, 0.9, dark);
    vec2 drift = vec2(t * 0.6, 0.0);
    col += vec3(stars(p + drift * 0.5, 60.0) + stars(p + drift, 25.0) * 1.3) * mix(0.15, 1.0, dark);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
