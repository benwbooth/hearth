import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// One app in the task manager (classic panel) or the dock: pinned launcher
// and/or running windows. Left click launches / focuses / minimizes /
// cycles, middle click opens a new window, right click the app menu, hover
// shows live window previews. `dock` switches to the macOS look: no
// background, a dot under running apps, magnification via `zoom`.
MouseArea {
    id: task
    required property var modelData
    property bool dock: false
    property bool vertical: false
    property int iconSize: Theme.taskIconSize
    property real cellLength: Theme.barHeight + 4   // along the bar/dock
    property real thickness: Theme.barHeight
    property real zoom: 1                            // dock magnification
    property real maxZoom: 1                         // largest zoom (icon load size)
    property bool showIndicator: true
    // Dock drag-to-reorder/remove: an object with begin(task, p),
    // move(task, p), end(task, p); p in the task's window coordinates.
    property var dragHost: null
    // False once the pointer has left the dock: previews must close even if
    // the MouseArea missed the leave (input region changed under it).
    property bool hostHovered: true
    // The dock says which icon is under the pointer from its own layout:
    // when magnification moves icons under a resting pointer, Qt doesn't
    // re-enter the new one until the pointer moves.
    property bool hot: false
    readonly property bool pointed: containsMouse || hot
    onHostHoveredChanged: if (!hostHovered) previewHide.restart()
    readonly property bool menuOpen: menu.open
    readonly property bool previewOpen: preview.visible

    readonly property var entry: modelData.entry
    readonly property var windows: modelData.windows
    readonly property bool running: windows.length > 0
    readonly property bool focused: windows.some(w => w.activated)
    readonly property bool urgent: windows.some(w => { const c = Compositor.windowForToplevel(w); return c && c.urgent; })
    readonly property var badge: Badges.forApp(modelData.key)
    readonly property string edge: { const w = task.QsWindow.window; return w && w.edge ? w.edge : "bottom"; }
    property int cycle: 0
    // Right-click menu: the workspace list under "Move to Workspace" is open.
    property bool wsOpen: false
    Connections { target: menu; function onOpenChanged() { if (!menu.open) task.wsOpen = false; } }
    property bool dragging: false
    property point pressPos

    implicitWidth: vertical ? thickness : cellLength * zoom
    implicitHeight: vertical ? cellLength * zoom : thickness
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

    function launch() {
        if (entry) Launch.app(entry);
        if (dock) { launching = true; bounces = 0; launchTimeout.restart(); if (!bounce.running) bounce.start(); }
    }
    // Launch bounce, macOS style: hops of half an icon, ~0.6 s each, until
    // the app's first window shows (at most ~6 s); an app asking for
    // attention (urgent) bounces three times.
    property bool launching: false
    property int bounces: 0
    property int bounceLimit: 10
    onRunningChanged: if (running) launching = false
    onUrgentChanged: if (urgent && dock && !bounce.running) { bounces = 0; bounceLimit = 3; bounce.start(); }
    Timer { id: launchTimeout; interval: 6000; onTriggered: task.launching = false }

    // Left click: launch, focus, minimize, or cycle through windows.
    function trigger() {
        if (!running) { launch(); return; }
        if (windows.length === 1) {
            const w = windows[0];
            if (w.activated) Compositor.minimizeToplevel(w);
            else w.activate();
            return;
        }
        // Several windows: each click focuses the next one.
        cycle = (cycle + 1) % windows.length;
        windows[cycle].activate();
    }

    onPressed: mouse => { ShellState.pressedIn(task); pressPos = Qt.point(mouse.x, mouse.y); dragging = false; previewShow.stop(); }
    onPositionChanged: mouse => {
        // Moving over the icon restarts the rest timer (dock thumbnails).
        if (task.dock && task.pointed && !preview.visible && !task.pressed) previewShow.restart();
        if (!task.dragHost || !task.pressed || !(task.pressedButtons & Qt.LeftButton)) return;
        const p = task.mapToItem(null, mouse.x, mouse.y);
        if (!task.dragging) {
            if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 10) return;
            task.dragging = true;
            preview.visible = false;
            task.dragHost.begin(task, p);
        }
        task.dragHost.move(task, p);
    }
    onReleased: mouse => {
        if (task.dragging) {
            task.dragHost.end(task, task.mapToItem(null, mouse.x, mouse.y));
            Qt.callLater(() => task.dragging = false);
        }
    }
    // The grab was taken away mid-drag: drop the drag, don't leave it hanging.
    onCanceled: if (task.dragging) { task.dragHost.cancel(task); task.dragging = false; }
    Component.onDestruction: if (task.dragging && task.dragHost) task.dragHost.cancel(task)
    onClicked: mouse => {
        if (task.dragging) return;
        if (mouse.button === Qt.MiddleButton) launch();
        else if (mouse.button === Qt.RightButton) { preview.visible = false; menu.toggle(); }
        else trigger();
    }
    onWheel: w => {
        if (windows.length < 2) return;
        cycle = (cycle + (w.angleDelta.y < 0 ? 1 : windows.length - 1)) % windows.length;
        windows[cycle].activate();
    }

    Rectangle {
        visible: !task.dock
        anchors.fill: parent
        anchors.margins: 3
        radius: Theme.radius
        color: task.urgent ? Qt.rgba(0.96, 0.45, 0, 0.35)
             : task.focused ? Theme.selected
             : task.containsMouse ? Theme.hover
             : task.running ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
             : "transparent"
    }

    // The dock's icons sit on its inner edge and grow away from it.
    // The icon box grows with magnification; the image inside is loaded
    // once at the largest size and only scaled. (Sizing the image itself by
    // zoom made it reload, asynchronously, on every frame of the magnify
    // animation, so icons blanked out while hovering.)
    // The drawn icon (tests: Dock's HEARTH_DOCK_TRACE logs where it lands).
    readonly property Item iconItem: iconImage
    Item {
        id: icon
        readonly property real size: task.iconSize * task.zoom
        width: size
        height: size
        opacity: task.dragging ? 0.25 : task.pressed ? 0.7 : 1
        Icon {
            id: iconImage
            readonly property real full: Math.ceil(task.iconSize * Math.max(1, task.maxZoom))
            implicitSize: full
            // Centred exactly, not with anchors.centerIn: that puts the
            // image on a whole logical pixel (even with alignWhenCentered
            // off), so during the zoom each icon jumped up to half a pixel
            // (2/3 of a device pixel at 4/3) back and forth against its box.
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            scale: icon.size / full
            smooth: true
            mipmap: true
            name: task.entry ? task.entry.icon : (task.windows.length ? task.windows[0].appId : "")
        }
        x: !task.dock || !task.vertical ? (parent.width - width) / 2
         : task.edge === "left" ? (task.thickness - task.iconSize) / 2 + bounceOffset.value
         : (task.thickness + task.iconSize) / 2 - width - bounceOffset.value
        y: !task.dock ? (parent.height - height) / 2
         : task.vertical ? (parent.height - height) / 2
         : (task.thickness + task.iconSize) / 2 - height - bounceOffset.value

        // Unity LauncherEntry badge: count and/or progress.
        Rectangle {
            visible: task.badge.countVisible && task.badge.count > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -6
            anchors.topMargin: -4
            height: 16 * Math.max(1, task.zoom * 0.8)
            width: Math.max(height, countLabel.implicitWidth + 8)
            radius: height / 2
            color: Theme.bad
            Label {
                id: countLabel
                anchors.centerIn: parent
                text: task.badge.count > 99 ? "99+" : String(task.badge.count)
                color: "#ffffff"
                font.pointSize: Theme.smallFontSize
                font.weight: Font.Bold
            }
        }
        Rectangle {
            visible: task.badge.progressVisible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -3
            height: 4
            radius: 2
            color: Qt.rgba(0, 0, 0, 0.6)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, task.badge.progress))
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }
    }
    // Launch bounce (dock).
    QtObject { id: bounceOffset; property real value: 0 }
    SequentialAnimation {
        id: bounce
        loops: Animation.Infinite
        // Up decelerating, down accelerating: a ball under gravity.
        NumberAnimation { target: bounceOffset; property: "value"; to: task.iconSize * 0.5; duration: 300; easing.type: Easing.OutQuad }
        NumberAnimation { target: bounceOffset; property: "value"; to: 0; duration: 300; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                task.bounces++;
                const more = task.launching ? task.bounces < task.bounceLimit : (task.urgent && task.bounces < task.bounceLimit);
                if (!more) { bounce.stop(); bounceOffset.value = 0; task.bounceLimit = 10; }
            }
        }
    }

    // Running indicator. Panel: one dash per window along the bottom.
    // Dock: a dot between the icon and the screen edge.
    Row {
        visible: !task.dock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        spacing: 3
        Repeater {
            model: task.dock ? 0 : Math.min(task.windows.length, 4)
            Rectangle {
                width: task.windows.length > 1 ? 6 : 14
                height: 2
                radius: 1
                color: task.focused ? Theme.accent : Theme.fgDim
            }
        }
    }
    Rectangle {
        visible: opacity > 0
        // macOS: a 4 pt dot, black in light mode, white in dark.
        opacity: task.dock && task.running && task.showIndicator ? (Theme.dark ? 0.85 : 0.7) : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        width: Math.round(4 * Theme.pt)
        height: width
        radius: width / 2
        color: task.urgent ? Theme.warn : Theme.dark ? "#ffffff" : "#000000"
        x: !task.vertical ? (parent.width - width) / 2
         : task.edge === "left" ? 2 : parent.width - width - 2
        y: task.vertical ? (parent.height - height) / 2 : parent.height - height - 2
    }

    // Hover preview: live thumbnails of each window, click to focus.
    PopupWindow {
        id: preview
        property bool hovered: false
        anchor.item: task
        anchor.edges: task.edge === "top" ? Edges.Bottom : task.edge === "left" ? Edges.Right
                    : task.edge === "right" ? Edges.Left : Edges.Top
        anchor.gravity: anchor.edges
        anchor.adjustment: PopupAdjustment.Slide
        // Clear the (magnified) icon, which grows out of the item.
        // The surface has room for the glass's shadow around the pane.
        readonly property real pad: previewFrame.shadowPad
        readonly property real gap: 8 + task.iconSize * (task.zoom - 1) - pad
        anchor.margins.top: task.edge === "bottom" ? -gap : task.edge === "top" ? gap : 0
        anchor.margins.left: task.edge === "left" ? gap : task.edge === "right" ? -gap : 0
        color: "transparent"
        visible: false
        implicitWidth: previewFrame.implicitWidth + 2 * pad
        implicitHeight: previewFrame.implicitHeight + 2 * pad
        mask: Region { item: previewFrame }

        Timer {
            id: previewShow
            // In the dock the name label is drawn by the dock itself; window
            // thumbnails only open after the pointer rests on a running app
            // (restarted on every move), so sweeping across icons never pops
            // windows in and out.
            interval: task.dock ? 900 : 450
            onTriggered: preview.visible = ((task.pointed && task.hostHovered) || previewHover.hovered)
                                           && !(task.dock && !task.running)
                                           && !menu.open && !task.dragging && !task.pressed
        }
        Timer {
            id: previewHide
            interval: 250
            onTriggered: if ((!task.pointed || !task.hostHovered) && !previewHover.hovered) preview.visible = false
        }

        GlassFrame {
            id: previewFrame
            x: preview.pad
            y: preview.pad
            width: implicitWidth
            height: implicitHeight
            implicitWidth: previewCol.implicitWidth + 16
            implicitHeight: previewCol.implicitHeight + 16
            radius: Theme.menuRadius

            HoverHandler { id: previewHover; onHoveredChanged: if (!hovered) previewHide.restart() }

            Column {
                id: previewCol
                x: 8
                y: 8
                spacing: 6
                Label {
                    visible: !task.running
                    text: task.entry ? task.entry.name : task.modelData.key
                    font.weight: Font.DemiBold
                }
                Label {
                    visible: !task.running && !task.dock && task.entry && task.entry.comment !== ""
                    text: task.entry ? task.entry.comment : ""
                    color: Theme.fgDim
                    width: Math.min(implicitWidth, 360)
                }
                Label {
                    visible: task.running && task.dock
                    text: task.entry ? task.entry.name : task.modelData.key
                    font.weight: Font.DemiBold
                }
                // What a click does, for people new to the dock.
                Label {
                    visible: task.dock
                    text: (task.running ? (task.windows.length > 1 ? "Click to switch between its windows" : "Click to switch to it")
                                        : "Click to open") + " · right-click for options"
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
                Row {
                    spacing: 8
                    visible: task.running
                    Repeater {
                        model: preview.visible ? task.windows : []
                        MouseArea {
                            id: thumb
                            required property var modelData
                            width: 240
                            height: 170
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) modelData.close();
                                else { modelData.activate(); preview.visible = false; }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radius
                                color: thumb.containsMouse ? Theme.hover : "transparent"
                                border.color: thumb.modelData.activated ? Theme.accent : "transparent"
                            }
                            Label {
                                x: 6
                                y: 4
                                width: parent.width - 30
                                text: thumb.modelData.title
                                font.pointSize: Theme.smallFontSize
                            }
                            MouseArea {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 2
                                width: 20
                                height: 20
                                visible: thumb.containsMouse
                                onClicked: thumb.modelData.close()
                                Icon { anchors.centerIn: parent; implicitSize: 16; name: "window-close" }
                            }
                            ScreencopyView {
                                anchors.fill: parent
                                anchors.margins: 6
                                anchors.topMargin: 24
                                captureSource: thumb.modelData
                                live: true
                                constraintSize: Qt.size(width, height)
                            }
                        }
                    }
                }
            }
        }
    }

    onPointedChanged: {
        if (pointed) { previewHide.stop(); previewShow.restart(); }
        else { previewShow.stop(); previewHide.restart(); }
    }

    // Right-click menu, grouped like macOS's Dock menu: the app's windows;
    // what it can open (its jump list, New Window); this window's controls;
    // Options (keep / remove, login, Files, workspace); then Quit.
    // Desktop's workspace rule for this app (Options > Assign To).
    readonly property string ruleAppId: windows.length && windows[0].appId ? windows[0].appId
                                        : entry ? (entry.startupClass || entry.id) : modelData.key
    readonly property int ruleIndex: WindowRules.rules.findIndex(r => r.appId === ruleAppId)
    readonly property string assigned: ruleIndex >= 0 ? (WindowRules.rules[ruleIndex].workspace || "") : ""
    property bool assignOpen: false
    Connections { target: menu; function onOpenChanged() { if (!menu.open) task.assignOpen = false; } }
    function assignTo(ws) {
        let i = ruleIndex;
        if (i < 0) {
            if (!ws) return;
            i = WindowRules.add(ruleAppId, entry ? entry.name : ruleAppId, entry ? entry.icon : "");
        }
        WindowRules.update(i, "workspace", ws);
    }
    BarPopup {
        id: menu
        anchorItem: task
        padding: Theme.menuPadding
        Column {
            width: Math.round(230 * Theme.pt)
            spacing: 0
            // Rows line up past the checkmark/icon column.
            readonly property bool menuGutter: true
            MenuHeader {
                text: task.entry ? task.entry.name : task.modelData.key
            }
            // The app's windows (macOS lists them first).
            Repeater {
                model: task.windows.length > 1 ? task.windows : []
                MenuItem {
                    required property var modelData
                    text: modelData.title
                    checkable: true
                    checked: modelData.activated
                    onTriggered: { modelData.activate(); menu.close(); }
                }
            }
            MenuSeparator { visible: task.windows.length > 1 }
            // What the app can open: its jump list (desktop actions), New Window.
            Repeater {
                model: task.entry ? task.entry.actions : []
                MenuItem {
                    required property var modelData
                    text: modelData.name
                    icon: modelData.icon
                    onTriggered: { Launch.app(modelData, task.entry ? task.entry.id : ""); menu.close(); }
                }
            }
            MenuItem {
                visible: !!task.entry
                text: task.running ? "New Window" : "Open"
                icon: task.running ? "window-new" : "system-run"
                onTriggered: { task.launch(); menu.close(); }
            }

            // Its windows.
            MenuSeparator { visible: task.running }
            MenuItem {
                visible: task.running && task.dock
                text: "Show All Windows"
                icon: "view-grid"
                onTriggered: { menu.close(); ShellState.overviewRequested(); }
            }
            MenuItem {
                visible: task.running
                readonly property bool allMin: task.windows.every(w => w.minimized)
                text: allMin ? "Show" : (task.dock ? "Hide" : "Minimize")
                icon: allMin ? "window-restore" : "window-minimize"
                onTriggered: {
                    menu.close();
                    if (allMin) { for (const w of task.windows) w.activate(); }
                    else { for (const w of task.windows) Compositor.minimizeToplevel(w); }
                }
            }
            MenuItem {
                visible: task.windows.length === 1
                text: "Maximize"
                checkable: true
                checked: visible && task.windows[0].maximized
                onTriggered: { menu.close(); const w = task.windows[0]; w.maximized = !w.maximized; }
            }
            MenuItem {
                visible: task.windows.length === 1
                text: "Full Screen"
                checkable: true
                checked: visible && task.windows[0].fullscreen
                onTriggered: { menu.close(); const w = task.windows[0]; w.fullscreen = !w.fullscreen; }
            }
            MenuItem {
                id: wsItem
                readonly property var spaces: Compositor.workspaces.filter(ws => !ws.special
                                               && (!task.QsWindow.window || !task.QsWindow.window.screen
                                                   || ws.output === "" || ws.output === task.QsWindow.window.screen.name))
                visible: task.running && spaces.length > 1
                text: (task.wsOpen ? "▾  " : "▸  ") + (task.windows.length > 1 ? "Move All to Workspace" : "Move to Workspace")
                icon: "virtual-desktops"
                onTriggered: task.wsOpen = !task.wsOpen
            }
            Repeater {
                model: task.wsOpen && wsItem.visible ? wsItem.spaces : []
                MenuItem {
                    required property var modelData
                    readonly property var cws: task.windows.map(w => Compositor.windowForToplevel(w)).filter(c => !!c)
                    text: "      " + (modelData.name && modelData.name !== String(modelData.idx) ? modelData.name : "Workspace " + modelData.idx)
                    checkable: true
                    checked: cws.length > 0 && cws.every(c => c.workspaceId === modelData.id)
                    onTriggered: {
                        menu.close();
                        for (const c of cws) Compositor.moveWindowToWorkspace(c.id, modelData.id);
                    }
                }
            }

            // Options (macOS's Options submenu).
            MenuSeparator {}
            MenuHeader { text: "Options" }
            // A recent app (after the divider, not open): take it off.
            MenuItem {
                visible: task.dock && !!task.modelData.recent && !task.running
                text: "Remove from Dock"
                icon: "list-remove"
                onTriggered: { menu.close(); TaskGroups.forgetRecent(task.modelData.key); }
            }
            MenuItem {
                visible: !!task.entry || Pins.isPinned(task.modelData.key)
                readonly property bool pinned: Pins.isPinned(task.modelData.key)
                text: pinned ? (task.dock ? "Remove from Dock" : "Unpin from Taskbar")
                             : (task.dock ? "Keep in Dock" : "Pin to Taskbar")
                icon: pinned ? "list-remove" : "list-add"
                onTriggered: {
                    menu.close();
                    if (pinned) Pins.unpin(task.modelData.key);
                    else Pins.pin(task.modelData.key);
                }
            }
            MenuItem {
                visible: !!task.entry
                text: "Open at Login"
                checkable: true
                checked: Autostart.isOn(task.modelData.key)
                onTriggered: { Autostart.set(task.modelData.key, !checked); menu.close(); }
            }
            MenuItem {
                visible: !!task.entry
                text: "Show in Files"
                icon: "system-file-manager"
                onTriggered: { menu.close(); Launchpad.showInFiles(task.modelData.key); }
            }
            // Assign To: open this app's windows on a named workspace (a
            // window rule, Settings > Window Rules).
            MenuItem {
                id: assignItem
                readonly property var named: Compositor.workspaces.filter(ws => !ws.special && ws.name && ws.name !== String(ws.idx))
                                                .map(ws => ws.name).filter((n, i, a) => a.indexOf(n) === i)
                visible: Compositor.isArbor && named.length > 0
                text: (task.assignOpen ? "▾  " : "▸  ") + "Assign To" + (task.assigned ? ": " + task.assigned : "")
                icon: "virtual-desktops"
                onTriggered: task.assignOpen = !task.assignOpen
            }
            Repeater {
                model: task.assignOpen && assignItem.visible ? [""].concat(assignItem.named) : []
                MenuItem {
                    required property string modelData
                    text: "      " + (modelData || "None (any workspace)")
                    checkable: true
                    checked: task.assigned === modelData
                    onTriggered: { menu.close(); task.assignTo(modelData); }
                }
            }
            MenuItem {
                visible: !!task.entry
                text: "Edit Application…"
                icon: "document-edit"
                onTriggered: { menu.close(); Quickshell.execDetached(["sh", "-c", 'id="$1"; d="${XDG_DATA_HOME:-$HOME/.local/share}/applications"; mkdir -p "$d"; '
                    + '[ -f "$d/$id.desktop" ] || for p in $(echo "${XDG_DATA_DIRS:-/run/current-system/sw/share}" | tr : " "); do [ -f "$p/applications/$id.desktop" ] && cp "$p/applications/$id.desktop" "$d/" && chmod u+w "$d/$id.desktop" && break; done; '
                    + 'exec tessera --new-window --run "${EDITOR:-nano} \"$d/$id.desktop\""', "sh", task.modelData.key]); }
            }

            // Quit.
            MenuSeparator { visible: task.running }
            MenuItem {
                visible: task.windows.length > 0
                text: task.dock ? "Quit" : task.windows.length > 1 ? `Close all ${task.windows.length} windows` : "Close"
                icon: task.dock ? "application-exit" : "window-close"
                onTriggered: { for (const w of task.windows) w.close(); menu.close(); }
            }
            MenuItem {
                // For an app that stopped responding: ends its processes
                // right away (unsaved work is lost).
                readonly property var pids: [...new Set(task.windows.map(w => Compositor.windowForToplevel(w))
                                                        .filter(c => c && c.pid > 0).map(c => String(c.pid)))]
                visible: pids.length > 0
                text: "Force Quit"
                icon: "process-stop"
                onTriggered: { menu.close(); Quickshell.execDetached(["kill", "-KILL"].concat(pids)); }
            }
        }
    }
}
