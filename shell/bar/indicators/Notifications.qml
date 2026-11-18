import QtQuick
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../.."

// Notification bell for SwayNotificationCenter (swaync), which shows the
// popups and the history panel. Click opens the panel, middle-click toggles
// Do Not Disturb; the badge is swaync's notification count.
BarButton {
    id: root
    property int count: 0
    property bool dnd: false
    property bool inhibited: false

    implicitWidth: 30
    icon: root.dnd ? "notifications-disabled" : "notifications"
    tooltip: root.dnd ? "Notifications (Do Not Disturb)" : "Notifications"
    tooltipSub: root.count > 0 ? (root.count === 1 ? "1 notification" : root.count + " notifications")
                               : "No notifications"

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) Quickshell.execDetached(["swaync-client", "-d", "-sw"]);
        else Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
    }

    // `-swb` prints a JSON line on every change:
    // {"text": "<count>", "alt": "notification|none|dnd-notification|dnd-none|inhibited-...", ...}
    Process {
        id: sub
        command: ["swaync-client", "-swb"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const s = JSON.parse(line);
                    root.count = parseInt(s.text) || 0;
                    root.dnd = (s.alt || "").indexOf("dnd") >= 0;
                    root.inhibited = (s.alt || "").indexOf("inhibited") >= 0;
                } catch (e) {}
            }
        }
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 3000
        onTriggered: sub.running = true
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
