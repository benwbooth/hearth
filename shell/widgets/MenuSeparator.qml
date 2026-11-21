import QtQuick
import ".."

// A divider between groups of MenuItems: a 1 px line with 4 pt above and
// below, inset like the row text (macOS 26 menus).
Item {
    width: parent ? parent.width : 100
    implicitHeight: visible ? Math.round(9 * Theme.pt) : 0
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.menuTextInset
        width: parent.width - 2 * Theme.menuTextInset
        height: 1
        color: Theme.menuSeparator
    }
}
