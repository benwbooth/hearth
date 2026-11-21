import QtQuick
import Quickshell
import ".."
import "../services"

// A liquid-glass pane, macOS 26 style, shared by menus, popovers, the
// Dock, its labels and tooltips so all glass looks the same. Drawn by
// shaders/glass.frag: tint over whatever the compositor blurs behind it,
// a sheen in the upper part, light gathered along the edges (lensing), a
// specular rim brightest at the top-left with its reflection at the
// bottom-right, a hairline outline and a soft drop shadow.
//
// On arbor with real glass (services/RealGlass.qml, Settings > Appearance
// > Real glass) the pane also reports its shape to the compositor, which
// draws the backdrop refracted, blurred and lit under it; the shell then
// leaves out its own sheen and lensing, draws a lighter tint and only a
// faint rim, and keeps the outline and shadow.
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
    property bool shadow: Theme.glassShadows
    property real shadowBlur: Theme.menuShadowBlur
    property real shadowY: Theme.menuShadowY
    property real shadowOpacity: Theme.shadowOpacity
    property real rim: Theme.specular
    property real glow: Theme.glassGlow
    property real sheen: Theme.glassSheen
    // Real glass: report this pane to the compositor (arbor).
    property bool compositorGlass: true
    // "Regular" (frosted: menus, popovers, the Dock) or "Clear" (media).
    property string glassVariant: "Regular"
    // Extra arbor GlassParams (e.g. { blur_radius: 4 }).
    property var glassParams: ({})
    readonly property bool realGlass: compositorGlass && RealGlass.active
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
        // The compositor's glass already tints, saturates and lights the
        // backdrop: only a lighter tint for legibility on top.
        readonly property color tint: root.realGlass
            ? Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tint.a * Theme.realGlassTint)
            : root.tint
        readonly property color shadowColor: Qt.rgba(0, 0, 0, root.shadow ? root.shadowOpacity : 0)
        readonly property real shadowBlur: Math.max(1, root.shadowBlur)
        readonly property real shadowY: root.shadowY
        readonly property real rim: root.rimVisible ? root.rim * (root.realGlass ? 0.35 : 1) : 0
        readonly property real glow: root.rimVisible && !root.realGlass ? root.glow : 0
        readonly property real sheen: root.rimVisible && !root.realGlass ? root.sheen : 0
        readonly property real outline: root.rimVisible ? 1 : 0
        readonly property real dark: Theme.dark ? 1 : 0
    }

    // --- real glass reporting ---
    readonly property var hostWindow: root.QsWindow.window

    function report() {
        const win = root.hostWindow;
        if (!root.realGlass || !win || !win.visible || !root.visible || root.width <= 0 || root.height <= 0) {
            RealGlass.remove(root);
            return;
        }
        // Effective opacity (menus and tooltips fade in and out).
        let op = 1;
        for (let it = root; it; it = it.parent) op *= it.opacity;
        if (op < 0.01) { RealGlass.remove(root); return; }
        // Window coordinates after every transform (a popup's grow, the
        // Dock's slide and magnification).
        const p0 = root.mapToItem(null, 0, 0);
        const p1 = root.mapToItem(null, root.width, root.height);
        const x = Math.min(p0.x, p1.x), y = Math.min(p0.y, p1.y);
        const w = Math.abs(p1.x - p0.x), h = Math.abs(p1.y - p0.y);
        // Slid entirely out of its window (a hidden Dock): nothing to draw.
        if (x >= win.width || y >= win.height || x + w <= 0 || y + h <= 0) {
            RealGlass.remove(root);
            return;
        }
        const k = w / root.width;
        const r3 = v => Math.round(v * 1000) / 1000;
        const params = Object.assign({
            variant: root.glassVariant,
            strength: r3(RealGlass.strength),
            opacity: r3(Math.min(1, op))
        }, root.glassParams);
        RealGlass.put(root, win, {
            x: r3(x), y: r3(y), width: r3(w), height: r3(h),
            radius: r3(Math.min(root.radius, root.width / 2, root.height / 2) * k),
            params: params
        });
    }

    // Once per rendered frame of the window: catches every move, resize,
    // transform and fade without polling while nothing changes.
    Connections {
        target: root.realGlass ? root.Window.window : null
        ignoreUnknownSignals: true
        function onAfterAnimating() { root.report(); }
    }
    Connections {
        target: root.hostWindow
        ignoreUnknownSignals: true
        function onVisibleChanged() { Qt.callLater(root.report); }
    }
    onRealGlassChanged: report()
    onVisibleChanged: Qt.callLater(report)
    onWidthChanged: Qt.callLater(report)
    onHeightChanged: Qt.callLater(report)
    Component.onCompleted: Qt.callLater(report)
    Component.onDestruction: RealGlass.remove(root)
}
