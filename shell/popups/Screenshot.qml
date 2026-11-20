import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Spectacle-style capture (Print): the screen freezes under a dim overlay
// with a Region / Window / Screen toolbar. Region: drag a rectangle. Window:
// hover highlights a window, click takes it. Screen: click or Enter. The
// capture opens in satty to annotate, copy (Enter) or save (Ctrl+S). Keys:
// R / W / S switch mode, Esc cancels. IPC target `screenshot`: open(),
// region(), window(), screen().
Scope {
    id: root
    property bool open: false
    property string mode: "region"

    function start(m) { mode = m; Compositor.refresh(); open = true; }

    IpcHandler {
        target: "screenshot"
        function open(): void { root.start("region"); }
        function region(): void { root.start("region"); }
        function window(): void { root.start("window"); }
        function screen(): void { root.start("screen"); }
    }

    // Hide the overlay first, then capture the live screen (same pixels as
    // the frozen frame unless something animates) straight into satty.
    property var pending: []
    Timer {
        id: shoot
        interval: 150
        onTriggered: Quickshell.execDetached(root.pending)
    }
    function capture(cmd) {
        pending = ["sh", "-c", cmd + " | satty --filename -"];
        open = false;
        shoot.restart();
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win
            screen: Compositor.focusedScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hearth-screenshot"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            // Selection in window-local logical coordinates.
            property rect sel: Qt.rect(0, 0, 0, 0)
            property bool dragging: false
            property point anchorPt: Qt.point(0, 0)
            readonly property bool hasSel: sel.width > 2 && sel.height > 2

            // Visible windows on this monitor, topmost first.
            readonly property var windows: {
                const act = Compositor.workspaces.find(w => w.active && w.output === win.screen.name);
                const ws = act ? act.id : null;
                const list = [];
                for (const t of Compositor.windows) {
                    const o = t.hypr ? t.hypr.lastIpcObject : null;
                    if (o && (o.hidden || !o.mapped)) continue;
                    if (!t.at || !t.size || t.workspaceId !== ws) continue;
                    list.push({ o: t, x: t.at[0], y: t.at[1], w: t.size[0], h: t.size[1] });
                }
                list.sort((a, b) => a.o.focusOrder - b.o.focusOrder);
                return list;
            }
            function windowAt(px, py) {
                for (const w of windows)
                    if (px >= w.x && py >= w.y && px < w.x + w.w && py < w.y + w.h) return w;
                return null;
            }

            function grabRect(r) {
                const gx = Math.round(r.x + win.screen.x), gy = Math.round(r.y + win.screen.y);
                root.capture(`grim -g "${gx},${gy} ${Math.round(r.width)}x${Math.round(r.height)}" -`);
            }
            function grabScreen() { root.capture(`grim -o ${win.screen.name} -`); }

            // Frozen frame of this output.
            ScreencopyView {
                anchors.fill: parent
                captureSource: win.screen
                live: false
            }

            // Dim everything except the selection (or hovered window).
            readonly property rect hole: {
                if (root.mode === "screen") return Qt.rect(0, 0, win.width, win.height);
                if (root.mode === "window") {
                    const w = hover.hovered;
                    return w ? Qt.rect(w.x, w.y, w.w, w.h) : Qt.rect(0, 0, 0, 0);
                }
                return sel;
            }
            Item {
                anchors.fill: parent
                readonly property color dim: Qt.rgba(0, 0, 0, 0.45)
                Rectangle { color: parent.dim; x: 0; y: 0; width: parent.width; height: win.hole.y }
                Rectangle { color: parent.dim; x: 0; y: win.hole.y + win.hole.height; width: parent.width; height: parent.height - y }
                Rectangle { color: parent.dim; x: 0; y: win.hole.y; width: win.hole.x; height: win.hole.height }
                Rectangle { color: parent.dim; x: win.hole.x + win.hole.width; y: win.hole.y; width: parent.width - x; height: win.hole.height }
                Rectangle {
                    visible: win.hole.width > 0 && root.mode !== "screen"
                    x: win.hole.x - 1; y: win.hole.y - 1
                    width: win.hole.width + 2; height: win.hole.height + 2
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: 2
                }
                // Size readout under a region.
                Rectangle {
                    visible: root.mode === "region" && win.hasSel
                    x: Math.min(win.sel.x, parent.width - width)
                    y: win.sel.y + win.sel.height + 6 + height > parent.height ? win.sel.y - height - 6 : win.sel.y + win.sel.height + 6
                    width: sizeLabel.implicitWidth + 12; height: sizeLabel.implicitHeight + 6
                    radius: Theme.radius; color: Theme.bgRaised
                    Label {
                        id: sizeLabel
                        anchors.centerIn: parent
                        text: Math.round(win.sel.width * win.screen.devicePixelRatio) + " × "
                            + Math.round(win.sel.height * win.screen.devicePixelRatio)
                    }
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.mode === "region" ? Qt.CrossCursor : Qt.PointingHandCursor
                property var hovered: null
                onPositionChanged: mouse => {
                    if (root.mode === "window") hover.hovered = win.windowAt(mouse.x, mouse.y);
                    if (win.dragging) {
                        const a = win.anchorPt;
                        win.sel = Qt.rect(Math.min(a.x, mouse.x), Math.min(a.y, mouse.y),
                                          Math.abs(mouse.x - a.x), Math.abs(mouse.y - a.y));
                    }
                }
                onPressed: mouse => {
                    if (root.mode !== "region") return;
                    win.dragging = true;
                    win.anchorPt = Qt.point(mouse.x, mouse.y);
                    win.sel = Qt.rect(mouse.x, mouse.y, 0, 0);
                }
                onReleased: mouse => {
                    if (root.mode === "region") {
                        win.dragging = false;
                        if (win.hasSel) win.grabRect(win.sel);
                    } else if (root.mode === "window") {
                        const w = win.windowAt(mouse.x, mouse.y);
                        if (w) win.grabRect(Qt.rect(w.x, w.y, w.w, w.h));
                    } else {
                        win.grabScreen();
                    }
                }
            }

            // Mode toolbar, top centre.
            Rectangle {
                id: bar
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24
                width: row.implicitWidth + 16
                height: row.implicitHeight + 12
                radius: Theme.radius
                color: Theme.bgRaised
                border.color: Theme.border
                transform: Translate { x: 0.001; y: 0.001 }

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: [
                            { m: "region", icon: "select-rectangular", text: "Region", key: "R" },
                            { m: "window", icon: "window", text: "Window", key: "W" },
                            { m: "screen", icon: "view-fullscreen", text: "Screen", key: "S" },
                        ]
                        delegate: BarButton {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.text
                            tooltip: modelData.text + " (" + modelData.key + ")"
                            active: root.mode === modelData.m
                            onClicked: { root.mode = modelData.m; win.sel = Qt.rect(0, 0, 0, 0); }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 8
                        rightPadding: 4
                        color: Theme.fgDim
                        text: root.mode === "region" ? "Drag to select · Esc cancels"
                            : root.mode === "window" ? "Click a window · Esc cancels"
                            : "Click or Enter · Esc cancels"
                    }
                }
            }

            Item {
                focus: true
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape: root.open = false; break;
                    case Qt.Key_R: root.mode = "region"; break;
                    case Qt.Key_W: root.mode = "window"; break;
                    case Qt.Key_S: root.mode = "screen"; break;
                    case Qt.Key_Return: case Qt.Key_Enter:
                        if (root.mode === "region" && win.hasSel) win.grabRect(win.sel);
                        else if (root.mode === "screen") win.grabScreen();
                        break;
                    default: return;
                    }
                    event.accepted = true;
                }
            }
        }
    }
}
