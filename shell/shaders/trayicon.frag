#version 440
// Menu bar tray icons from apps (bar/Tray.qml), made monochrome without
// losing their shape. Coloured pixels stay as they are. Colourless ones
// (white, grey, black) are compared with the icon's main tone, the average
// of its opaque colourless pixels: those near it are the "ink" and take the
// menu bar's text colour; those that contrast with it (a dark logo on a
// white tile) are cut out, so the bar shows through, as in a macOS template
// image. A one-tone icon (white or black) turns wholly into the text colour;
// ChatGPT's white tile with a black logo used to turn into a white square.
//
// A logo on a filled tile (most of the icon opaque in one tone, with
// contrasting marks on it: ChatGPT's knot on a white square) goes the other
// way round: the logo is the ink and the tile drops away, like the app's own
// macOS menu bar icon. Cutting thin strokes out of the tile instead left a
// light square with speckles at menu bar size.
// Compile: scripts/build-shaders.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 target;        // the menu bar's text colour
};
layout(binding = 1) uniform sampler2D source;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float saturation(vec3 rgb) {
    float mx = max(rgb.r, max(rgb.g, rgb.b));
    float mn = min(rgb.r, min(rgb.g, rgb.b));
    return mx > 0.0 ? (mx - mn) / mx : 0.0;
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    vec3 rgb = c.rgb / c.a;                       // straight colour

    // The main tone: the most common luminance (8 bins) of the opaque,
    // colourless pixels, so a logo's strokes don't drag a tile's tone down.
    float cnt[8];
    float sum[8];
    for (int k = 0; k < 8; k++) { cnt[k] = 0.0; sum[k] = 0.0; }
    float opaque = 0.0;
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            vec4 s = texture(source, (vec2(float(i), float(j)) + 0.5) / 16.0);
            if (s.a > 0.5) {
                opaque += 1.0;
                vec3 sr = s.rgb / s.a;
                if (saturation(sr) < 0.2) {
                    float l = lum(sr);
                    int k = min(7, int(l * 8.0));
                    cnt[k] += 1.0;
                    sum[k] += l;
                }
            }
        }
    }
    int best = 0;
    for (int k = 1; k < 8; k++) if (cnt[k] > cnt[best]) best = k;
    float mainTone = cnt[best] > 0.0 ? sum[best] / cnt[best] : lum(rgb);

    // A tile: over half the icon opaque, with marks that contrast with it.
    float marks = 0.0;
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            vec4 s = texture(source, (vec2(float(i), float(j)) + 0.5) / 16.0);
            if (s.a > 0.5) {
                vec3 sr = s.rgb / s.a;
                if (saturation(sr) < 0.2 && abs(lum(sr) - mainTone) > 0.2) marks += 1.0;
            }
        }
    }
    float tile = smoothstep(0.45, 0.6, opaque / 256.0) * step(2.0, marks);

    // 0 = keep (coloured), 1 = monochrome (grey).
    float w = 1.0 - smoothstep(0.12, 0.3, saturation(rgb));
    float d = abs(lum(rgb) - mainTone);
    // Ink near the main tone, cut out where it contrasts; on a tile, the
    // marks are the ink and the tile itself is cut away.
    float ink = mix(1.0 - smoothstep(0.3, 0.55, d), smoothstep(0.08, 0.3, d), tile);
    vec4 keep = vec4(rgb * c.a, c.a);
    vec4 mono = vec4(target.rgb, 1.0) * (c.a * ink);
    fragColor = mix(keep, mono, w) * qt_Opacity;
}
