import QtQuick
import ".."

// A GPU's memory as a bar: used / total, warning colours when nearly full.
// For the AI menu and Settings > AI (services/Ai.qml).
Item {
    id: root
    property var gpu: null
    implicitHeight: col.implicitHeight
    implicitWidth: 300
    readonly property real frac: gpu && gpu.total ? Math.min(1, gpu.used / gpu.total) : 0
    Column {
        id: col
        width: parent.width
        spacing: 3
        Item {
            width: parent.width
            height: name.implicitHeight
            Label { id: name; text: root.gpu ? root.gpu.name : ""; font.pointSize: Theme.smallFontSize; width: parent.width - used.implicitWidth - 8 }
            Label {
                id: used
                anchors.right: parent.right
                text: root.gpu ? `${root.gpu.usedText} of ${root.gpu.totalText}` + (root.gpu.busy !== null && root.gpu.busy !== undefined ? ` · ${root.gpu.busy}% busy` : "") : ""
                color: Theme.fgSecondary
                font.pointSize: Theme.smallFontSize
            }
        }
        Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: Theme.hover
            Rectangle {
                width: parent.width * root.frac
                height: parent.height
                radius: 3
                color: root.frac > 0.92 ? Theme.bad : root.frac > 0.8 ? Theme.warn : Theme.accent
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }
}
