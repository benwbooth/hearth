import QtQuick
import ".."

// The round ✕ that appears at a notification's top-left corner on hover
// (macOS), drawn as two strokes so it stays crisp at any scale.
MouseArea {
    id: root
    property string tooltip: "Clear"
    property bool shown: true
    implicitWidth: Math.round(20 * Theme.pt)
    implicitHeight: implicitWidth
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    visible: opacity > 0.01
    enabled: shown
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.containsMouse
            ? (Theme.dark ? Qt.rgba(0.36, 0.37, 0.40, 1) : Qt.rgba(0.88, 0.88, 0.9, 1))
            : (Theme.dark ? Qt.rgba(0.24, 0.245, 0.27, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.96))
        border.width: 1
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14)
    }
    Repeater {
        model: [45, -45]
        Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: root.width * 0.42
            height: Math.max(1.5, root.width * 0.085)
            radius: height / 2
            rotation: modelData
            antialiasing: true
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.7)
        }
    }
    Tooltip {
        anchorItem: root
        text: root.tooltip
        hovered: root.containsMouse
    }
}
