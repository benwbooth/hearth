import QtQuick
import "../widgets"
import "../services"
import ".."

// The magnifier in the menu bar: opens Spotlight (popups/Spotlight.qml).
BarButton {
    icon: "search"
    iconFallback: "edit-find"
    tooltip: "Search apps, files and settings; calculate"
    tooltipSub: Spotlight.shortcutText
    active: Spotlight.open
    onClicked: mouse => { if (mouse.button === Qt.LeftButton) Spotlight.toggle(); }
}
