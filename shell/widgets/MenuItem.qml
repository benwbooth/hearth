import QtQuick
import ".."

// One row in a hearth popup menu.
MouseArea {
    id: root
    property string text: ""
    property string icon: ""
    property bool checked: false
    property bool checkable: false
    property string shortcut: ""
    signal triggered()

    width: parent ? parent.width : implicitWidth
    implicitWidth: row.implicitWidth + 16 + (shortcut !== "" ? shortcutWidth + 24 : 0)
    readonly property real shortcutWidth: shortcut !== "" ? shortcut.length * 7 + 8 : 0
    implicitHeight: visible ? 26 : 0
    hoverEnabled: true
    onClicked: root.triggered()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.enabled && (root.pressed || root.containsMouse) ? Theme.accent : "transparent"
    }
    Label {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.shortcut !== ""
        text: root.shortcut
        color: root.enabled && root.containsMouse ? Theme.accentText : Theme.fgDim
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
            color: !root.enabled ? Theme.fgDim : root.containsMouse ? Theme.accentText : Theme.fg
        }
    }
}
