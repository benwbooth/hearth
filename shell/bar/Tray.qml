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

    Clipboard {}
    Media {}
    Zones {}
    Network {}
    Rdp {}
    Camera {}
    Drives {}
    Weather {}
    Keyboard {}
    Battery {}
    Bluetooth {}
    Brightness {}
    Volume {}
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
        implicitWidth: 30
        icon: modelData.icon
        tooltip: modelData.tooltipTitle || modelData.title || modelData.id
        tooltipSub: modelData.tooltipDescription

        function showMenu() {
            const win = item.QsWindow.window;
            const p = item.mapToItem(win.contentItem, 0, 0);
            modelData.display(win, p.x, p.y);
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
