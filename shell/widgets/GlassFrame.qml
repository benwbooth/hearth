import QtQuick
import ".."

// A translucent macOS-style pane (menus, popups, previews): tinted glass
// over whatever the compositor blurs behind it, a dark outline and a thin
// bright inner rim. Carries the 0.001 px text nudge for its surface.
Rectangle {
    id: root
    property color tint: Theme.glassMenu
    property bool rimVisible: true
    color: tint
    radius: Theme.popupRadius
    border.color: Theme.glassEdge
    border.width: 1
    transform: Translate { x: 0.001; y: 0.001 }

    Rectangle {
        visible: root.rimVisible
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.color: Theme.glassRim
        border.width: 1
    }
}
