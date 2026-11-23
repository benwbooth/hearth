import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../widgets"
import "../services"
import "indicators"
import ".."

// System tray: app icons (StatusNotifierItem) followed by hearth's own
// indicators. Passive app icons go in the dropdown behind the chevron, and
// so does whatever doesn't fit the menu bar on a narrow screen (MenuBar.qml
// decides: `overflowKeys`, `sniOverflow`, `outsideItems`).
Row {
    id: root
    spacing: 0

    // Set by the menu bar. Indicators listed here (by ipcName) leave the
    // bar for the dropdown (BarButton.overflowed reads these two).
    property var overflowKeys: []
    readonly property Item overflowAnchor: more
    // How many app icons, from the left, are in the dropdown.
    property int sniOverflow: 0
    // The menu bar's own items now in the dropdown: [{ key, item }].
    property var outsideItems: []

    readonly property var items: SystemTray.items.values
    readonly property var shownItems: items.filter(i => i.status !== Status.Passive)
    readonly property var hiddenItems: items.filter(i => i.status === Status.Passive)
    readonly property var barItems: shownItems.slice(Math.min(sniOverflow, shownItems.length))
    readonly property var menuItems: shownItems.slice(0, Math.min(sniOverflow, shownItems.length)).concat(hiddenItems)

    // hearth's indicators in bar order, plus the bell, for the menu bar's
    // fit: { key, w, on }.
    readonly property var indicators: [recording, media, clipboard, zones, network, rdp, camera, printers, drives, weather, keyboard, battery, bluetooth, brightness, volume]
    readonly property var entries: indicators.map(i => ({ key: i.overflowKey, w: i.implicitWidth, on: i.present }))
        .concat([{ key: "notifications", w: bell.implicitWidth, on: true }])
    readonly property real chevronWidth: more.implicitWidth
    // Rows in the dropdown below the app icons, in bar order.
    readonly property var menuRows: outsideItems.concat(
        indicators.filter(i => i.present && i.overflowed).map(i => ({ key: i.overflowKey, item: i })))

    Repeater {
        model: root.barItems
        delegate: TrayItem {}
    }

    Recording { id: recording; ipcName: "recording" }
    Media { id: media; ipcName: "media" }
    Clipboard { id: clipboard; ipcName: "clipboard" }
    Zones { id: zones; ipcName: "zones" }
    Network { id: network; ipcName: "network" }
    Rdp { id: rdp; ipcName: "rdp" }
    Camera { id: camera; ipcName: "camera" }
    Printers { id: printers; ipcName: "printers" }
    Drives { id: drives; ipcName: "drives" }
    Weather { id: weather; ipcName: "weather" }
    Keyboard { id: keyboard; ipcName: "keyboard" }
    Battery { id: battery; ipcName: "battery" }
    Bluetooth { id: bluetooth; ipcName: "bluetooth" }
    Brightness { id: brightness; ipcName: "brightness" }
    Volume { id: volume; ipcName: "volume" }
    NotificationBell { id: bell }

    Indicator {
        id: more
        implicitWidth: 26
        icon: "arrow-up"
        ipcName: "more"
        tooltip: root.menuRows.length > 0 ? "More menu bar items" : "Show hidden icons"
        tooltipSub: root.menuRows.length > 0 ? "App icons and items that don't fit the menu bar" : ""
        shown: root.menuItems.length > 0 || root.menuRows.length > 0
        popupContent: Column {
            id: list
            spacing: 6
            width: Math.max(grid.implicitWidth, root.menuRows.length > 0 ? 400 : 0)
            Grid {
                id: grid
                visible: root.menuItems.length > 0
                columns: 6
                spacing: 2
                Repeater {
                    model: root.menuItems
                    delegate: TrayItem { inMenu: true }
                }
            }
            Rectangle {
                visible: grid.visible && root.menuRows.length > 0
                width: parent.width
                height: 1
                color: Theme.border
            }
            Repeater {
                model: root.menuRows
                delegate: OverflowRow { width: list.width }
            }
        }
    }

    // A menu bar item in the dropdown: the workspace map itself, the system
    // monitor's numbers (click: treetop), or an indicator's icon, name and
    // value (click: its popup, under the chevron; right/middle click and
    // the wheel work like on the bar).
    component OverflowRow: MouseArea {
        id: row
        required property var modelData
        readonly property var target: modelData.item
        readonly property string key: modelData.key
        readonly property bool isMap: key === "workspaces"
        readonly property bool isMonitor: key === "sysmonitor"
        implicitHeight: isMap ? mapRow.implicitHeight + 8 : 32
        hoverEnabled: true
        acceptedButtons: isMap ? Qt.NoButton : Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (isMonitor) { target.toggleTreetop(); more.popup.close(); return; }
            if (mouse.button === Qt.LeftButton) {
                more.popup.close();
                const t = target;
                if (t.overflowActivate) Qt.callLater(() => t.overflowActivate());
            } else if (mouse.button === Qt.RightButton && target.rightClicked) target.rightClicked();
            else if (mouse.button === Qt.MiddleButton && target.middleClicked) target.middleClicked();
        }
        onWheel: w => { if (target.scrolled) target.scrolled(w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x); }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: row.containsMouse && !row.isMap ? Theme.hover : "transparent"
        }
        Row {
            id: mapRow
            visible: row.isMap
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Label { text: "Workspaces"; color: Theme.fgDim; anchors.verticalCenter: parent.verticalCenter }
            Workspaces {
                screen: root.QsWindow.window ? root.QsWindow.window.screen : null
                fg: Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            visible: !row.isMap
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 18
                name: row.isMonitor ? "utilities-system-monitor" : (row.target.icon || "")
                fallback: row.isMonitor ? "application-x-executable" : (row.target.iconFallback || "application-x-executable")
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: row.isMonitor ? "System monitor" : String(row.target.tooltip || row.key)
                elide: Text.ElideRight
                width: Math.max(40, Math.min(implicitWidth, row.width - 8 - 28 - value.implicitWidth - 24))
            }
        }
        Label {
            id: value
            visible: !row.isMap
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fgDim
            text: row.isMonitor ? row.target.compactText : String(row.target.text || "")
        }
        Tooltip {
            anchorItem: row
            hovered: row.containsMouse && !row.isMap
            text: row.isMonitor ? "Open treetop" : String(row.target.tooltip || "")
            subtext: row.isMonitor ? "" : String(row.target.tooltipSub || "")
        }
    }

    component TrayItem: BarButton {
        id: item
        required property var modelData
        // In the chevron's dropdown: a left click there also closes it.
        property bool inMenu: false
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
                // Like a dock icon: to the front, or minimized when it
                // already is (services/TrayWindows.qml).
                else {
                    TrayWindows.toggle(modelData);
                    if (inMenu) more.popup.close();
                }
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
