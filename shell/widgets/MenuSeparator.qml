import QtQuick
import ".."

// A divider line between groups of MenuItems.
Item {
    width: parent ? parent.width : 100
    implicitHeight: visible ? 9 : 0
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 8
        width: parent.width - 16
        height: 1
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
    }
}
