import QtQuick
import ".."

// A macOS-style push button for windows (Settings, dialogs). `primary`
// fills it with the accent colour (the default action). `tooltip` shows on
// hover.
MouseArea {
    id: root
    property string text
    property string tooltip: ""
    property bool primary: false
    property bool destructive: false
    implicitWidth: Math.max(72, lbl.implicitWidth + 28)
    implicitHeight: 28
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    opacity: enabled ? 1 : 0.4
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.primary ? (root.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent)
             : root.pressed ? Theme.pressed : root.containsMouse ? Theme.hover
             : (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
        border.color: root.primary ? "transparent" : Theme.border
    }
    Label {
        id: lbl
        anchors.centerIn: parent
        text: root.text
        color: root.primary ? Theme.accentText : root.destructive ? Theme.bad : Theme.fg
    }
    Tooltip {
        anchorItem: root
        text: root.tooltip
        hovered: root.containsMouse && !root.pressed
    }
}
