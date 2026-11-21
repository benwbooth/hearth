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

// Aurora: slow curtains of northern lights over a night sky (a light
// dawn sky in light mode). hearth built-in wallpaper shader.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 17.0; a *= 0.5; }
    return v;
}
void main() {
    vec2 uv = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y);
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = iTime * 0.04;
    vec3 skyTop = mix(vec3(0.62, 0.74, 0.92), vec3(0.01, 0.02, 0.06), dark);
    vec3 skyLow = mix(vec3(0.98, 0.84, 0.74), vec3(0.03, 0.07, 0.13), dark);
    vec3 col = mix(skyLow, skyTop, smoothstep(0.0, 1.0, uv.y));
    // Stars (night only): single pixels in a sparse grid.
    vec2 fp = uv * res / 3.0;
    vec2 sg = floor(fp);
    float sh = hash(sg);
    float s = step(0.992, sh) * smoothstep(0.32, 0.0, length(fract(fp) - 0.5))
            * (0.55 + 0.45 * sin(iTime * (0.8 + sh * 2.0) + sh * 40.0));
    col += vec3(s) * dark * smoothstep(0.2, 0.7, uv.y);
    // Curtains: a wavy lower edge with light rising from it in rays.
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float x = p.x + fk * 1.7;
        float edge = 0.40 + 0.10 * fk
            + 0.07 * sin(x * (1.1 + 0.3 * fk) + t * (2.0 + fk))
            + 0.05 * sin(x * 2.7 - t * 1.3 + fk * 2.0)
            + 0.12 * (fbm(vec2(x * 0.8, t * 0.5 + fk * 3.0)) - 0.5);
        float d = uv.y - edge;
        float rays = fbm(vec2(x * 9.0 + 0.6 * sin(t * 2.0 + x), t * 1.5 + fk * 5.0));
        rays = pow(rays, 2.2) * 2.6;
        float body = smoothstep(-0.012, 0.004, d) * exp(-max(d, 0.0) * (7.0 + 2.0 * fk));
        float glow = exp(-abs(d) * 30.0) * 0.6;
        vec3 low = k == 1 ? vec3(0.10, 0.85, 0.85) : vec3(0.12, 0.95, 0.50);
        vec3 high = k == 2 ? vec3(0.85, 0.30, 0.75) : vec3(0.45, 0.30, 0.95);
        vec3 c = mix(low, high, smoothstep(0.02, 0.22, d));
        float fade = 0.55 + 0.45 * sin(t * 1.7 + fk * 2.1 + x * 0.5);
        col += c * (body * rays + glow * rays * 0.5) * fade * mix(0.45, 0.85, dark);
    }
    // Horizon hills.
    float hill = 0.16 + 0.05 * fbm(vec2(p.x * 1.5, 2.0)) + 0.03 * sin(p.x * 2.0);
    col = mix(col, mix(vec3(0.33, 0.38, 0.48), vec3(0.005, 0.01, 0.02), dark), smoothstep(hill + 0.003, hill, uv.y));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
