import QtQuick
import ".."

// A liquid-glass pane, macOS 26 style, shared by menus, popovers, the
// Dock, its labels and tooltips so all glass looks the same. Drawn by
// shaders/glass.frag: tint over whatever the compositor blurs behind it,
// a sheen in the upper part, light gathered along the edges (lensing), a
// specular rim brightest at the top-left with its reflection at the
// bottom-right, a hairline outline and a soft drop shadow.
//
// The glass fills this item; the shadow is drawn outside it, `shadowPad`
// px on each side, so the window around it needs that much room (keep the
// window a fixed size: never grow it per frame). Children go on top of the
// glass. Carries the 0.001 px text nudge for its surface.
Item {
    id: root
    property color tint: Theme.glassMenu
    property real radius: Theme.menuRadius
    property bool rimVisible: true
    property bool shadow: true
    property real shadowBlur: Theme.menuShadowBlur
    property real shadowY: Theme.menuShadowY
    property real shadowOpacity: Theme.shadowOpacity
    property real rim: Theme.specular
    property real glow: Theme.glassGlow
    property real sheen: Theme.glassSheen
    // Room the shadow needs around the pane (top is smaller: it falls down).
    readonly property real shadowPad: shadow ? Math.ceil(shadowBlur + Math.abs(shadowY)) : 2
    transform: Translate { x: 0.001; y: 0.001 }

    ShaderEffect {
        id: fx
        x: -root.shadowPad
        y: -root.shadowPad
        width: root.width + 2 * root.shadowPad
        height: root.height + 2 * root.shadowPad
        visible: root.width > 0 && root.height > 0
        fragmentShader: "../shaders/glass.frag.qsb"
        readonly property size itemSize: Qt.size(width, height)
        readonly property rect pane: Qt.rect(root.shadowPad, root.shadowPad, root.width, root.height)
        readonly property real radius: Math.min(root.radius, root.width / 2, root.height / 2)
        readonly property color tint: root.tint
        readonly property color shadowColor: Qt.rgba(0, 0, 0, root.shadow ? root.shadowOpacity : 0)
        readonly property real shadowBlur: Math.max(1, root.shadowBlur)
        readonly property real shadowY: root.shadowY
        readonly property real rim: root.rimVisible ? root.rim : 0
        readonly property real glow: root.rimVisible ? root.glow : 0
        readonly property real sheen: root.rimVisible ? root.sheen : 0
        readonly property real outline: root.rimVisible ? 1 : 0
        readonly property real dark: Theme.dark ? 1 : 0
    }
}
