import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// Icon-only task manager: pinned launchers plus running apps, grouped by
// desktop entry, like Plasma's icontasks.
Row {
    id: root
    spacing: 2

    function keyFor(toplevel) {
        const e = DesktopEntries.heuristicLookup(toplevel.appId);
        return e ? e.id : (toplevel.appId || "unknown");
    }

    // [{ key, entry, windows: [Toplevel] }]: pins first, in order, then
    // unpinned running apps in the order they appeared.
    readonly property var groups: {
        // Desktop entries load asynchronously: depend on the list so the
        // pins resolve once it's filled.
        void DesktopEntries.applications.values;
        const pins = Pins.ids;
        const tops = ToplevelManager.toplevels.values;
        const byKey = {};
        const order = [];
        for (const id of pins) {
            if (byKey[id]) continue;
            byKey[id] = { key: id, entry: DesktopEntries.byId(id), windows: [], pinned: true };
            order.push(id);
        }
        for (const t of tops) {
            const k = keyFor(t);
            if (!byKey[k]) {
                byKey[k] = { key: k, entry: DesktopEntries.heuristicLookup(t.appId), windows: [], pinned: false };
                order.push(k);
            }
            byKey[k].windows.push(t);
        }
        // Drop pins whose desktop entry no longer exists and isn't running.
        const out = order.map(k => byKey[k]).filter(g => g.entry || g.windows.length > 0);
        return out;
    }

    // Super+N (Plasma's "activate task manager entry N").
    IpcHandler {
        target: ShellState.isActiveScreen(QsWindow.window ? QsWindow.window.screen : null) ? "tasks" : ""
        function activate(n: int): void {
            const item = repeater.itemAt(n - 1);
            if (item) item.trigger();
        }
    }

    Repeater {
        id: repeater
        model: ScriptModel {
            values: root.groups
            objectProp: "key"
        }
        delegate: TaskButton {}
    }

    component TaskButton: MouseArea {
        id: task
        required property var modelData
        readonly property var entry: modelData.entry
        readonly property var windows: modelData.windows
        readonly property bool running: windows.length > 0
        readonly property bool focused: windows.some(w => w.activated)
        readonly property bool urgent: windows.some(w => { const h = Hypr.hyprFor(w); return h && h.urgent; })
        readonly property var badge: Badges.forApp(modelData.key)
        property int cycle: 0

        implicitWidth: Theme.barHeight + 4
        implicitHeight: Theme.barHeight
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        function launch() {
            if (entry) entry.execute();
        }

        // Left click: launch, focus, minimize, or cycle through windows.
        function trigger() {
            if (!running) { launch(); return; }
            if (windows.length === 1) {
                const w = windows[0];
                if (w.activated) w.minimized = true;
                else w.activate();
                return;
            }
            // Several windows: each click focuses the next one.
            cycle = (cycle + 1) % windows.length;
            windows[cycle].activate();
        }

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) launch();
            else if (mouse.button === Qt.RightButton) { tip.hovered = false; menu.toggle(); }
            else trigger();
        }
        onWheel: w => {
            if (windows.length < 2) return;
            cycle = (cycle + (w.angleDelta.y < 0 ? 1 : windows.length - 1)) % windows.length;
            windows[cycle].activate();
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: Theme.radius
            color: task.urgent ? Qt.rgba(0.96, 0.45, 0, 0.35)
                 : task.focused ? Qt.rgba(1, 1, 1, 0.16)
                 : task.containsMouse ? Theme.hover
                 : task.running ? Qt.rgba(1, 1, 1, 0.05)
                 : "transparent"
        }

        Icon {
            id: icon
            anchors.centerIn: parent
            implicitSize: Theme.taskIconSize
            name: task.entry ? task.entry.icon : (task.windows.length ? task.windows[0].appId : "")
            opacity: task.pressed ? 0.7 : 1

            // Unity LauncherEntry badge: count and/or progress.
            Rectangle {
                visible: task.badge.countVisible && task.badge.count > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -6
                anchors.topMargin: -4
                height: 16
                width: Math.max(16, countLabel.implicitWidth + 8)
                radius: 8
                color: Theme.bad
                Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: task.badge.count > 99 ? "99+" : String(task.badge.count)
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

        // Running indicator: one dash per window (up to 4) along the bottom.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: 3
            Repeater {
                model: Math.min(task.windows.length, 4)
                Rectangle {
                    width: task.windows.length > 1 ? 6 : 14
                    height: 2
                    radius: 1
                    color: task.focused ? Theme.accent : Theme.fgDim
                }
            }
        }

        // Hover preview: live thumbnails of each window, click to focus.
        PopupWindow {
            id: preview
            property bool hovered: false
            anchor.item: task
            anchor.edges: Edges.Top
            anchor.gravity: Edges.Top
            anchor.adjustment: PopupAdjustment.Slide
            anchor.margins.top: -4
            color: "transparent"
            visible: false
            implicitWidth: previewFrame.implicitWidth
            implicitHeight: previewFrame.implicitHeight

            Timer {
                id: previewShow
                interval: 450
                onTriggered: preview.visible = (task.containsMouse || previewHover.hovered) && !menu.open
            }
            Timer {
                id: previewHide
                interval: 250
                onTriggered: if (!task.containsMouse && !previewHover.hovered) preview.visible = false
            }

            Rectangle {
                id: previewFrame
                anchors.fill: parent
                color: Theme.bgAlt
                border.color: Theme.border
                radius: Theme.popupRadius
                implicitWidth: previewCol.implicitWidth + 16
                implicitHeight: previewCol.implicitHeight + 16
                transform: Translate { x: 0.001; y: 0.001 }

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
                        visible: !task.running && task.entry && task.entry.comment !== ""
                        text: task.entry ? task.entry.comment : ""
                        color: Theme.fgDim
                        width: Math.min(implicitWidth, 360)
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
                                    id: thumbTitle
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

        onContainsMouseChanged: {
            if (containsMouse) { previewHide.stop(); previewShow.restart(); }
            else { previewShow.stop(); previewHide.restart(); }
        }

        // Right-click menu.
        BarPopup {
            id: menu
            anchorItem: task
            padding: 6
            Column {
                width: 240
                spacing: 0
                Label {
                    x: 8
                    height: 28
                    width: parent.width - 16
                    text: task.entry ? task.entry.name : task.modelData.key
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: task.entry ? task.entry.actions : []
                    MenuItem {
                        required property var modelData
                        text: modelData.name
                        icon: modelData.icon
                        onTriggered: { modelData.execute(); menu.close(); }
                    }
                }
                MenuItem {
                    visible: !!task.entry
                    text: task.running ? "New window" : "Open"
                    icon: "list-add"
                    onTriggered: { task.launch(); menu.close(); }
                }
                MenuItem {
                    visible: !!task.entry
                    text: Pins.isPinned(task.modelData.key) ? "Unpin from taskbar" : "Pin to taskbar"
                    icon: Pins.isPinned(task.modelData.key) ? "window-unpin" : "window-pin"
                    onTriggered: {
                        if (Pins.isPinned(task.modelData.key)) Pins.unpin(task.modelData.key);
                        else Pins.pin(task.modelData.key);
                        menu.close();
                    }
                }
                MenuItem {
                    visible: task.windows.length > 0
                    text: task.windows.length > 1 ? `Close all ${task.windows.length} windows` : "Close"
                    icon: "window-close"
                    onTriggered: { for (const w of task.windows) w.close(); menu.close(); }
                }
            }
        }

        Tooltip {
            id: tip
            anchorItem: task
            text: ""
            hovered: false
        }
    }
}
