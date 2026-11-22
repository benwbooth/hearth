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
