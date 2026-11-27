import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../widgets"
import "../services"
import ".."

// App tray icons (StatusNotifierItem) and the ⌃ chevron with its dropdown:
// passive app icons, and in the menu bar whatever doesn't fit or was put
// there (Settings > Menu Bar: "Only in the ⌃ menu"). hearth's own
// indicators are separate items (bar/MenuBar.qml, bar/PanelIndicators.qml).
// The menu bar takes the chevron out (`chevron`) and puts it where the item
// list says; MenuBar.qml decides `sniOverflow` and `menuRows`.
Row {
    id: root
    spacing: 0

    // Set by the menu bar: overflowed items' keys (BarButton.overflowed
    // reads these two).
    property var overflowKeys: []
    readonly property Item overflowAnchor: more
    readonly property Item chevron: more
    // How many app icons, from the left, are in the dropdown.
    property int sniOverflow: 0
    // Rows below the app icons in the dropdown, in bar order: [{ key, item }].
    property var menuRows: []
    // Settings > Menu Bar > App icons: "bar" | "overflow" | "hidden".
    readonly property string iconsShow: BarItems.show("trayicons")

    readonly property var items: SystemTray.items.values
    readonly property var shownItems: iconsShow === "hidden" ? [] : items.filter(i => i.status !== Status.Passive)
    readonly property var hiddenItems: iconsShow === "hidden" ? [] : items.filter(i => i.status === Status.Passive)
    readonly property int sniInMenu: iconsShow === "overflow" ? shownItems.length : Math.min(sniOverflow, shownItems.length)
    readonly property var barItems: shownItems.slice(sniInMenu)
    readonly property var menuItems: shownItems.slice(0, sniInMenu).concat(hiddenItems)
    // Width of the icons left in the bar and of the chevron, for the fit.
    readonly property real chevronWidth: more.implicitWidth

    Repeater {
        id: barRep
        model: root.barItems
        delegate: TrayItem {}
    }

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

    // An app's tray menu, in hearth's own glass menu (the same as the
    // global menu's: widgets/DBusMenuList.qml reading the item's dbusmenu
    // through Quickshell), below its icon, or below the chevron for icons
    // in the dropdown. One for all tray icons.
    BarPopup {
        id: trayMenu
        property var sni: null
        anchorItem: more
        align: "start"
        padding: 0
        bare: true
        function show(sni, anchor) {
            if (open && trayMenu.sni === sni) { close(); return; }
            open = false;
            trayMenu.sni = sni;
            trayMenu.anchorItem = anchor;
            open = true;
        }
        Connections {
            target: TrayWindows
            function onMenuRequested(sni) {
                const i = root.barItems.indexOf(sni);
                const btn = i >= 0 ? barRep.itemAt(i) : null;
                trayMenu.show(sni, btn || more);
            }
        }
        Loader {
            // Kept while the menu fades out.
            active: trayMenu.visible && !!trayMenu.sni
            sourceComponent: DBusMenuList {
                qsMenu: trayMenu.sni ? trayMenu.sni.menu : null
                onDone: trayMenu.close()
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
        readonly property bool isMonitor: key.startsWith("treetop.")
        implicitHeight: isMap ? mapRow.implicitHeight + 8 : 32
        hoverEnabled: true
        acceptedButtons: isMap ? Qt.NoButton : Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (isMonitor) { target.toggleTreetop(); more.popup.close(); return; }
            if (mouse.button === Qt.LeftButton) {
                more.popup.close();
                const t = target;
                if (key === "notifications") Notifications.toggleCenter();
                else if (key === "spotlight") Spotlight.toggle();
                else if (t.overflowActivate) Qt.callLater(() => t.overflowActivate());
            } else if (mouse.button === Qt.RightButton && target.rightClicked) target.rightClicked();
            else if (mouse.button === Qt.MiddleButton && key === "notifications") Notifications.toggleDnd();
            else if (mouse.button === Qt.MiddleButton && target.middleClicked) target.middleClicked();
        }
        WheelNotches { id: rowNotches }
        onWheel: w => {
            if (!target.scrolled) return;
            const n = rowNotches.feed(w);
            for (let i = 0; i < Math.min(Math.abs(n), 5); i++) target.scrolled(n > 0 ? 120 : -120);
        }

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
                text: row.isMonitor ? BarItems.label(row.key) : String(row.target.tooltip || BarItems.label(row.key))
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
        exactMono: true
        tooltip: modelData.tooltipTitle || modelData.title || modelData.id
        tooltipSub: modelData.tooltipDescription

        // Below the icon, like macOS, so the menu never covers the tray
        // (from the dropdown: below the chevron, as the dropdown closes).
        function showMenu() { trayMenu.show(modelData, inMenu ? more : item); }

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
