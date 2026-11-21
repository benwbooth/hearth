import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The capture overlay (Print), hearth's take on Spectacle's: every screen
// freezes under a dim veil with a glass toolbar at the bottom of the
// focused one.
//   Region      drag a rectangle; drag inside it to move it, the handles to
//               resize; a magnifier follows the pointer while you drag; the
//               size is shown in real pixels; the last region comes back.
//   Window      hover highlights a window, click takes it (arbor draws it
//               alone, even when covered, with or without its title bar
//               and shadow).
//   Screen      click a screen.   All screens   click anywhere.
// Screenshot / Record switches between a picture and a video of the same
// choice. Pointer and Delay apply to the capture. Enter or double-click
// takes it, Esc cancels; R / W / S / A switch modes, arrows nudge the
// region (Shift: resize).
// Without a delay, Region and Screen come from the frozen frame, so menus
// and tooltips open when you pressed Print stay in the picture.
Scope {
    id: root
    property bool open: false
    property string mode: "region"
    property bool record: false
    property bool pointer: false
    property int delay: 0
    // Selection: { output, x, y, w, h } in that output's logical px.
    property var sel: null
    readonly property bool hasSel: !!sel && sel.w >= 2 && sel.h >= 2

    Connections {
        target: Screenshots
        function onOverlayRequested(m) {
            if (root.open) return;
            root.record = m === "record";
            root.mode = m === "region" || m === "window" ? m : (Screenshots.opt("mode") || "region");
            if (root.record && root.mode === "all") root.mode = "screen";
            root.pointer = !!Screenshots.opt("pointer");
            root.delay = Number(Screenshots.opt("delay")) || 0;
            const last = Screenshots.opt("lastRegion");
            root.sel = Screenshots.opt("rememberRegion") && last && last.w > 0 ? last : null;
            Screenshots.cancelDelay();
            Compositor.refresh();
            root.open = true;
        }
    }

    function setMode(m) {
        if (root.record && m === "all") return;
        root.mode = m;
        Screenshots.setOpt("mode", m);
    }
    function close() { root.open = false; }

    // The pointer is drawn into the frozen frame, so toggling it takes a
    // fresh one: hide, then reopen with the selection kept.
    function setPointer(on) {
        Screenshots.setOpt("pointer", on);
        root.pointer = on;
        root.open = false;
        reopen.restart();
    }
    Timer { id: reopen; interval: 180; onTriggered: { Compositor.refresh(); root.open = true; } }

    // Scripting the open overlay (and tests):
    //   hearth-ipc call screenshot-overlay select OUTPUT X Y W H   (logical px)
    //   hearth-ipc call screenshot-overlay setMode window | pickWindow ID | capture | cancel
    IpcHandler {
        target: "screenshot-overlay"
        function select(output: string, x: real, y: real, w: real, h: real): void {
            root.setMode("region");
            root.sel = { output: output, x: x, y: y, w: w, h: h };
        }
        function setMode(m: string): void { root.setMode(m); }
        function capture(): void {
            if (root.mode === "region") root.confirm(root.selWindow, null);
            else if (root.mode !== "window") root.confirm(root.mainWindow, null);
        }
        function pickWindow(id: string): void {
            const w = root.mainWindow ? root.mainWindow.windows.find(x => x.o.id === id) : null;
            if (w) root.confirm(root.mainWindow, w);
        }
        function cancel(): void { root.close(); }
    }
    property var mainWindow: null

    function screenNamed(name) { return Quickshell.screens.find(s => s.name === name) || null; }
    function globalRect(r) {
        const s = screenNamed(r.output);
        return { x: r.x + (s ? s.x : 0), y: r.y + (s ? s.y : 0), w: r.w, h: r.h };
    }

    // Takes the current choice. `win` is the overlay window the click or
    // key came from (frozen captures crop from its frame); `target` the
    // window object in Window mode.
    function confirm(win, target) {
        const m = root.mode;
        if (m === "region" && !root.hasSel) return;
        if (m === "window" && !target) return;
        if (m === "region") Screenshots.setOpt("lastRegion", root.sel);
        const d = root.delay;
        const sel = root.sel;
        const out = win ? win.screen.name : Compositor.focusedOutput;

        if (root.record) {
            const what = m === "region" ? { region: globalRect(sel) }
                       : m === "window" ? { region: globalRect({ output: out, x: target.x, y: target.y, w: target.w, h: target.h }) }
                       : { output: out };
            const title = m === "window" ? target.o.title : m === "region" ? "Region" : out;
            root.close();
            Screenshots.later(d, () => Screenshots.startRecording(what, title));
            return;
        }
        if (d === 0 && win && (m === "region" || m === "screen")) {
            win.grabFrozen(m === "region" ? sel : { x: 0, y: 0, w: win.width, h: win.height },
                           m === "region" ? "Region" : out);
            return;
        }
        root.close();
        const p = root.pointer;
        if (m === "region") Screenshots.later(d, () => Screenshots.grabRegion(globalRect(sel), p));
        else if (m === "screen") Screenshots.later(d, () => Screenshots.grabScreen(out, p));
        else if (m === "all") Screenshots.later(d, () => Screenshots.grabScreen("", p));
        else Screenshots.later(d, () => Screenshots.grabWindow(target.o.id, { pointer: p }));
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hearth-screenshot"
            WlrLayershell.keyboardFocus: isMain ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            readonly property bool isMain: (Compositor.focusedOutput || Quickshell.screens[0].name) === screen.name
            // The window's own (fractional) scale; screen.devicePixelRatio is rounded up.
            readonly property real dpr: devicePixelRatio || 1
            readonly property bool selHere: !!root.sel && root.sel.output === screen.name
            readonly property rect selRect: selHere ? Qt.rect(root.sel.x, root.sel.y, root.sel.w, root.sel.h) : Qt.rect(0, 0, 0, 0)

            // Snap to device pixels so the crop is pixel exact at 4/3.
            function snap(v) { return Math.round(v * dpr) / dpr; }
            function setSel(x, y, w, h) {
                x = Math.max(0, Math.min(x, width)); y = Math.max(0, Math.min(y, height));
                w = Math.max(0, Math.min(w, width - x)); h = Math.max(0, Math.min(h, height - y));
                root.sel = { output: screen.name, x: snap(x), y: snap(y), w: snap(w), h: snap(h) };
            }

            // Visible windows on this screen's active workspace, topmost first.
            readonly property var windows: {
                const act = Compositor.workspaces.find(w => w.active && w.output === win.screen.name);
                const ws = act ? act.id : null;
                const list = [];
                for (const t of Compositor.windows) {
                    if (t.minimized || !t.at || !t.size || t.workspaceId !== ws) continue;
                    list.push({ o: t, x: t.at[0], y: t.at[1], w: t.size[0], h: t.size[1] });
                }
                list.sort((a, b) => (b.o.floating - a.o.floating) || (a.o.focusOrder - b.o.focusOrder));
                return list;
            }
            function windowAt(px, py) {
                for (const w of windows)
                    if (px >= w.x && py >= w.y && px < w.x + w.w && py < w.y + w.h) return w;
                return null;
            }

            // Crops the frozen frame (device pixels) and hands it on.
            function grabFrozen(r, title) {
                cropper.sourceRect = Qt.rect(r.x, r.y, r.w, r.h);
                cropper.width = r.w;
                cropper.height = r.h;
                // grabToImage scales its size by the window's scale itself.
                cropper.textureSize = Qt.size(Math.round(r.w * dpr), Math.round(r.h * dpr));
                cropper.grabToImage(res => {
                    const f = Screenshots.tmpPath("png");
                    if (res.saveToFile(f)) { root.close(); Screenshots.deliver(f, title); }
                    else { root.close(); Screenshots.failed("couldn't write " + f); }
                }, Qt.size(r.w, r.h));
            }

            // Behind the frozen frame: rendered only for grabToImage.
            ShaderEffectSource {
                id: cropper
                z: -1
                sourceItem: frozen
                live: false
                smooth: false
                hideSource: false
            }

            ScreencopyView {
                id: frozen
                anchors.fill: parent
                captureSource: win.screen
                paintCursor: root.pointer
                live: false
            }

            // Dim everything outside the hole.
            readonly property rect hole: {
                if (root.mode === "screen" || root.mode === "all") return Qt.rect(0, 0, win.width, win.height);
                if (root.mode === "window") {
                    const w = mouse.hovered;
                    return w ? Qt.rect(w.x, w.y, w.w, w.h) : Qt.rect(0, 0, 0, 0);
                }
                return selRect;
            }
            Item {
                anchors.fill: parent
                readonly property color dim: Qt.rgba(0, 0, 0, root.mode === "screen" || root.mode === "all" ? 0.18 : 0.45)
                Rectangle { color: parent.dim; x: 0; y: 0; width: parent.width; height: win.hole.y }
                Rectangle { color: parent.dim; x: 0; y: win.hole.y + win.hole.height; width: parent.width; height: parent.height - y }
                Rectangle { color: parent.dim; x: 0; y: win.hole.y; width: win.hole.x; height: win.hole.height }
                Rectangle { color: parent.dim; x: win.hole.x + win.hole.width; y: win.hole.y; width: parent.width - x; height: win.hole.height }
                // Screen modes: a frame round the whole screen.
                Rectangle {
                    visible: root.mode === "screen" || root.mode === "all"
                    anchors.fill: parent
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: mouse.containsMouse || root.mode === "all" ? 4 : 0
                }
                Rectangle {
                    visible: win.hole.width > 0 && (root.mode === "region" || root.mode === "window")
                    x: win.hole.x - 1; y: win.hole.y - 1
                    width: win.hole.width + 2; height: win.hole.height + 2
                    color: "transparent"
                    border.color: root.record ? Theme.bad : Theme.accent
                    border.width: 2
                }
                // Resize handles.
                Repeater {
                    model: root.mode === "region" && win.selHere && root.hasSel ? 8 : 0
                    Rectangle {
                        required property int index
                        readonly property var p: [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]][index]
                        width: 12; height: 12; radius: 6
                        x: win.selRect.x + p[0] * win.selRect.width - 6
                        y: win.selRect.y + p[1] * win.selRect.height - 6
                        color: "#ffffff"
                        border.color: root.record ? Theme.bad : Theme.accent
                        border.width: 2
                    }
                }
                // Size in real pixels, and the window's title in Window mode.
                Rectangle {
                    readonly property rect r: win.hole
                    visible: (root.mode === "region" && win.selHere && root.hasSel) || (root.mode === "window" && !!mouse.hovered)
                    x: Math.max(4, Math.min(r.x, parent.width - width - 4))
                    y: r.y - height - 8 >= 0 ? r.y - height - 8 : Math.min(parent.height - height - 4, r.y + 8)
                    width: sizeLabel.implicitWidth + 16; height: sizeLabel.implicitHeight + 8
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.66)
                    Label {
                        id: sizeLabel
                        anchors.centerIn: parent
                        color: "#ffffff"
                        text: (root.mode === "window" && mouse.hovered ? mouse.hovered.o.title + "  ·  " : "")
                            + Math.round(parent.r.width * win.dpr) + " × " + Math.round(parent.r.height * win.dpr)
                    }
                }
            }

            // The magnifier: 8x of the frozen frame round the pointer, with
            // a crosshair and the pixel position.
            Item {
                id: loupe
                readonly property real zoom: 8
                visible: root.mode === "region" && mouse.pressed && mouse.drag !== "move"
                width: 150; height: 150
                x: mouse.mouseX + 24 + width > win.width ? mouse.mouseX - 24 - width : mouse.mouseX + 24
                y: mouse.mouseY + 24 + height > win.height ? mouse.mouseY - 24 - height : mouse.mouseY + 24
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#000000"
                    border.color: "#ffffff"
                    border.width: 3
                    clip: true
                    layer.enabled: true
                    ShaderEffectSource {
                        anchors.fill: parent
                        anchors.margins: 3
                        sourceItem: frozen
                        smooth: false
                        live: true
                        readonly property real span: width / loupe.zoom
                        sourceRect: Qt.rect(mouse.mouseX - span / 2, mouse.mouseY - span / 2, span, span)
                    }
                    Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Theme.accent; opacity: 0.8 }
                    Rectangle { anchors.centerIn: parent; height: 1; width: parent.width; color: Theme.accent; opacity: 0.8 }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 4
                    width: posLabel.implicitWidth + 12; height: posLabel.implicitHeight + 4
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.66)
                    Label {
                        id: posLabel
                        anchors.centerIn: parent
                        color: "#ffffff"
                        text: Math.round(mouse.mouseX * win.dpr) + ", " + Math.round(mouse.mouseY * win.dpr)
                    }
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                property var hovered: null
                // Region drag: "new" | "move" | handle index 0..7 (clockwise from top-left).
                property var drag: null
                property point start: Qt.point(0, 0)
                property rect startSel: Qt.rect(0, 0, 0, 0)

                function handleAt(px, py) {
                    if (!win.selHere || !root.hasSel) return -1;
                    const r = win.selRect;
                    const pts = [[0, 0], [0.5, 0], [1, 0], [1, 0.5], [1, 1], [0.5, 1], [0, 1], [0, 0.5]];
                    for (let i = 0; i < 8; i++) {
                        const hx = r.x + pts[i][0] * r.width, hy = r.y + pts[i][1] * r.height;
                        if (Math.abs(px - hx) <= 10 && Math.abs(py - hy) <= 10) return i;
                    }
                    return -1;
                }
                function inSel(px, py) {
                    const r = win.selRect;
                    return win.selHere && px >= r.x && py >= r.y && px < r.x + r.width && py < r.y + r.height;
                }
                cursorShape: {
                    if (root.mode !== "region") return Qt.PointingHandCursor;
                    const h = drag !== null ? (typeof drag === "number" ? drag : -1) : handleAt(mouseX, mouseY);
                    if (h === 0 || h === 4) return Qt.SizeFDiagCursor;
                    if (h === 2 || h === 6) return Qt.SizeBDiagCursor;
                    if (h === 1 || h === 5) return Qt.SizeVerCursor;
                    if (h === 3 || h === 7) return Qt.SizeHorCursor;
                    if (drag === "move" || (drag === null && inSel(mouseX, mouseY))) return Qt.SizeAllCursor;
                    return Qt.CrossCursor;
                }

                onPositionChanged: m => {
                    if (root.mode === "window") { hovered = win.windowAt(m.x, m.y); return; }
                    if (root.mode !== "region" || drag === null) return;
                    const s = startSel, dx = m.x - start.x, dy = m.y - start.y;
                    if (drag === "new") {
                        win.setSel(Math.min(start.x, m.x), Math.min(start.y, m.y), Math.abs(dx), Math.abs(dy));
                    } else if (drag === "move") {
                        win.setSel(Math.max(0, Math.min(s.x + dx, win.width - s.width)),
                                   Math.max(0, Math.min(s.y + dy, win.height - s.height)), s.width, s.height);
                    } else {
                        let x1 = s.x, y1 = s.y, x2 = s.x + s.width, y2 = s.y + s.height;
                        if ([0, 6, 7].includes(drag)) x1 += dx;
                        if ([2, 3, 4].includes(drag)) x2 += dx;
                        if ([0, 1, 2].includes(drag)) y1 += dy;
                        if ([4, 5, 6].includes(drag)) y2 += dy;
                        win.setSel(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
                    }
                }
                onPressed: m => {
                    if (root.mode !== "region") return;
                    start = Qt.point(m.x, m.y);
                    startSel = win.selRect;
                    const h = handleAt(m.x, m.y);
                    if (h >= 0) drag = h;
                    else if (inSel(m.x, m.y)) drag = "move";
                    else { drag = "new"; win.setSel(m.x, m.y, 0, 0); }
                }
                onReleased: m => {
                    if (root.mode === "region") { drag = null; return; }
                    if (root.mode === "window") { const w = win.windowAt(m.x, m.y); if (w) root.confirm(win, w); }
                    else root.confirm(win, null);
                }
                onDoubleClicked: m => { if (root.mode === "region" && inSel(m.x, m.y)) root.confirm(win, null); }
            }

            // The toolbar, on the focused screen.
            GlassFrame {
                id: bar
                visible: win.isMain && !mouse.pressed
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 48
                width: row.implicitWidth + 20
                height: row.implicitHeight + 14
                radius: height / 2

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: [
                            { m: "region", icon: "select-rectangular", text: "Region", key: "R", tip: "Drag out a rectangle" },
                            { m: "window", icon: "window", text: "Window", key: "W", tip: "Click a window" },
                            { m: "screen", icon: "video-display", text: "Screen", key: "S", tip: "Click a screen" },
                            { m: "all", icon: "view-fullscreen", text: "All Screens", key: "A", tip: "Every screen in one picture" }
                        ]
                        delegate: BarButton {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.text
                            tooltip: modelData.tip + " (" + modelData.key + ")"
                            active: root.mode === modelData.m
                            enabled: !(root.record && modelData.m === "all")
                            opacity: enabled ? 1 : 0.4
                            onClicked: root.setMode(modelData.m)
                        }
                    }
                    Rectangle { width: 1; height: 22; anchors.verticalCenter: parent.verticalCenter; color: Theme.menuSeparator }
                    BarButton {
                        icon: "camera-photo"
                        text: "Screenshot"
                        tooltip: "Take a picture"
                        active: !root.record
                        onClicked: root.record = false
                    }
                    BarButton {
                        icon: "media-record"
                        text: "Record"
                        tooltip: "Record a video (stop it from the menu bar)"
                        active: root.record
                        onClicked: { root.record = true; if (root.mode === "all") root.setMode("screen"); }
                    }
                    Rectangle { width: 1; height: 22; anchors.verticalCenter: parent.verticalCenter; color: Theme.menuSeparator }
                    BarButton {
                        icon: "input-mouse"
                        text: "Pointer"
                        tooltip: root.pointer ? "The mouse pointer is in the picture (click to leave it out)"
                                              : "Leave out the mouse pointer (click to include it)"
                        active: root.pointer
                        visible: !root.record
                        onClicked: root.setPointer(!root.pointer)
                    }
                    BarButton {
                        icon: "chronometer"
                        text: root.delay > 0 ? root.delay + " s" : "No delay"
                        tooltip: "Wait before capturing (click to change: none, 3, 5, 10 s)"
                        active: root.delay > 0
                        onClicked: {
                            const steps = [0, 3, 5, 10];
                            root.delay = steps[(steps.indexOf(root.delay) + 1) % steps.length];
                            Screenshots.setOpt("delay", root.delay);
                        }
                    }
                    Item { width: 6; height: 1 }
                    PushButton {
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        text: root.record ? "Record" : "Capture"
                        tooltip: (root.mode === "region" ? "Take the selected region"
                                 : root.mode === "window" ? "Click a window instead"
                                 : root.mode === "screen" ? "Take this screen" : "Take every screen") + " (Enter)"
                        enabled: root.mode === "region" ? root.hasSel : root.mode !== "window"
                        onClicked: root.confirm(root.mode === "region" ? root.selWindow : win, null)
                    }
                    PushButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cancel"
                        tooltip: "Close without capturing (Esc)"
                        onClicked: root.close()
                    }
                    Item { width: 2; height: 1 }
                }
            }
            // root.selWindow: the window holding the selection (frozen crops come from it).
            Connections {
                target: root
                function onSelChanged() { if (win.selHere) root.selWindow = win; }
            }
            Component.onCompleted: {
                if (win.selHere) root.selWindow = win;
                if (win.isMain) root.mainWindow = win;
            }

            Item {
                focus: win.isMain
                anchors.fill: parent
                Keys.onPressed: event => {
                    const shift = event.modifiers & Qt.ShiftModifier;
                    const step = 1 / win.dpr * ((event.modifiers & Qt.ControlModifier) ? 10 : 1);
                    const s = root.sel;
                    const nudge = (dx, dy) => {
                        if (!s || !root.selWindow) return;
                        const w = root.selWindow;
                        if (shift) w.setSel(s.x, s.y, Math.max(1, s.w + dx), Math.max(1, s.h + dy));
                        else w.setSel(Math.max(0, Math.min(s.x + dx, w.width - s.w)), Math.max(0, Math.min(s.y + dy, w.height - s.h)), s.w, s.h);
                    };
                    switch (event.key) {
                    case Qt.Key_Escape: root.close(); break;
                    case Qt.Key_R: root.setMode("region"); break;
                    case Qt.Key_W: root.setMode("window"); break;
                    case Qt.Key_S: root.setMode("screen"); break;
                    case Qt.Key_A: root.setMode("all"); break;
                    case Qt.Key_Left: nudge(-step, 0); break;
                    case Qt.Key_Right: nudge(step, 0); break;
                    case Qt.Key_Up: nudge(0, -step); break;
                    case Qt.Key_Down: nudge(0, step); break;
                    case Qt.Key_Return: case Qt.Key_Enter:
                        if (root.mode === "region") root.confirm(root.selWindow, null);
                        else if (root.mode !== "window") root.confirm(win, null);
                        break;
                    default: return;
                    }
                    event.accepted = true;
                }
            }
        }
    }
    property var selWindow: null

    // Countdown bubble while a delayed capture waits.
    LazyLoader {
        active: Screenshots.countdown > 0

        PanelWindow {
            screen: Compositor.focusedScreen
            anchors { top: true; right: true }
            margins { top: 48; right: 24 }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hearth-screenshot-countdown"
            color: "transparent"
            implicitWidth: 120
            implicitHeight: 120
            mask: Region {}
            GlassFrame {
                anchors.centerIn: parent
                width: 84; height: 84
                radius: 42
                Label {
                    anchors.centerIn: parent
                    text: Screenshots.countdown
                    font.pointSize: Theme.fontSize + 18
                    font.weight: Font.Bold
                }
            }
        }
    }
}
