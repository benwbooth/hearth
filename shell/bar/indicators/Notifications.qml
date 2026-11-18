import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../widgets"
import "../../services"
import "../.."

// Notification bell: unread count badge, a crossed-out bell while Do Not
// Disturb is on. Left click opens the history (grouped by app, newest
// first); middle click toggles Do Not Disturb.
Indicator {
    id: root
    icon: ShellState.doNotDisturb ? "notifications-disabled" : "notifications"
    tooltip: ShellState.doNotDisturb ? "Do Not Disturb" : "Notifications"
    tooltipSub: {
        const n = Notifs.history.length;
        const u = Notifs.unreadCount;
        return (n === 0 ? "No notifications" : n + " notification" + (n === 1 ? "" : "s"))
            + (u > 0 ? ", " + u + " unread" : "") + "\nMiddle click: Do Not Disturb";
    }
    onMiddleClicked: ShellState.doNotDisturb = !ShellState.doNotDisturb

    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) Notifs.markRead(); }
    }
    Connections {
        target: Notifs
        // Arrivals while the history is open are read already.
        function onNotified() { if (root.popup.open) Notifs.markRead(); }
    }

    // Unread badge.
    Rectangle {
        visible: Notifs.unreadCount > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -5
        anchors.topMargin: -4
        width: Math.max(14, badgeText.implicitWidth + 6)
        height: 14
        radius: 7
        color: ShellState.doNotDisturb ? Theme.fgDim : Theme.accent
        Label {
            id: badgeText
            anchors.centerIn: parent
            text: Notifs.unreadCount > 99 ? "99+" : Notifs.unreadCount
            color: Theme.bg
            font.pointSize: 7
            font.weight: Font.Bold
        }
    }

    popupContent: ColumnLayout {
        id: pane
        implicitWidth: 420
        spacing: 8
        property double now: Date.now()
        Timer {
            interval: 30000
            running: true
            repeat: true
            onTriggered: pane.now = Date.now()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                Layout.fillWidth: true
                text: "Notifications"
                font.weight: Font.DemiBold
                font.pointSize: Theme.fontSize + 1
            }
            BarButton {
                implicitHeight: 30
                icon: ShellState.doNotDisturb ? "notifications-disabled" : "notifications"
                iconSize: 16
                text: "Do Not Disturb"
                active: ShellState.doNotDisturb
                onClicked: ShellState.doNotDisturb = !ShellState.doNotDisturb
            }
            BarButton {
                implicitHeight: 30
                icon: "edit-clear-all"
                iconSize: 16
                text: "Clear all"
                enabled: Notifs.history.length > 0
                opacity: enabled ? 1 : 0.5
                onClicked: Notifs.clearAll()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 24
            Layout.bottomMargin: 24
            visible: Notifs.history.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: "No notifications"
            color: Theme.fgDim
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(groupsCol.implicitHeight, 640)
            visible: Notifs.history.length > 0
            contentHeight: groupsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: groupsCol
                width: parent.width
                spacing: 10
                Repeater {
                    model: Notifs.groups()
                    delegate: Column {
                        id: group
                        required property var modelData
                        width: groupsCol.width
                        spacing: 4
                        RowLayout {
                            width: parent.width
                            spacing: 6
                            Icon {
                                implicitSize: 16
                                name: group.modelData.icon
                                fallback: "preferences-desktop-notification"
                            }
                            Label {
                                Layout.fillWidth: true
                                text: group.modelData.app
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                                font.weight: Font.DemiBold
                            }
                            Label {
                                visible: group.modelData.items.length > 1
                                text: group.modelData.items.length
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                            }
                        }
                        Repeater {
                            model: group.modelData.items
                            delegate: Entry { now: pane.now }
                        }
                    }
                }
            }
        }
    }

    component Entry: MouseArea {
        id: entry
        required property var modelData
        property double now: 0
        readonly property var n: modelData
        width: parent ? parent.width : 0
        implicitHeight: row.implicitHeight + 16
        hoverEnabled: true
        onClicked: Notifs.activate(entry.n)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: entry.containsMouse ? Theme.bgRaised : Qt.rgba(1, 1, 1, 0.03)
            border.color: entry.n.urgency === NotificationUrgency.Critical ? Theme.bad : "transparent"
        }
        RowLayout {
            id: row
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 8
            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                visible: entry.n.image !== "" && status === Image.Ready
                source: entry.n.image
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 80
                sourceSize.height: 80
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: entry.n.summary
                        textFormat: Text.PlainText
                        font.weight: Font.DemiBold
                    }
                    Label {
                        text: Notifs.age(entry.n, entry.now)
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: entry.n.body
                    textFormat: Text.StyledText
                    color: Theme.fgDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    linkColor: Theme.accent
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
            BarButton {
                Layout.alignment: Qt.AlignTop
                implicitHeight: 24
                implicitWidth: 24
                iconSize: 14
                icon: "window-close"
                tooltip: "Dismiss"
                onClicked: Notifs.dismiss(entry.n)
            }
        }
    }
}
