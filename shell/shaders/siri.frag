#version 440
// The voice assistant's glow (popups/VoiceOverlay.qml), after Apple
// Intelligence's Siri: a soft band of shifting colour hugging the screen's
// edges, breathing with your voice. Colours flow around the edge over
// time; the band widens and brightens with the microphone level.
// Compile: scripts/build-shaders.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // logical px
    float time;         // seconds
    float level;        // 0..1 microphone level (smoothed)
    float radius;       // screen corner radius, px
    float bandWidth;    // base band width, px
    float thinking;     // 1 while the assistant works: a calmer pulse
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Apple's palette: orange, pink, purple, blue, cyan.
vec3 palette(float t) {
    vec3 c0 = vec3(1.00, 0.55, 0.20);
    vec3 c1 = vec3(1.00, 0.30, 0.55);
    vec3 c2 = vec3(0.70, 0.35, 1.00);
    vec3 c3 = vec3(0.25, 0.50, 1.00);
    vec3 c4 = vec3(0.30, 0.85, 1.00);
    t = fract(t) * 5.0;
    if (t < 1.0) return mix(c0, c1, t);
    if (t < 2.0) return mix(c1, c2, t - 1.0);
    if (t < 3.0) return mix(c2, c3, t - 2.0);
    if (t < 4.0) return mix(c3, c4, t - 3.0);
    return mix(c4, c0, t - 4.0);
}

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    vec2 c = itemSize * 0.5;
    // Distance inside from the (rounded) screen edge.
    float d = -sdRoundBox(px - c, c, radius);
    // Position along the edge, 0..1, for the colour flow.
    vec2 rel = (px - c) / c;
    float ang = atan(rel.y, rel.x) / 6.2831853 + 0.5;
    float wobble = sin(ang * 18.0 + time * 2.3) * 0.5 + sin(ang * 7.0 - time * 1.7) * 0.5;
    float lv = mix(level, 0.25 + 0.15 * sin(time * 3.0), thinking);
    float w = bandWidth * (0.75 + 1.6 * lv + 0.18 * wobble);
    float band = exp(-d / max(1.0, w));
    float core = exp(-d / max(1.0, w * 0.18));
    vec3 col = palette(ang + time * 0.08);
    col = mix(col, vec3(1.0), core * 0.35);
    float a = clamp(band * (0.55 + 0.45 * lv) + core * 0.5, 0.0, 1.0);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
