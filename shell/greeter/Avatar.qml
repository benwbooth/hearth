import QtQuick
import Quickshell.Widgets
import "../widgets"
import ".."

// A round user picture (AccountsService icon), else the initials.
Item {
    id: root
    property var user: null
    property int size: 76
    property bool ring: false
    width: size
    height: size

    Rectangle {
        anchors.centerIn: parent
        width: root.size + 8; height: width; radius: width / 2
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.75)
        border.width: 2
        opacity: root.ring ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.22)
        border.color: Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        Image {
            id: img
            anchors.fill: parent
            visible: status === Image.Ready
            source: root.user && root.user.icon ? "file://" + root.user.icon : ""
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
        }
        Label {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: Greeter.initials(root.user)
            color: "white"
            font.family: Theme.displayFontFamily
            font.pointSize: 0.75 * Math.max(1, Math.round(root.size * 0.38))
            font.weight: Font.Medium
        }
    }
}
