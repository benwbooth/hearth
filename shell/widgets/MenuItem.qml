import QtQuick
import ".."

// One row in a hearth popup menu.
MouseArea {
    id: root
    property string text: ""
    property string icon: ""
    property bool checked: false
    property bool checkable: false
    signal triggered()

    width: parent ? parent.width : implicitWidth
    implicitWidth: row.implicitWidth + 16
    implicitHeight: visible ? 30 : 0
    hoverEnabled: true
    onClicked: root.triggered()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.pressed ? Theme.pressed : root.containsMouse ? Theme.hover : "transparent"
    }
    Row {
        id: row
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 16
            name: root.icon
            visible: root.icon !== "" && !root.checkable
        }
        // Drawn, not an icon: Breeze's checkbox-symbolic is a tick and
        // checkbox-checked-symbolic a pencil.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.checkable
            width: 16
            height: 16
            radius: 3
            color: root.checked ? Theme.accent : "transparent"
            border.color: root.checked ? Theme.accent : Theme.fgDim
            Label {
                anchors.centerIn: parent
                visible: root.checked
                text: "✓"
                color: Theme.bg
                font.weight: Font.Bold
                font.pointSize: Theme.smallFontSize
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
        }
    }
}
