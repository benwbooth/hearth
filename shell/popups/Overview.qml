import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// KDE Overview / Grid View: every workspace as a live miniature with its
// windows (per-window screencopy placed by geometry), and a search field
// that filters windows by title or app. Click a window to focus it, a
// workspace to switch to it, drag a window onto another workspace (or the
// empty "new workspace" tile) to move it there; Esc or a click on empty
// space closes. IPC target `overview`: toggle(), open(), close(); also the
// socket2 event `hearth-overview toggle|open|close` (hl.dsp.event).
Scope {
    id: root
    property bool open: false

    function toggle() { open = !open; }

    onOpenChanged: if (open) Compositor.refresh()

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open = true; }
        function close(): void { root.open = false; }
        function search(text: string): void { root.open = true; search.text = text; }
    }

    Connections {
        target: ShellState
        function onOverviewRequested() { root.open = true; }
    }
    Connections {
        target: Compositor
        function onCustomEvent(data) {
            if (!data.startsWith("hearth-overview ")) return;
            switch (data.split(" ")[1]) {
            case "toggle": root.toggle(); break;
            case "open": root.open = true; break;
            case "close": root.open = false; break;
            }
        }
    }

    PanelWindow {
        id: ov
        visible: root.open
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-overview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"

        property string query: ""
        property var dragging: null     // Compositor window being dragged

        onVisibleChanged: {
            if (visible) { query = ""; search.text = ""; search.forceActiveFocus(); }
        }

        function addr(t) { return t.id; }
        function klass(t) { return t.appId; }
        function matches(t) {
            const q = query.trim().toLowerCase();
            if (!q) return true;
            const e = DesktopEntries.heuristicLookup(klass(t));
            return [t.title, klass(t), e ? e.name : ""].join(" ").toLowerCase().includes(q);
        }

        // Hyprland: normal workspaces by id, plus an empty tile for "new
        // workspace". niri: this output's workspaces; its trailing empty one
        // already is the new workspace.
        readonly property var workspaces: {
            if (Compositor.isArbor) {
                const ws = Compositor.workspacesOn(Compositor.focusedOutput);
                const used = new Set(Compositor.windows.map(w => w.workspaceId));
                return ws.map((w, i) => ({ id: w.id, name: w.name, ws: w,
                                           fresh: i === ws.length - 1 && !used.has(w.id) }));
            }
            const ws = Compositor.workspacesOn("").filter(w => w.id > 0).sort((a, b) => a.id - b.id);
            const next = ws.length ? ws[ws.length - 1].id + 1 : 1;
            return ws.map(w => ({ id: w.id, name: w.name, ws: w, fresh: false }))
                .concat([{ id: next, name: "", ws: null, fresh: true }]);
        }
        readonly property var windows: Compositor.windows.filter(t => t.workspaceId !== null && !t.special)
        readonly property var hits: windows.filter(t => matches(t))

        function focusWindow(t) {
            root.open = false;
            Compositor.focusWindow(addr(t));
        }

        // Tile size: the column count that gives the biggest miniatures.
        readonly property real aspect: screen ? screen.width / screen.height : 16 / 9
        readonly property real areaW: width - 120
        readonly property real areaH: height - 220
        readonly property int labelH: 30
        readonly property int gap: 28
        readonly property var tiling: {
            const n = workspaces.length;
            let best = { cols: 1, w: 0 };
            for (let c = 1; c <= n; c++) {
                const rows = Math.ceil(n / c);
                const w = Math.min((areaW - gap * (c - 1)) / c,
                                   ((areaH - gap * (rows - 1)) / rows - labelH) * aspect);
                if (w > best.w) best = { cols: c, w: w };
            }
            return { cols: best.cols, w: Math.floor(best.w), h: Math.floor(best.w / aspect) };
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.1, 0.11, 0.12, 0.96)
        }

        // Empty space closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Item {
            anchors.fill: parent
            transform: Translate { x: 0.001; y: 0.001 }

            // Search field.
            Rectangle {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 48
                width: 520
                height: 40
                radius: Theme.radius
                color: Theme.bg
                border.color: search.activeFocus ? Theme.accent : Theme.border
                MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; name: "search" }
                    TextInput {
                        id: search
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize + 1
                        renderType: Text.NativeRendering
                        selectByMouse: true
                        clip: true
                        onTextChanged: ov.query = text
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                if (text !== "") text = "";
                                else root.open = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (ov.query.trim() !== "" && ov.hits.length) ov.focusWindow(ov.hits[0]);
                                else root.open = false;
                                event.accepted = true;
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Search windows…"
                            color: Theme.fgDim
                            font.pointSize: Theme.fontSize + 1
                        }
                    }
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: searchBox.bottom
                anchors.topMargin: 8
                visible: ov.query.trim() !== ""
                text: ov.hits.length === 0 ? "No matching windows"
                    : ov.hits.length === 1 ? "1 window — Enter to switch to it"
                    : ov.hits.length + " windows — Enter switches to the first"
                color: Theme.fgDim
            }

            Grid {
                id: grid
                anchors.horizontalCenter: parent.horizontalCenter
                y: 140 + Math.max(0, (ov.areaH - height) / 2)
                columns: ov.tiling.cols
                spacing: ov.gap

                Repeater {
                    model: ov.workspaces
                    delegate: Item {
                        id: tile
                        required property var modelData
                        readonly property var ws: modelData.ws
                        readonly property bool current: ws !== null && ws.active
                        readonly property var mon: Compositor.screenFor(ws && ws.output ? ws.output : Compositor.focusedOutput)
                        readonly property real monX: 0
                        readonly property real monY: 0
                        readonly property real monW: mon ? mon.width : ov.screen.width
                        readonly property real k: ov.tiling.w / monW
                        width: ov.tiling.w
                        height: ov.tiling.h + ov.labelH
                        z: ov.dragging && ws && ov.dragging.workspaceId === ws.id ? 10 : 0

                        Label {
                            x: 2
                            width: parent.width - 4
                            height: ov.labelH
                            text: tile.modelData.fresh ? "New workspace"
                                : (tile.ws.name !== String(tile.ws.idx) ? tile.ws.name : "Workspace " + tile.ws.idx)
                            color: tile.current ? Theme.fg : Theme.fgDim
                            font.weight: tile.current ? Font.DemiBold : Font.Normal
                        }

                        Rectangle {
                            id: frame
                            y: ov.labelH
                            width: ov.tiling.w
                            height: ov.tiling.h
                            radius: Theme.radius
                            color: tile.ws ? Theme.bg : "transparent"
                            border.width: drop.containsDrag || tile.current ? 2 : 1
                            border.color: drop.containsDrag ? Theme.accent
                                        : tile.current ? Theme.accent
                                        : wsHover.containsMouse ? Theme.fgDim : Theme.border
                            clip: !ov.dragging

                            MouseArea {
                                id: wsHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.open = false;
                                    Compositor.focusWorkspace(tile.modelData.id);
                                }
                            }

                            Icon {
                                visible: tile.modelData.fresh
                                anchors.centerIn: parent
                                implicitSize: 48
                                name: "list-add"
                                opacity: 0.5
                            }

                            DropArea {
                                id: drop
                                anchors.fill: parent
                                keys: ["hearth-window"]
                                onDropped: drag => {
                                    const t = ov.dragging;
                                    if (t && t.workspaceId !== tile.modelData.id)
                                        Compositor.moveWindowToWorkspace(ov.addr(t), tile.modelData.id);
                                }
                            }

                            Repeater {
                                // Least recently focused first, so the most recent is on top.
                                model: ScriptModel {
                                    objectProp: "id"
                                    values: ov.windows.filter(t => tile.ws !== null && t.workspaceId === tile.ws.id)
                                        .sort((a, b) => b.focusOrder - a.focusOrder)
                                }
                                delegate: Item {
                                    id: win
                                    required property var modelData
                                    readonly property var o: modelData
                                    readonly property bool hit: ov.matches(modelData)
                                    readonly property var entry: DesktopEntries.heuristicLookup(ov.klass(modelData))
                                    property real dx: 0
                                    property real dy: 0
                                    readonly property bool dragged: ov.dragging !== null && ov.dragging.id === modelData.id

                                    x: (o.at ? (o.at[0] - tile.monX) * tile.k : 0) + dx
                                    y: (o.at ? (o.at[1] - tile.monY) * tile.k : 0) + dy
                                    width: Math.max(24, o.size ? o.size[0] * tile.k : 100)
                                    height: Math.max(24, o.size ? o.size[1] * tile.k : 80)
                                    z: dragged ? 100 : 0
                                    opacity: hit ? 1 : 0.25

                                    Drag.active: dragged
                                    Drag.keys: ["hearth-window"]
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: height / 2

                                    ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: win.modelData.toplevel || null
                                        visible: !!win.modelData.toplevel
                                        live: root.open
                                        constraintSize: Qt.size(width, height)
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        color: winMouse.containsMouse ? Qt.rgba(0.24, 0.68, 0.91, 0.15) : "transparent"
                                        border.width: winMouse.containsMouse || (ov.query.trim() !== "" && win.hit) ? 2 : 0
                                        border.color: Theme.accent
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Math.min(12, parent.height * 0.08)
                                        visible: parent.height > 60
                                        width: Math.min(parent.width - 8, iconRow.implicitWidth + 12)
                                        height: 30
                                        radius: Theme.radius
                                        color: Qt.rgba(0.125, 0.137, 0.149, 0.85)
                                        Row {
                                            id: iconRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Icon {
                                                id: winIcon
                                                implicitSize: 22
                                                name: win.entry ? win.entry.icon : ov.klass(win.modelData)
                                            }
                                            Label {
                                                visible: winMouse.containsMouse || ov.query.trim() !== ""
                                                width: Math.min(implicitWidth, win.width - 60)
                                                height: winIcon.height
                                                text: win.modelData.title
                                                font.pointSize: Theme.smallFontSize
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: winMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        property point start
                                        property bool moved: false
                                        onPressed: mouse => {
                                            start = mapToItem(frame, mouse.x, mouse.y);
                                            moved = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                                            const p = mapToItem(frame, mouse.x, mouse.y);
                                            if (!moved && Math.hypot(p.x - start.x, p.y - start.y) < 8) return;
                                            moved = true;
                                            ov.dragging = win.modelData;
                                            win.dx += p.x - start.x;
                                            win.dy += p.y - start.y;
                                            start = p;
                                        }
                                        onReleased: mouse => {
                                            if (moved) {
                                                win.Drag.drop();
                                                ov.dragging = null;
                                                win.dx = 0;
                                                win.dy = 0;
                                            }
                                        }
                                        onClicked: mouse => {
                                            if (moved) return;
                                            if (mouse.button === Qt.MiddleButton) Compositor.closeWindow(win.modelData.id);
                                            else ov.focusWindow(win.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
