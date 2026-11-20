import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// A monochrome logo from shell/assets/<name>.svg, drawn in `color` (like the
// Apple logo in the macOS menu bar). The SVGs use the placeholder FILL.
Item {
    id: root
    property string name: "nixos"
    property color color: Theme.fg
    property int size: 16
    implicitWidth: size
    implicitHeight: size
    readonly property bool wanted: name !== "" && name !== "none"
    visible: wanted

    FileView {
        id: file
        path: root.wanted ? Quickshell.shellDir + "/assets/" + root.name + ".svg" : ""
        printErrors: false
        onLoaded: root.svg = text()
    }
    property string svg: ""
    Image {
        id: img
        anchors.fill: parent
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        source: {
            const t = root.svg;
            if (!t) return "";
            const c = Qt.rgba(root.color.r, root.color.g, root.color.b, 1).toString();
            return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(t.split("FILL").join(c));
        }
    }
}
