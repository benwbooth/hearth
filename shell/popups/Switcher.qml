import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// KWin-style Alt+Tab / Meta+Tab task switcher: live thumbnails of the
// windows in most-recently-used order. Hyprland binds drive it, preferably
// through socket2 `custom` events (ordered, no process spawn per key):
//   hl.dispatch(hl.dsp.event("hearth-switcher next"))   -- next|prev|nextApp|prevApp|commit|cancel
// or the IPC target `switcher` with the same function names.
// The first next/prev starts a session; the overlay only appears after
// 150 ms, so a quick Alt+Tab tap just flips to the previous window.
// Letting go of Alt/Super commits through a key-release bind on ALT_L etc.
// with `transparent = true`: Hyprland shadows a modifier's release bind once
// another key (Tab) was pressed with it, and transparent binds are exempt.
// While shown the overlay has the keyboard: arrows, Return, Esc (and a bare
// modifier release as a fallback when no release bind is set up).
Scope {
    id: root

    property bool active: false
    property bool shown: false
    property bool appMode: false
    property var items: []      // [Compositor window]
    property int index: 0

    function addr(t) { return t.id; }
    function klass(t) { return t.appId; }

    function windowList() { return Compositor.windowsByRecency(); }

    function begin(app) {
        let list = windowList();
        if (app && list.length) {
            const c = klass(list[0]);
            list = list.filter(t => klass(t) === c);
        }
        items = list;
        appMode = app;
        active = list.length > 0;
        return active;
    }

    function step(delta, app) {
        if (!active || appMode !== app) {
            if (!begin(app)) return;
            index = items.length > 1 ? (delta > 0 ? 1 : items.length - 1) : 0;
            if (!shown) showTimer.restart();
            return;
        }
        const n = items.length;
        index = ((index + delta) % n + n) % n;
    }

    function commit() {
        if (!active) return;
        const t = items[index];
        finish();
        if (t) activate(t);
    }

    function cancel() { finish(); }

    function finish() {
        showTimer.stop();
        active = false;
        shown = false;
        items = [];
    }

    function activate(t) {
        // Hyprland: pull a window out of a special workspace first.
        if (t.special && Compositor.focusedWorkspace)
            Compositor.moveWindowToWorkspace(t.id, Compositor.focusedWorkspace.id);
        Compositor.focusWindow(t.id);
    }

    function run(cmd) {
        switch (cmd) {
        case "next": step(1, false); break;
        case "prev": step(-1, false); break;
        case "nextApp": step(1, true); break;
        case "prevApp": step(-1, true); break;
        case "commit": commit(); break;
        case "cancel": cancel(); break;
        }
    }

    Timer {
        id: showTimer
        interval: 150
        onTriggered: if (root.active) root.shown = true
    }

    Connections {
        target: Compositor
        function onCustomEvent(data) {
            if (data.startsWith("hearth-switcher ")) root.run(data.split(" ")[1]);
        }
        // A window closed mid-session: drop it from the list.
        function onWindowsChanged() {
            if (!root.active) return;
            const ids = new Set(Compositor.windows.map(w => w.id));
            if (root.items.every(t => ids.has(t.id))) return;
            root.items = root.items.filter(t => ids.has(t.id));
            if (!root.items.length) root.finish();
            else root.index = Math.min(root.index, root.items.length - 1);
        }
    }

    IpcHandler {
        target: "switcher"
        function next(): void { root.run("next"); }
        function prev(): void { root.run("prev"); }
        function nextApp(): void { root.run("nextApp"); }
        function prevApp(): void { root.run("prevApp"); }
        function commit(): void { root.run("commit"); }
        function cancel(): void { root.run("cancel"); }
        // For tests and scripts: the session state as JSON.
        function state(): string {
            return JSON.stringify({ active: root.active, shown: root.shown, appMode: root.appMode, index: root.index,
                                    items: root.items.map(t => ({ address: root.addr(t), title: t.title, class: root.klass(t) })),
                                    mru: Compositor.mru });
        }
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-switcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"

        // Thumbnail cell size: shrink until every window fits on screen.
        readonly property int count: root.items.length
        readonly property real maxW: width * 0.85
        readonly property real maxH: height * 0.8
        readonly property real cellScale: {
            for (let s = 1; s > 0.3; s -= 0.05) {
                const cols = Math.max(1, Math.floor((maxW - 24) / (360 * s)));
                const rows = Math.ceil(count / cols);
                if (rows * 280 * s + 24 <= maxH) return s;
            }
            return 0.3;
        }
        readonly property int cellW: Math.round(360 * cellScale)
        readonly property int cellH: Math.round(280 * cellScale)
        readonly property int cols: Math.max(1, Math.min(count, Math.floor((maxW - 24) / cellW)))

        property var lastPointer: null
        onVisibleChanged: if (visible) { lastPointer = null; keys.forceActiveFocus(); }

        // Clicking outside the panel cancels.
        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            transform: Translate { x: 0.001; y: 0.001 }

            Keys.onPressed: event => {
                const n = root.items.length;
                switch (event.key) {
                // No Tab here: the Hyprland binds step on Tab, and a Tab
                // still held when the overlay takes the keyboard would step twice.
                case Qt.Key_Right: root.index = (root.index + 1) % n; break;
                case Qt.Key_Left: root.index = (root.index + n - 1) % n; break;
                case Qt.Key_Down: root.index = Math.min(n - 1, root.index + win.cols); break;
                case Qt.Key_Up: root.index = Math.max(0, root.index - win.cols); break;
                case Qt.Key_Home: root.index = 0; break;
                case Qt.Key_End: root.index = n - 1; break;
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: root.commit(); break;
                case Qt.Key_Escape: root.cancel(); break;
                default: return;
                }
                event.accepted = true;
            }
            // Fallback for configs without a release bind: letting go of the
            // modifier commits.
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L
                        || event.key === Qt.Key_Super_R) {
                    root.commit();
                    event.accepted = true;
                }
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: grid.width + 24
                height: grid.height + 24 + (root.appMode ? 28 : 0)
                radius: Theme.popupRadius
                color: Qt.rgba(0.125, 0.137, 0.149, 0.94)
                border.color: Theme.border

                // Swallow clicks on the panel's padding.
                MouseArea { anchors.fill: parent }

                Label {
                    visible: root.appMode
                    x: 14
                    y: 8
                    width: parent.width - 28
                    text: {
                        if (!root.items.length) return "";
                        const c = root.klass(root.items[0]);
                        const e = DesktopEntries.heuristicLookup(c);
                        return "Windows of " + (e ? e.name : (c || "this application"));
                    }
                    color: Theme.fgDim
                }

                Grid {
                    id: grid
                    x: 12
                    y: 12 + (root.appMode ? 28 : 0)
                    columns: win.cols
                    Repeater {
                        model: root.shown ? root.items : []
                        delegate: MouseArea {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === root.index
                            readonly property var entry: DesktopEntries.heuristicLookup(root.klass(modelData))
                            width: win.cellW
                            height: win.cellH
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            // Hover selects only once the pointer really moves, so a
                            // cursor resting where the overlay appears doesn't pick a window.
                            onPositionChanged: mouse => {
                                const p = mapToItem(null, mouse.x, mouse.y);
                                const last = win.lastPointer;
                                win.lastPointer = p;
                                if (last && (Math.abs(p.x - last.x) > 2 || Math.abs(p.y - last.y) > 2))
                                    root.index = index;
                            }
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) { Compositor.closeWindow(modelData.id); return; }
                                root.index = index;
                                root.commit();
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: Theme.radius
                                color: cell.selected ? Qt.rgba(0.24, 0.68, 0.91, 0.22) : "transparent"
                                border.color: cell.selected ? Theme.accent : "transparent"
                                border.width: 2
                            }

                            ScreencopyView {
                                id: thumb
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 10
                                width: parent.width - 20
                                height: parent.height - 52
                                captureSource: cell.modelData.toplevel || null
                                visible: !!cell.modelData.toplevel
                                live: true
                                constraintSize: Qt.size(width, height)
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 10
                                spacing: 6
                                width: Math.min(implicitWidth, parent.width - 20)
                                Icon {
                                    id: icon
                                    implicitSize: 22
                                    name: cell.entry ? cell.entry.icon : root.klass(cell.modelData)
                                }
                                Label {
                                    width: Math.min(implicitWidth, cell.width - 48)
                                    height: icon.height
                                    text: cell.modelData.title || root.klass(cell.modelData)
                                    font.weight: cell.selected ? Font.DemiBold : Font.Normal
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
