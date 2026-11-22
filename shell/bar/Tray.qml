import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../widgets"
import "../services"
import "indicators"
import ".."

// System tray: app icons (StatusNotifierItem) followed by hearth's own
// indicators. Passive app icons go in the overflow popup behind the arrow.
Row {
    id: root
    spacing: 0

    readonly property var items: SystemTray.items.values
    readonly property var shownItems: items.filter(i => i.status !== Status.Passive)
    readonly property var hiddenItems: items.filter(i => i.status === Status.Passive)

    Repeater {
        model: root.shownItems
        delegate: TrayItem {}
    }

    Recording { ipcName: "recording" }
    Media { ipcName: "media" }
    Clipboard { ipcName: "clipboard" }
    Zones { ipcName: "zones" }
    Network { ipcName: "network" }
    Rdp { ipcName: "rdp" }
    Camera { ipcName: "camera" }
    Printers { ipcName: "printers" }
    Drives { ipcName: "drives" }
    Weather { ipcName: "weather" }
    Keyboard { ipcName: "keyboard" }
    Battery { ipcName: "battery" }
    Bluetooth { ipcName: "bluetooth" }
    Brightness { ipcName: "brightness" }
    Volume { ipcName: "volume" }
    Notifications {}

    Indicator {
        id: more
        implicitWidth: 26
        icon: "arrow-up"
        tooltip: "Show hidden icons"
        shown: root.hiddenItems.length > 0
        popupContent: Grid {
            columns: 6
            spacing: 2
            Repeater {
                model: root.hiddenItems
                delegate: TrayItem {}
            }
        }
    }

    component TrayItem: BarButton {
        id: item
        required property var modelData
        implicitWidth: Theme.menuBarItemWidth
        icon: modelData.icon
        // Apps' own tray icons are usually full-colour pictures that turn
        // into blobs as silhouettes: only their symbolic/panel icons go
        // monochrome.
        monochrome: Settings.menubar.monochromeIcons !== false && /symbolic|panel|tray|indicator|-mono/i.test(String(modelData.icon))
        // Everything else: white or grey pictures (an update checker, Claude)
        // still follow the bar's text colour; colourful icons keep theirs.
        adaptive: Settings.menubar.monochromeIcons !== false && !monochrome
        tooltip: modelData.tooltipTitle || modelData.title || modelData.id
        tooltipSub: modelData.tooltipDescription

        function showMenu() {
            const win = item.QsWindow.window;
            const p = item.mapToItem(win.contentItem, 0, 0);
            // Below the icon, like macOS, so the menu never covers the tray.
            modelData.display(win, p.x, p.y + item.height);
        }

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (modelData.onlyMenu && modelData.hasMenu) showMenu();
                else modelData.activate();
            } else if (mouse.button === Qt.MiddleButton) {
                modelData.secondaryActivate();
            } else if (modelData.hasMenu) {
                showMenu();
            }
        }
        onWheel: w => modelData.scroll(w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x,
                                       w.angleDelta.y === 0)
    }
}
