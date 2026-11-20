import QtQuick
import ".."

// macOS-style switch.
MouseArea {
    id: root
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 38
    implicitHeight: 22
    cursorShape: Qt.PointingHandCursor
    onClicked: toggled(!checked)
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.15))
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
}
