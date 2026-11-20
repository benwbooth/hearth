import QtQuick
import Quickshell
import ".."
import "../services"

// A bar/tray button: icon and/or text, hover highlight and a tooltip.
// Extra children (badges, overlays) go on top of the icon.
MouseArea {
    id: root
    onPressed: ShellState.pressedIn(root)
    property string icon: ""
    property string iconFallback: "application-x-executable"
    property string text: ""
    property string tooltip: ""
    property string tooltipSub: ""
    property bool active: false
    // Bar windows may set `barHeight` / `barIconSize` (the thin menu bar).
    readonly property var hostWindow: root.QsWindow.window
    readonly property int hostHeight: hostWindow && hostWindow.barHeight ? hostWindow.barHeight : Theme.barHeight
    property int iconSize: hostWindow && hostWindow.barIconSize ? hostWindow.barIconSize : Theme.iconSize
    property color textColor: Theme.fg
    default property alias overlay: overlayItem.data

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    implicitHeight: hostHeight
    implicitWidth: Math.max(hostHeight - 12, row.implicitWidth + 12)

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.hostHeight < 36 ? 3 : 4
        anchors.bottomMargin: root.hostHeight < 36 ? 3 : 4
        radius: Theme.radius
        color: root.pressed ? Theme.pressed
             : (root.containsMouse || root.active) ? Theme.hover
             : "transparent"
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            id: iconItem
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            fallback: root.iconFallback
            implicitSize: root.iconSize
            Item {
                id: overlayItem
                anchors.fill: parent
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.textColor
        }
    }

    Tooltip {
        anchorItem: root
        text: root.tooltip
        subtext: root.tooltipSub
        hovered: root.containsMouse && !root.pressed
    }
}
