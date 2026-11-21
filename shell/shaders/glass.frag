#version 440
// hearth's liquid glass: one rounded pane (continuous corners) with its
// tint, a sheen in its upper part, light concentrated along the edges
// (lensing), a specular rim lit from the top-left and reflected at the
// bottom-right, a hairline outline and a soft drop shadow outside it.
// Everything is computed from the pane's signed distance field, so it is
// antialiased at any scale. The compositor supplies the blur behind it.
// Compile: scripts/build-shaders.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item, logical px
    vec4 pane;          // x, y, w, h of the glass inside the item
    float radius;       // corner radius, logical px
    vec4 tint;          // straight alpha
    vec4 shadowColor;   // straight alpha; a = peak opacity
    float shadowBlur;   // px
    float shadowY;      // px, downwards
    float rim;          // specular rim strength 0..1
    float glow;         // edge lensing strength 0..1
    float sheen;        // top sheen strength 0..1
    float outline;      // dark hairline 0..1
    float dark;         // 1 in dark mode
};

// Rounded box with continuous ("squircle") corners: a p-norm corner
// (n = 2.6) on a radius stretched to match the visible size of a circular
// one, like Apple's continuous corner curve.
float sdPane(vec2 p, vec2 b, float r) {
    r = min(r * 1.18, min(b.x, b.y));
    vec2 q = abs(p) - b + r;
    vec2 m = max(q, 0.0);
    const float n = 2.6;
    float c = pow(pow(m.x, n) + pow(m.y, n), 1.0 / n);
    return min(max(q.x, q.y), 0.0) + c - r;
}

vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 half_ = pane.zw * 0.5;
    vec2 c = pane.xy + half_;
    vec2 lp = p - c;
    float d = sdPane(lp, half_, radius);
    float aa = max(fwidth(d), 0.0001);

    // Outward normal from the distance field.
    vec2 e = vec2(0.5, 0.0);
    vec2 nrm = normalize(vec2(sdPane(lp + e.xy, half_, radius) - sdPane(lp - e.xy, half_, radius),
                              sdPane(lp + e.yx, half_, radius) - sdPane(lp - e.yx, half_, radius)) + 1e-6);
    // Light from above-left of the screen; its reflection lights the
    // opposite (bottom-right) rim less strongly.
    vec2 L = normalize(vec2(-0.55, -0.83));
    float lit = pow(max(dot(nrm, L), 0.0), 1.6);
    float refl = pow(max(dot(nrm, -L), 0.0), 2.2);
    float dir = 0.18 + 0.95 * lit + 0.45 * refl;

    float cover = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, d);

    // Glass body.
    vec4 col = vec4(tint.rgb * tint.a, tint.a);
    // Sheen: light caught in the upper part of the pane.
    float fy = clamp((p.y - pane.y) / max(1.0, min(pane.w, 80.0)), 0.0, 1.0);
    float sh = sheen * (1.0 - smoothstep(0.0, 0.9, fy));
    col = over(vec4(vec3(sh), sh), col);
    // Lensing: the glass gathers light along its edges, fading inwards.
    float g = glow * exp(d / 5.0) * dir;
    col = over(vec4(vec3(g), g) * 0.5, col);
    // Specular rim: a ~1.2 px line just inside the edge.
    float band = smoothstep(-1.6 - aa, -1.6 + aa, d) * (1.0 - smoothstep(-aa, 0.0, d + 0.0));
    float rimA = clamp(rim * band * dir, 0.0, 1.0);
    col = over(vec4(vec3(rimA), rimA), col);
    col *= cover;

    // Hairline outline just outside the edge (separates glass from
    // similar backgrounds), then the drop shadow.
    float line = outline * (smoothstep(-aa, 0.0, d) - smoothstep(0.9, 0.9 + aa, d));
    vec4 o = vec4(0.0, 0.0, 0.0, line * (dark > 0.5 ? 0.38 : 0.14));
    float sd = sdPane(lp - vec2(0.0, shadowY), half_, radius);
    float s = 1.0 - smoothstep(-shadowBlur * 0.35, shadowBlur, sd);
    s = s * s * shadowColor.a;
    vec4 shadow = vec4(shadowColor.rgb * s, s);
    vec4 outside = over(o, shadow) * (1.0 - cover);

    fragColor = (col + outside) * qt_Opacity;
}
