#version 440
// Menu bar status icons in one colour, like SF Symbols (BarButton's
// `monochrome`): every pixel takes `target` at the icon's own coverage, so
// anti-aliased edges stay soft. MultiEffect's brightness +1 did this on
// premultiplied pixels and turned each half-covered edge pixel fully white,
// which thickened strokes and filled thin gaps (KeePassXC's key and padlock
// merged with its ring, 2026-11-27).
// Compile: scripts/build-shaders.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 target;        // white on a dark bar, black on a light one
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float a = texture(source, qt_TexCoord0).a * qt_Opacity;
    fragColor = vec4(target.rgb * a, a);
}
