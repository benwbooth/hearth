import QtQuick
import Quickshell
import Quickshell.Widgets
import "../services"
import ".."

// Theme icon by name (or an absolute path / image:// URL), with a fallback.
IconImage {
    id: root
    property string name: ""
    property string fallback: "application-x-executable"
    implicitSize: 22
    asynchronous: true
    // Device pixels to rasterise a scalable icon at (0: the shown size,
    // which Qt then scales again at a fractional scale). See BarButton.
    property real rasterSize: 0
    Binding { target: root.backer; property: "sourceSize"; when: root.rasterSize > 0; value: Qt.size(root.rasterSize, root.rasterSize) }

    // Pixel-exact (menus): `crispSize` is the wanted logical size. The icon
    // is drawn at the icon theme's design size nearest to it in device
    // pixels (16/22/24/32), rasterised at exactly that and placed on the
    // device pixel grid. At 4/3 a 16 pt icon was 21.33 device pixels: a
    // 16 px Breeze symbol stretched between pixels, its strokes jagged.
    property real crispSize: 0
    readonly property real dpr: {
        const w = root.QsWindow.window;
        const sc = w && w.screen ? w.screen : null;
        const o = sc ? Displays.live[sc.name] : null;
        if (o && o.logical && o.logical.scale > 0) return o.logical.scale;
        return sc && sc.devicePixelRatio > 0 ? sc.devicePixelRatio : 1;
    }
    readonly property int crispPx: {
        if (crispSize <= 0) return 0;
        const px = crispSize * dpr;
        let best = 16;
        for (const d of [16, 22, 24, 32]) if (Math.abs(d - px) < Math.abs(best - px)) best = d;
        return best;
    }
    Binding { target: root; property: "implicitSize"; when: root.crispPx > 0; value: root.crispPx / root.dpr }
    Binding { target: root; property: "rasterSize"; when: root.crispPx > 0; value: root.crispPx }
    // (BarButton sets its own transform and snaps itself.)
    transform: Translate { id: crispSnap }
    function snap() {
        if (crispPx <= 0 || !visible) return;
        const p = mapToItem(null, 0, 0);
        const rx = p.x - crispSnap.x, ry = p.y - crispSnap.y;
        crispSnap.x = Math.round(rx * dpr) / dpr - rx;
        crispSnap.y = Math.round(ry * dpr) / dpr - ry;
    }
    onXChanged: if (crispPx > 0) Qt.callLater(snap)
    onYChanged: if (crispPx > 0) Qt.callLater(snap)
    onCrispPxChanged: Qt.callLater(snap)
    onVisibleChanged: if (crispPx > 0) Qt.callLater(snap)
    Component.onCompleted: if (crispPx > 0) Qt.callLater(snap)
    source: {
        const n = root.name;
        if (!n) return Quickshell.iconPath(root.fallback, true);
        if (n.startsWith("data:")) return n;
        if (n.startsWith("/") || n.includes("://")) return n.startsWith("/") ? "file://" + n : n;
        // The shell's icon theme is Breeze Dark (pragma); in light mode the
        // monochrome icons come from Breeze (services/IconIndex.qml).
        if (!Theme.dark) {
            const light = IconIndex.lookup(n);
            if (light) return "file://" + light;
        }
        return Quickshell.iconPath(n, root.fallback);
    }
}
