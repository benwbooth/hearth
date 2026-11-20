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

    function hoverOpen(popup) {
        // Another title's menu is open: move to this one.
        if (ShellState.activePopup && ShellState.activePopup !== popup && ShellState.activePopup.menuBarMenu)
            popup.open = true;
    }

    MenuTitle {
        id: appTitle
        text: root.appName
        bold: true
        visible: Settings.menubar.showAppName
        popup: appMenu
    }
    BarPopup {
        id: appMenu
        readonly property bool menuBarMenu: true
        anchorItem: appTitle
        padding: 5
        Column {
            width: 240
            MenuItem {
                text: "New Window"
                visible: !!root.entry
                onTriggered: { appMenu.close(); root.entry.execute(); }
            }
            MenuItem {
                text: "Minimize"
                visible: root.activeTop !== null
                onTriggered: { appMenu.close(); if (root.activeTop) root.activeTop.minimized = true; }
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
        model: AppMenu.topLevel
        delegate: Item {
            id: topItem
            required property var modelData
            implicitWidth: title.implicitWidth
            implicitHeight: title.implicitHeight
            MenuTitle {
                id: title
                text: topItem.modelData.label
                enabled: topItem.modelData.enabled
                popup: pop
            }
            BarPopup {
                id: pop
                readonly property bool menuBarMenu: true
                anchorItem: title
                padding: 5
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

    component MenuTitle: MouseArea {
        id: t
        property string text
        property bool bold: false
        property var popup
        hoverEnabled: true
        implicitHeight: Theme.menuBarHeight
        implicitWidth: label.implicitWidth + 20
        onClicked: popup.toggle()
        onContainsMouseChanged: if (containsMouse && enabled) root.hoverOpen(popup)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: 3
            radius: Theme.radius
            color: t.popup && t.popup.open ? Theme.selected : t.containsMouse ? Theme.hover : "transparent"
        }
        Label {
            id: label
            anchors.centerIn: parent
            text: t.text
            color: t.enabled ? Theme.fg : Theme.fgDim
            font.weight: t.bold ? Font.Bold : Font.Normal
        }
    }
}
