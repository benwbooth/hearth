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
    //
    // Neither of Qt's paths rasterises at exactly N device pixels at 4/3:
    // the image://icon provider renders at Qt's integer ratio (2: 44 px for
    // 22, squeezed 2:1, each 1 px stroke smeared over two pixels), and a
    // file SVG renders at sourceSize x 4/3 (sourceSize is whole points, and
    // 22 px is 16.5 pt). So a Breeze icon is loaded from its file
    // (services/IconIndex.qml) at a design size whose size in points is
    // whole: at 4/3 the 24 px design (the 22 px artwork with a 1 px margin)
    // at 18 pt, exactly 24 device pixels, drawn 1:1.
    property real crispSize: 0
    // The scale of the screen the icon is on (the Screen attached property
    // where the item has no QsWindow).
    readonly property real dpr: {
        const w = root.QsWindow.window;
        const sn = w && w.screen ? w.screen.name : root.Screen.name;
        const o = sn ? Displays.live[sn] : null;
        if (o && o.logical && o.logical.scale > 0) return o.logical.scale;
        const d = w && w.screen ? w.screen.devicePixelRatio : root.Screen.devicePixelRatio;
        return d > 0 ? d : 1;
    }
    readonly property bool themeName: name !== "" && !name.startsWith("data:") && !name.startsWith("/") && !name.includes("://")
    // The Breeze design size whose points are whole, nearest to the wanted
    // size (0: none; then the nearest design size through Qt's lookup).
    readonly property int filePx: {
        if (crispSize <= 0 || !themeName || !IconIndex.loaded) return 0;
        const px = crispSize * dpr;
        let best = 0;
        for (const d of IconIndex.sizes(name, Theme.dark)) {
            const pt = d / dpr;
            if (Math.abs(pt - Math.round(pt)) > 0.01) continue;
            if (!best || Math.abs(d - px) < Math.abs(best - px)) best = d;
        }
        return best;
    }
    readonly property int crispPx: {
        if (crispSize <= 0) return 0;
        if (filePx > 0) return filePx;
        const px = crispSize * dpr;
        let best = 16;
        for (const d of [16, 22, 24, 32]) if (Math.abs(d - px) < Math.abs(best - px)) best = d;
        return best;
    }
    Binding { target: root; property: "implicitSize"; when: root.crispPx > 0; value: root.crispPx / root.dpr }
    // A file SVG takes sourceSize in points (Qt multiplies by the scale).
    Binding {
        target: root.backer; property: "sourceSize"; when: root.filePx > 0
        value: Qt.size(Math.round(root.filePx / root.dpr), Math.round(root.filePx / root.dpr))
    }
    Binding { target: root; property: "rasterSize"; when: root.crispPx > 0 && root.filePx === 0; value: root.crispPx }
    // (BarButton sets its own transform and snaps itself.)
    transform: Translate { id: crispSnap }
    function snap() {
        if (crispPx <= 0 || !visible) return;
        // Where layout puts the icon in its window, without transforms: a
        // menu opens with a Scale animation (BarPopup), and mapToItem() in
        // the middle of it gave a position the icon then kept, between
        // device pixels.
        let rx = 0, ry = 0;
        for (let it = root; it; it = it.parent) { rx += it.x; ry += it.y; }
        crispSnap.x = Math.round(rx * dpr) / dpr - rx;
        crispSnap.y = Math.round(ry * dpr) / dpr - ry;
    }
    onXChanged: if (crispPx > 0) Qt.callLater(snap)
    onYChanged: if (crispPx > 0) Qt.callLater(snap)
    onCrispPxChanged: Qt.callLater(snap)
    onDprChanged: if (crispPx > 0) Qt.callLater(snap)
    onVisibleChanged: if (crispPx > 0) Qt.callLater(snap)
    Component.onCompleted: if (crispPx > 0) Qt.callLater(snap)
    source: {
        const n = root.name;
        if (!n) return Quickshell.iconPath(root.fallback, true);
        if (n.startsWith("data:")) return n;
        if (n.startsWith("/") || n.includes("://")) return n.startsWith("/") ? "file://" + n : n;
        if (root.filePx > 0) return "file://" + IconIndex.path(n, root.filePx, Theme.dark);
        // The shell's icon theme is Breeze Dark (pragma); in light mode the
        // monochrome icons come from Breeze (services/IconIndex.qml).
        if (!Theme.dark) {
            const light = IconIndex.lookup(n);
            if (light) return "file://" + light;
        }
        return Quickshell.iconPath(n, root.fallback);
    }
}
