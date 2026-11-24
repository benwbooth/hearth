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
//
// Apps pad their tray pictures (ChatGPT's knot fills only the middle of its
// tile): the visible part, the marks on a tile, is zoomed to fill the slot,
// at most 1.6 times. BarButton renders these icons at twice the device
// size so the zoom stays sharp.
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

    // The main tone: the most common luminance (8 bins) of the opaque,
    // colourless pixels, so a logo's strokes don't drag a tile's tone down.
    float cnt[8];
    float sum[8];
    for (int k = 0; k < 8; k++) { cnt[k] = 0.0; sum[k] = 0.0; }
    float opaque = 0.0;
    vec4 box = vec4(1.0, 1.0, 0.0, 0.0);          // visible part: min xy, max xy
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            vec2 at = (vec2(float(i), float(j)) + 0.5) / 16.0;
            vec4 s = texture(source, at);
            if (s.a > 0.2) box = vec4(min(box.xy, at), max(box.zw, at));
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
    float mainTone = cnt[best] > 0.0 ? sum[best] / cnt[best] : 0.5;

    // A tile: over half the icon opaque, with marks that contrast with it.
    float marks = 0.0;
    vec4 markBox = vec4(1.0, 1.0, 0.0, 0.0);
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 16; j++) {
            vec2 at = (vec2(float(i), float(j)) + 0.5) / 16.0;
            vec4 s = texture(source, at);
            if (s.a > 0.5) {
                vec3 sr = s.rgb / s.a;
                if (saturation(sr) < 0.2 && abs(lum(sr) - mainTone) > 0.2) {
                    marks += 1.0;
                    markBox = vec4(min(markBox.xy, at), max(markBox.zw, at));
                }
            }
        }
    }
    float tile = step(0.5, opaque / 256.0) * step(4.0, marks);

    // Zoom the visible part (on a tile: its marks) to fill the slot, keeping
    // its shape and centre; a grid cell of slack each side, at most 1.6x.
    vec4 b = tile > 0.5 ? markBox : box;
    float span = b.z >= b.x ? max(b.z - b.x, b.w - b.y) + 2.0 / 16.0 : 1.0;
    span = clamp(span, 1.0 / 1.6, 1.0);
    vec2 centre = b.z >= b.x ? (b.xy + b.zw) * 0.5 : vec2(0.5);
    // Keep the zoomed square inside the picture.
    centre = clamp(centre, vec2(span * 0.5), vec2(1.0 - span * 0.5));
    vec2 uv = centre + (qt_TexCoord0 - 0.5) * span;

    vec4 c = texture(source, uv);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    vec3 rgb = c.rgb / c.a;                       // straight colour

    // 0 = keep (coloured), 1 = monochrome (grey).
    float w = 1.0 - smoothstep(0.12, 0.3, saturation(rgb));
    float d = abs(lum(rgb) - mainTone);
    // Ink near the main tone, cut out where it contrasts; on a tile, the
    // marks are the ink and the tile itself is cut away.
    // (A tile's soft edge and drop shadow are not marks.)
    float ink = mix(1.0 - smoothstep(0.3, 0.55, d), smoothstep(0.14, 0.34, d) * smoothstep(0.6, 0.95, c.a), tile);
    vec4 keep = vec4(rgb * c.a, c.a);
    vec4 mono = vec4(target.rgb, 1.0) * (c.a * ink);
    fragColor = mix(keep, mono, w) * qt_Opacity;
}
