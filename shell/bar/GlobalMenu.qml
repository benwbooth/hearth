import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// macOS-style menus for the focused app: its name in bold (a small menu of
// window actions every app gets), then its own menu bar when the
// compositor gives one (AppMenu: arbor's app_menu + dbusmenu). With a menu
// open, hovering another title switches to it, like a real menu bar.
Row {
    id: root
    spacing: 0

    readonly property var win: Compositor.focusedWindow
    readonly property var activeTop: ToplevelManager.activeToplevel
    readonly property string appId: win ? win.appId : activeTop ? activeTop.appId : ""
    readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string appName: entry ? entry.name : appId ? appId.split(".").pop() : "Desktop"
    // Every open window of the focused app.
    readonly property var appWindows: {
        if (!appId) return [];
        return ToplevelManager.toplevels.values.filter(t => t.appId === appId);
    }
    property bool anyOpen: false


    MenuTitle {
        id: appTitle
        text: root.appName
        bold: true
        tip: "Window commands for " + root.appName + ": new window, minimize, close, quit"
        visible: Settings.menubar.showAppName
        popup: appMenu
    }
    BarPopup {
        id: appMenu
        menuBarMenu: true
        align: "start"
        anchorItem: appTitle
        padding: Theme.menuPadding
        Column {
            width: Math.round(220 * Theme.pt)
            MenuItem {
                text: "New Window"
                visible: !!root.entry
                onTriggered: { appMenu.close(); root.entry.execute(); }
            }
            MenuItem {
                text: "Minimize"
                visible: root.activeTop !== null
                onTriggered: { appMenu.close(); if (root.activeTop) Compositor.minimizeToplevel(root.activeTop); }
            }
            MenuItem {
                text: "Close Window"
                visible: root.win !== null || root.activeTop !== null
                onTriggered: {
                    appMenu.close();
                    if (root.win) Compositor.closeWindow(root.win.id);
                    else if (root.activeTop) root.activeTop.close();
                }
            }
            MenuSeparator {}
            MenuItem {
                text: "Quit " + root.appName
                enabled: root.appWindows.length > 0
                onTriggered: { appMenu.close(); for (const t of root.appWindows) t.close(); }
            }
        }
    }

    Repeater {
        // Keyed by item id: a layout refresh (every time a menu opens) must
        // not recreate the titles, or the open dropdown would go with them.
        model: ScriptModel {
            values: AppMenu.topLevel
            objectProp: "id"
        }
        delegate: Item {
            id: topItem
            required property var modelData
            implicitWidth: title.implicitWidth
            implicitHeight: title.implicitHeight
            MenuTitle {
                id: title
                text: topItem.modelData.label
                tip: "The " + topItem.modelData.label + " menu of " + root.appName
                enabled: topItem.modelData.enabled
                popup: pop
            }
            BarPopup {
                id: pop
                menuBarMenu: true
                align: "start"
                anchorItem: title
                padding: 0
                bare: true
                Loader {
                    active: pop.open
                    sourceComponent: DBusMenuList {
                        itemId: topItem.modelData.id
                        hostPopup: pop
                        onDone: pop.close()
                    }
                }
            }
        }
    }

    // A menu title: macOS 26 metrics (13 pt, ~10 pt padding each side), the
    // translucent capsule while its menu is open; opens on press like
    // macOS (MenuBar.qml pressTitle/dragTitle/releaseTitle/hoverTitle).
    component MenuTitle: MouseArea {
        id: t
        property string text
        property bool bold: false
        property var popup
        readonly property var menuPopup: popup
        readonly property bool menuPress: !!bar && bar.pressTitle !== undefined
        readonly property var bar: t.QsWindow.window
        property string tip: ""
        hoverEnabled: true
        implicitHeight: Theme.menuBarHeight
        implicitWidth: label.implicitWidth + 2 * Math.round(9.5 * Theme.pt)
        onPressed: mouse => { ShellState.pressedIn(t); if (menuPress) bar.pressTitle(t, popup, mouse); else popup.toggle(); }
        onPositionChanged: mouse => { if (menuPress && pressed) bar.dragTitle(t, popup, mouse); }
        onReleased: mouse => { if (menuPress) bar.releaseTitle(t, popup, mouse); }
        onContainsMouseChanged: if (containsMouse && enabled && menuPress) bar.hoverTitle(popup)
        Component.onCompleted: if (menuPress) bar.registerTitle(t)
        Component.onDestruction: if (menuPress && bar) bar.unregisterTitle(t)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: height / 2
            color: Theme.menuBarHighlight
            opacity: t.popup && t.popup.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: t.popup && t.popup.open ? 0 : 140; easing.type: Easing.OutCubic } }
        }
        Tooltip {
            anchorItem: t
            text: t.tip
            hovered: t.containsMouse && !(t.popup && t.popup.open) && !ShellState.activePopup
        }
        Label {
            id: label
            anchors.centerIn: parent
            text: t.text
            color: t.enabled ? Theme.barFg : Theme.barFgDim
            font.pointSize: Theme.menuBarFontSize
            font.weight: t.bold ? Font.Bold : Font.Normal
            font.letterSpacing: Theme.menuTracking
        }
    }
}
