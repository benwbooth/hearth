import QtQuick
import Quickshell
import "../widgets"
import ".."

// App launcher button: opens Vicinae (Raycast-style launcher: apps, files,
// calculator and unit conversion, clipboard history, emoji, extensions).
// Tapping Super opens it too (bound in hyprland.lua).
BarButton {
    id: root
    icon: "start-here-kde-symbolic"
    iconFallback: "start-here"
    iconSize: 26
    tooltip: "Search apps, files and more"
    onClicked: Quickshell.execDetached(["vicinae", "toggle"])
}
