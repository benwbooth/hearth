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

    // AppMenu.win: the focused window, kept while a hearth menu has focus.
    readonly property var win: AppMenu.win
    readonly property var activeTop: win && win.toplevel ? win.toplevel
        : Compositor.isArbor ? null : ToplevelManager.activeToplevel
    readonly property string appId: win ? win.appId : activeTop ? activeTop.appId : ""
    readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : null
    // Without a desktop entry: the last part of a reverse-DNS id
    // (org.example.Foo -> Foo), else the id as is (foo.py stays foo.py).
    readonly property string appName: entry ? entry.name
        : appId ? (appId.split(".").length >= 3 ? appId.split(".").pop() : appId) : "Desktop"
    // Every open window of the focused app.
    readonly property var appWindows: {
        if (!appId) return [];
        return ToplevelManager.toplevels.values.filter(t => t.appId === appId);
    }
    property bool anyOpen: false
    // Room for the titles (MenuBar): titles past it are hidden.
    property real maxWidth: Infinity
    // Whether the first n titles after the app name (the app's menus, then
    // Window) fit in maxWidth. Widths from the delegates / the Window title.
    function fits(n) {
        void AppMenu.topLevel;
        let w = appTitle.visible ? appTitle.implicitWidth : 0;
        for (let i = 0; i < n; i++) {
            const it = i < topRep.count ? topRep.itemAt(i) : winTitle;
            w += it ? it.implicitWidth : 0;
        }
        return w <= root.maxWidth;
    }


    // Windows of the focused app, as Compositor windows (arbor ids).
    readonly property var appCompWindows: root.appId ? Compositor.windows.filter(w => w.appId === root.appId) : []
    // The app's own menus already have a Window menu (macOS apps do).
    readonly property bool appHasWindowMenu: AppMenu.topLevel.some(i => i.label === "Window")
    readonly property bool hasWindow: root.win !== null || root.activeTop !== null

    MenuTitle {
        id: appTitle
        text: root.appName
        bold: true
        tip: "Commands for " + root.appName + ": about, hide, quit"
        visible: Settings.menubar.showAppName
        popup: appMenu
    }
    // The app-name menu, like macOS's: About, the app's own GNOME-style
    // app menu if it has one (GTK), new window, hide, quit.
    BarPopup {
        id: appMenu
        menuBarMenu: true
        align: "start"
        anchorItem: appTitle
        padding: Theme.menuPadding
        Column {
            width: Math.round(240 * Theme.pt)
            MenuItem {
                text: "About " + root.appName
                visible: root.appId !== ""
                onTriggered: { appMenu.close(); aboutPop.open = true; }
            }
            MenuSeparator { visible: root.appId !== "" }
            Repeater {
                // GTK app menu (GNOME 3 style), flat with its sections.
                model: AppMenu.gtkAppMenu ? AppMenu.gtkAppMenu.children.filter(i => i.visible) : []
                delegate: Loader {
                    required property var modelData
                    width: parent.width
                    sourceComponent: modelData.type === "separator" ? sepC : itemC
                    Component { id: sepC; MenuSeparator {} }
                    Component {
                        id: itemC
                        MenuItem {
                            text: modelData.label
                            enabled: modelData.enabled
                            shortcut: modelData.shortcut
                            checkable: modelData.toggleType !== ""
                            radio: modelData.toggleType === "radio"
                            checked: modelData.toggleState === 1
                            onTriggered: { appMenu.close(); AppMenu.click(modelData.id); }
                        }
                    }
                }
            }
            MenuSeparator { visible: !!AppMenu.gtkAppMenu }
            MenuItem {
                text: "New Window"
                visible: !!root.entry
                onTriggered: { appMenu.close(); root.entry.execute(); }
            }
            MenuItem {
                text: "Close Window"
                visible: root.hasWindow
                onTriggered: {
                    appMenu.close();
                    if (root.win) Compositor.closeWindow(root.win.id);
                    else if (root.activeTop) root.activeTop.close();
                }
            }
            MenuSeparator { visible: root.hasWindow }
            MenuItem {
                text: "Hide " + root.appName
                visible: root.appWindows.length > 0
                onTriggered: { appMenu.close(); for (const t of root.appWindows) Compositor.minimizeToplevel(t); }
            }
            MenuItem {
                text: "Hide Others"
                visible: Compositor.isArbor
                enabled: Compositor.windows.some(w => w.appId !== root.appId && !w.minimized)
                onTriggered: {
                    appMenu.close();
                    for (const w of Compositor.windows)
                        if (w.appId !== root.appId && !w.minimized) Compositor.minimize(w.id);
                }
            }
            MenuItem {
                text: "Show All"
                visible: Compositor.isArbor
                enabled: Compositor.windows.some(w => w.minimized)
                onTriggered: {
                    appMenu.close();
                    const keep = root.win;
                    for (const w of Compositor.windows) if (w.minimized) Compositor.focusWindow(w.id);
                    if (keep) Compositor.focusWindow(keep.id);
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
    // About <App>: what hearth knows from the app's desktop entry.
    BarPopup {
        id: aboutPop
        align: "start"
        anchorItem: appTitle
        padding: Math.round(16 * Theme.pt)
        Column {
            width: Math.round(260 * Theme.pt)
            spacing: Math.round(6 * Theme.pt)
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.entry && root.entry.icon ? root.entry.icon : "application-x-executable"
                implicitSize: Math.round(64 * Theme.pt)
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.appName
                font.weight: Font.Bold
                font.pointSize: Theme.fontSize * 1.2
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.fgSecondary
                visible: text !== ""
                text: root.entry ? [root.entry.genericName, root.entry.comment].filter(x => x).join("\n") : ""
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
                color: Theme.fgSecondary
                font.pointSize: Theme.menuSmallFontSize
                text: "App ID: " + root.appId
            }
        }
    }
    Repeater {
        id: topRep
        // Keyed by item id: a layout refresh (every time a menu opens) must
        // not recreate the titles, or the open dropdown would go with them.
        model: ScriptModel {
            values: AppMenu.topLevel
            objectProp: "id"
        }
        delegate: Item {
            id: topItem
            required property var modelData
            required property int index
            visible: root.fits(index + 1)
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

    // macOS's Window menu, for apps whose own menus have none (and every
    // app without exported menus): window commands from the compositor.
    MenuTitle {
        id: winTitle
        text: "Window"
        tip: "Minimize, zoom, full screen or move " + root.appName + "'s window"
        visible: root.hasWindow && !root.appHasWindowMenu && root.fits(topRep.count + 1)
        popup: winMenu
    }
    BarPopup {
        id: winMenu
        menuBarMenu: true
        align: "start"
        anchorItem: winTitle
        padding: Theme.menuPadding
        Column {
            width: Math.round(240 * Theme.pt)
            MenuItem {
                text: "Minimize"
                onTriggered: {
                    winMenu.close();
                    if (root.win) Compositor.minimize(root.win.id);
                    else if (root.activeTop) Compositor.minimizeToplevel(root.activeTop);
                }
            }
            MenuItem {
                text: "Zoom"
                visible: Compositor.isArbor && root.win !== null
                onTriggered: { winMenu.close(); Compositor.arborAction("MaximizeWindowToEdges", { id: Number(root.win.id) }); }
            }
            MenuItem {
                text: "Enter Full Screen"
                visible: Compositor.isArbor && root.win !== null
                onTriggered: { winMenu.close(); Compositor.arborAction("FullscreenWindow", { id: Number(root.win.id) }); }
            }
            MenuItem {
                text: root.win && root.win.floating ? "Move Window to Layout" : "Float Window"
                visible: Compositor.isArbor && root.win !== null
                onTriggered: { winMenu.close(); Compositor.arborAction("ToggleWindowFloating", { id: Number(root.win.id) }); }
            }
            MenuSeparator { visible: root.win !== null && moveRep.count > 0 }
            MenuHeader { text: "Move to Workspace"; visible: root.win !== null && moveRep.count > 0 }
            Repeater {
                id: moveRep
                model: root.win ? Compositor.workspaces.filter(w => w.id !== root.win.workspaceId && w.output === root.win.output) : []
                delegate: MenuItem {
                    required property var modelData
                    width: parent.width
                    text: modelData.name
                    onTriggered: { winMenu.close(); Compositor.moveWindowToWorkspace(root.win.id, modelData.id); }
                }
            }
            MenuSeparator {}
            MenuItem {
                text: "Bring All to Front"
                enabled: root.appCompWindows.length > 1
                onTriggered: {
                    winMenu.close();
                    const keep = root.win;
                    for (const w of root.appCompWindows) Compositor.focusWindow(w.id);
                    if (keep) Compositor.focusWindow(keep.id);
                }
            }
            MenuSeparator { visible: root.appCompWindows.length > 0 }
            Repeater {
                model: root.appCompWindows
                delegate: MenuItem {
                    required property var modelData
                    width: parent.width
                    text: modelData.title || root.appName
                    checkable: true
                    checked: modelData.focused
                    onTriggered: { winMenu.close(); Compositor.focusWindow(modelData.id); }
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
