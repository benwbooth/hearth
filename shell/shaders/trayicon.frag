#version 440
// Menu bar tray icons from apps (bar/Tray.qml): recolour the colourless
// pixels (white, grey, black: an app's "template" icon drawn for some other
// panel) to the menu bar's text colour (dark greys to its opposite), and leave coloured pixels alone, so
// a white icon turns black on a light bar while a colourful one stays as
// it is. Compile: scripts/build-shaders.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 target;        // the menu bar's text colour
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) { fragColor = vec4(0.0); return; }
    vec3 rgb = c.rgb / c.a;                       // straight colour
    float mx = max(rgb.r, max(rgb.g, rgb.b));
    float mn = min(rgb.r, min(rgb.g, rgb.b));
    float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
    // 0 = keep (coloured), 1 = recolour (grey).
    float w = 1.0 - smoothstep(0.12, 0.3, sat);
    // Light greys take the text colour and dark greys its opposite, so an
    // icon drawn in both (Kog's white gear on a black disc) keeps its shape
    // instead of flattening into one blob of text colour.
    vec3 grey = mix(vec3(1.0) - target.rgb, target.rgb, mx);
    vec3 outRgb = mix(rgb, grey, w);
    fragColor = vec4(outRgb * c.a, c.a) * qt_Opacity;
}
