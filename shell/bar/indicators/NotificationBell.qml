import QtQuick
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// The bell in the menu bar: click opens Notification Center
// (services/Notifications.qml), middle-click toggles Do Not Disturb; the
// badge counts the notifications waiting there.
BarButton {
    id: root
    readonly property int count: Notifications.count
    readonly property bool dnd: Notifications.dnd

    implicitWidth: 30
    icon: root.dnd ? "notifications-disabled" : "notifications"
    tooltip: root.dnd ? "Notification Center (Do Not Disturb is on)" : "Notification Center"
    tooltipSub: (root.count > 0 ? (root.count === 1 ? "1 notification" : root.count + " notifications") : "No notifications")
        + " · middle-click: Do Not Disturb"
    active: Notifications.centerOpen

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) Notifications.toggleDnd();
        else Notifications.toggleCenter();
    }

    Rectangle {
        visible: root.count > 0
        parent: root
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 2
        anchors.topMargin: 8
        height: 14
        width: Math.max(14, badgeText.implicitWidth + 6)
        radius: 7
        color: root.dnd ? Theme.fgDim : Theme.accent
        Label {
            id: badgeText
            anchors.centerIn: parent
            text: root.count > 99 ? "99+" : String(root.count)
            color: Theme.bg
            font.pointSize: Theme.smallFontSize - 1
            font.weight: Font.Bold
        }
    }
}
