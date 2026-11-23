import QtQuick
import Quickshell
import "../widgets"
import "../services"
import ".."

// App launcher button (classic panel): opens the Launchpad, every
// installed app in a full-screen grid (popups/LaunchpadWindow.qml).
// Right-click opens Vicinae (Raycast-style search: apps, files,
// calculator, clipboard history, emoji).
BarButton {
    id: root
    icon: "start-here-kde-symbolic"
    iconFallback: "start-here"
    iconSize: 26
    tooltip: "All apps (Launchpad) · right-click: search with Vicinae"
    onClicked: mouse => { if (mouse.button === Qt.RightButton) Quickshell.execDetached(["vicinae", "toggle"]); else Launchpad.toggle(); }
}
