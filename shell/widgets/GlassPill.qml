import QtQuick
import ".."

// A subtle glass capsule button (notification actions, Notification
// Center's header): a faint fill with a bright hairline at the top edge,
// lighter on hover. Text and/or an icon; `tooltip` on hover.
MouseArea {
    id: root
    property string text: ""
    property string icon: ""
    property string tooltip: ""
    property bool checked: false
    property real fontSize: Theme.macPt(12)
    property real pad: Math.round(10 * Theme.pt)
    // Longer text is elided.
    property real maxTextWidth: Math.round(200 * Theme.pt)
    implicitHeight: Math.round(24 * Theme.pt)
    implicitWidth: Math.max(implicitHeight, row.implicitWidth + 2 * pad)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent
             : root.pressed ? Theme.glassPillPressed : root.containsMouse ? Theme.glassPillHover : Theme.glassPill
        Behavior on color { ColorAnimation { duration: 90 } }
        // Light on the top edge, like the cards' rim.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: root.checked ? Qt.rgba(1, 1, 1, 0.25) : Theme.glassPillRim
            opacity: 0.9
        }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(5 * Theme.pt)
        Icon {
            visible: root.icon !== ""
            name: root.icon
            implicitSize: Math.round(14 * Theme.pt)
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            visible: root.text !== ""
            text: root.text
            anchors.verticalCenter: parent.verticalCenter
            font.pointSize: root.fontSize
            font.weight: Font.Medium
            color: root.checked ? Theme.accentText : Theme.fg
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.maxTextWidth)
        }
    }
    Tooltip {
        anchorItem: root
        text: root.tooltip
        hovered: root.containsMouse && !root.pressed
    }
}
