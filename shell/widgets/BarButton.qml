import QtQuick
import ".."

// A bar/tray button: icon and/or text, hover highlight and a tooltip.
// Extra children (badges, overlays) go on top of the icon.
MouseArea {
    id: root
    property string icon: ""
    property string iconFallback: "application-x-executable"
    property string text: ""
    property string tooltip: ""
    property string tooltipSub: ""
    property bool active: false
    property int iconSize: Theme.iconSize
    property color textColor: Theme.fg
    default property alias overlay: overlayItem.data

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    implicitHeight: Theme.barHeight
    implicitWidth: Math.max(Theme.barHeight - 12, row.implicitWidth + 12)

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
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
