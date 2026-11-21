import QtQuick
import QtQuick.Layouts
import ".."

// A rounded group of rows in the Settings window, like macOS settings.
Rectangle {
    default property alias rows: col.data
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 8
    radius: Theme.popupRadius
    color: Theme.bgAlt
    border.color: Theme.border
    Column {
        id: col
        x: 14
        y: 4
        width: parent.width - 28
    }
}
