import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// Zone layout editor (FanzyZones' editor): a canvas shaped like the display,
// with the layout's zones as boxes in fractions of the work area.
//   drag a zone        move it            drag an edge/corner   resize it
//   click empty space  deselect           double-click a zone   split it left | right
// Toolbar: name, Add, Split ⇆ / ⇅, Duplicate, Delete, Fill gaps, Grid
// (columns x rows with relative sizes), Snap to grid / to other zones,
// Undo / Redo. Keys: Delete, Ctrl+D, Ctrl+Z / Ctrl+Shift+Z, Tab cycles
// zones, arrows move the selected zone one grid step (Shift: resize),
// Ctrl+S saves, Escape deselects (again: closes).
// Saving hands the layout to ZoneEditor.saved; the zones picker writes it to
// zones.json and turns it on for the display.
Scope {
    id: root

    LazyLoader {
        active: ZoneEditor.open

        FloatingWindow {
            id: win
            title: "Zone Layout Editor — " + (nameBox.text || "Untitled")
            visible: true
            color: Theme.bg
            // Smaller on a small screen (it opened past the bottom of a 600 pt one).
            implicitWidth: screenObj ? Math.max(820, Math.min(1100, Math.round(screenObj.width * 0.9))) : 1100
            implicitHeight: screenObj ? Math.max(560, Math.min(760, Math.round(screenObj.height * 0.85))) : 760
            minimumSize: Qt.size(820, 560)
            onVisibleChanged: if (!visible) ZoneEditor.close()

            readonly property var screenObj: Quickshell.screens.find(s => s.name === ZoneEditor.display) || Quickshell.screens[0]
            readonly property real aspect: screenObj && screenObj.height > 0 ? screenObj.width / screenObj.height : 16 / 9

            // --- document -------------------------------------------------
            property var zones: []
            property int sel: -1
            property bool snapGrid: true
            property bool snapEdges: true
            // Against the column (the row itself grows past it when too wide).
            readonly property bool compactBar: toolbar.fullWidth > toolbar.parent.width + 0.5
            property int divisions: 24
            readonly property real minSize: 0.05
            property var history: []
            property int historyAt: -1

            Component.onCompleted: {
                zones = ZoneEditor.layout.zones.slice();
                nameBox.text = ZoneEditor.layout.name;
                remember();
            }

            function copyZones(zs) { return zs.map(z => ({ x: z.x, y: z.y, width: z.width, height: z.height })); }
            function remember() {
                const h = history.slice(0, historyAt + 1);
                h.push(copyZones(zones));
                history = h.slice(-200);
                historyAt = history.length - 1;
            }
            function setZones(zs, keepSel) {
                zones = zs;
                if (!keepSel || sel >= zones.length) sel = Math.min(sel, zones.length - 1);
            }
            function undo() { if (historyAt > 0) { historyAt--; setZones(copyZones(history[historyAt])); } }
            function redo() { if (historyAt < history.length - 1) { historyAt++; setZones(copyZones(history[historyAt])); } }

            // --- geometry ---------------------------------------------------
            function clamp(r) {
                const w = Math.min(1, Math.max(minSize, r.width));
                const h = Math.min(1, Math.max(minSize, r.height));
                return { x: Math.min(Math.max(0, r.x), 1 - w), y: Math.min(Math.max(0, r.y), 1 - h), width: w, height: h };
            }
            function snapValue(v, axis, exclude) {
                const near = 0.012;
                if (snapEdges) {
                    // Other zones' edges and the canvas edges win when close.
                    let best = null, bd = near;
                    const cand = [0, 1];
                    zones.forEach((z, i) => {
                        if (i === exclude) return;
                        if (axis === "x") cand.push(z.x, z.x + z.width); else cand.push(z.y, z.y + z.height);
                    });
                    for (const c of cand) { const d = Math.abs(c - v); if (d < bd) { bd = d; best = c; } }
                    if (best !== null) return best;
                }
                return snapGrid ? Math.round(v * divisions) / divisions : v;
            }
            // Moves keep the size and snap whichever edge is closer.
            function snapMove(r, i) {
                const lx = snapValue(r.x, "x", i), rx = snapValue(r.x + r.width, "x", i) - r.width;
                const ty = snapValue(r.y, "y", i), by = snapValue(r.y + r.height, "y", i) - r.height;
                return clamp({ x: Math.abs(lx - r.x) <= Math.abs(rx - r.x) ? lx : rx,
                               y: Math.abs(ty - r.y) <= Math.abs(by - r.y) ? ty : by,
                               width: r.width, height: r.height });
            }
            function replaceZone(i, r) {
                const zs = zones.slice();
                zs[i] = r;
                zones = zs;
            }

            // --- edits ------------------------------------------------------
            function addZone() {
                const zs = zones.slice();
                zs.push({ x: 0.3, y: 0.25, width: 0.4, height: 0.5 });
                zones = zs;
                sel = zs.length - 1;
                remember();
            }
            function split(horizontalCut) {
                if (sel < 0) return;
                const z = zones[sel], zs = zones.slice();
                const a = horizontalCut ? { x: z.x, y: z.y, width: z.width, height: z.height / 2 }
                                        : { x: z.x, y: z.y, width: z.width / 2, height: z.height };
                const b = horizontalCut ? { x: z.x, y: z.y + z.height / 2, width: z.width, height: z.height / 2 }
                                        : { x: z.x + z.width / 2, y: z.y, width: z.width / 2, height: z.height };
                zs.splice(sel, 1, a, b);
                zones = zs;
                remember();
            }
            function duplicate() {
                if (sel < 0) return;
                const z = zones[sel], zs = zones.slice();
                zs.push(clamp({ x: z.x + 0.03, y: z.y + 0.03, width: z.width, height: z.height }));
                zones = zs;
                sel = zs.length - 1;
                remember();
            }
            function remove() {
                if (sel < 0) return;
                const zs = zones.slice();
                zs.splice(sel, 1);
                zones = zs;
                sel = -1;
                remember();
            }
            // Grows the selected zone (or every zone) into empty space next to it.
            function fill() {
                const zs = copyZones(zones);
                const idx = sel >= 0 ? [sel] : zs.map((_, i) => i);
                const blocked = (a, b) => a.x < b.x + b.width - 1e-6 && b.x < a.x + a.width - 1e-6
                                       && a.y < b.y + b.height - 1e-6 && b.y < a.y + a.height - 1e-6;
                for (const i of idx) {
                    const z = zs[i], others = zs.filter((_, j) => j !== i);
                    const grow = (key, sizeKey, dir) => {
                        for (let step = 0; step < 400; step++) {
                            const t = Object.assign({}, z);
                            if (dir < 0) { t[key] -= 0.0025; t[sizeKey] += 0.0025; } else t[sizeKey] += 0.0025;
                            if (t[key] < -1e-9 || t[key] + t[sizeKey] > 1 + 1e-9 || others.some(o => blocked(t, o))) break;
                            Object.assign(z, t);
                        }
                    };
                    grow("x", "width", -1); grow("x", "width", 1); grow("y", "height", -1); grow("y", "height", 1);
                    for (const k of ["x", "y", "width", "height"]) z[k] = Math.round(z[k] * 1000) / 1000;
                }
                zones = zs;
                remember();
            }
            function weights(s) {
                const w = String(s).split(/[\s,:\/]+/).map(Number).filter(n => n > 0);
                return w.length ? w : [1];
            }
            function applyGrid(cols, rows) {
                const cw = weights(cols), rw = weights(rows);
                const cs = cw.reduce((a, b) => a + b, 0), rs = rw.reduce((a, b) => a + b, 0);
                const zs = [];
                let y = 0;
                for (const r of rw) {
                    let x = 0;
                    for (const c of cw) { zs.push({ x: x / cs, y: y / rs, width: c / cs, height: r / rs }); x += c; }
                    y += r;
                }
                zones = zs;
                sel = -1;
                remember();
            }
            function nudge(dx, dy, resize) {
                if (sel < 0) return;
                const z = zones[sel], st = 1 / divisions;
                replaceZone(sel, clamp(resize ? { x: z.x, y: z.y, width: z.width + dx * st, height: z.height + dy * st }
                                              : { x: z.x + dx * st, y: z.y + dy * st, width: z.width, height: z.height }));
                remember();
            }
            function save() {
                const name = nameBox.text.trim() || "My Layout";
                // Reading order: top to bottom, then left to right (zone numbers).
                const zs = copyZones(zones).map(z => {
                    for (const k in z) z[k] = Math.round(z[k] * 10000) / 10000;
                    return z;
                }).sort((p, q) => Math.abs(p.y - q.y) > 1e-4 ? p.y - q.y : p.x - q.x)
                  .map((z, i) => Object.assign({ name: "Zone " + (i + 1) }, z));
                const id = ZoneEditor.layout.id
                    || "user." + name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36);
                ZoneEditor.saved({ id: id, name: name, is_built_in: false, zones: zs }, ZoneEditor.display);
                ZoneEditor.close();
            }
            readonly property bool overlapping: {
                for (let i = 0; i < zones.length; i++)
                    for (let j = i + 1; j < zones.length; j++) {
                        const a = zones[i], b = zones[j];
                        if (a.x < b.x + b.width - 1e-4 && b.x < a.x + a.width - 1e-4
                            && a.y < b.y + b.height - 1e-4 && b.y < a.y + a.height - 1e-4) return true;
                    }
                return false;
            }
            readonly property real coverage: {
                // Rough share of the screen covered (sampled).
                let hit = 0;
                const n = 40;
                for (let i = 0; i < n; i++)
                    for (let j = 0; j < n; j++) {
                        const px = (i + 0.5) / n, py = (j + 0.5) / n;
                        if (zones.some(z => px >= z.x && px < z.x + z.width && py >= z.y && py < z.y + z.height)) hit++;
                    }
                return hit / (n * n);
            }

            // Scripting (and tests): hearth-ipc call zone-editor-window zones | select N | add | split lr|tb
            // | duplicate | remove | fill | grid "1 2 1" "1" | nudge DX DY RESIZE | undo | redo | save | cancel
            IpcHandler {
                target: "zone-editor-window"
                function zones(): string { return JSON.stringify({ sel: win.sel, zones: win.zones }); }
                function select(i: int): void { win.sel = i; }
                function add(): void { win.addZone(); }
                function split(dir: string): void { win.split(dir === "tb"); }
                function duplicate(): void { win.duplicate(); }
                function remove(): void { win.remove(); }
                function fill(): void { win.fill(); }
                function grid(cols: string, rows: string): void { win.applyGrid(cols, rows); }
                function nudge(dx: int, dy: int, resize: bool): void { win.nudge(dx, dy, resize); }
                function undo(): void { win.undo(); }
                function redo(): void { win.redo(); }
                function save(): void { win.save(); }
                function cancel(): void { ZoneEditor.close(); }
            }

            Shortcut { sequence: StandardKey.Undo; onActivated: win.undo() }
            Shortcut { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; onActivated: win.redo() }
            Shortcut { sequence: "Ctrl+D"; onActivated: win.duplicate() }
            Shortcut { sequence: "Ctrl+S"; onActivated: win.save() }
            Shortcut { sequences: ["Delete", "Backspace"]; enabled: !nameBox.input.activeFocus; onActivated: win.remove() }
            Shortcut { sequence: "Tab"; enabled: !nameBox.input.activeFocus && win.zones.length > 0; onActivated: win.sel = (win.sel + 1) % win.zones.length }
            Shortcut { sequence: "Escape"; onActivated: { if (nameBox.input.activeFocus) canvasArea.forceActiveFocus(); else if (win.sel >= 0) win.sel = -1; else ZoneEditor.close(); } }
            Shortcut { sequence: "Left"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(-1, 0, false) }
            Shortcut { sequence: "Right"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(1, 0, false) }
            Shortcut { sequence: "Up"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(0, -1, false) }
            Shortcut { sequence: "Down"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(0, 1, false) }
            Shortcut { sequence: "Shift+Left"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(-1, 0, true) }
            Shortcut { sequence: "Shift+Right"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(1, 0, true) }
            Shortcut { sequence: "Shift+Up"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(0, -1, true) }
            Shortcut { sequence: "Shift+Down"; enabled: !nameBox.input.activeFocus; onActivated: win.nudge(0, 1, true) }

            // A toolbar button with an icon, text and tooltip.
            component ToolBtn: MouseArea {
                id: tb
                property string icon: ""
                property string text: ""
                property string tip: ""
                property bool checked: false
                // Icon only when the window is too narrow for the full toolbar
                // (the tooltip still names it).
                readonly property bool compact: win.compactBar && icon !== ""
                // Width with the text shown, whatever `compact` is.
                readonly property real fullWidth: (icon !== "" ? 16 : 0) + (text !== "" ? tbLabel.implicitWidth + (icon !== "" ? 6 : 0) : 0) + 16
                implicitWidth: tbRow.implicitWidth + 16
                implicitHeight: 30
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                opacity: enabled ? 1 : 0.4
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: tb.checked ? Theme.accentDim : tb.pressed ? Theme.pressed : tb.containsMouse ? Theme.hover : "transparent"
                    border.color: tb.checked ? Theme.accent : "transparent"
                }
                Row {
                    id: tbRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: tb.icon; implicitSize: 16; visible: tb.icon !== ""; anchors.verticalCenter: parent.verticalCenter }
                    Label { id: tbLabel; text: tb.text; visible: tb.text !== "" && !tb.compact; anchors.verticalCenter: parent.verticalCenter }
                }
                Tooltip { anchorItem: tb; text: tb.compact && tb.text !== "" ? tb.text + ": " + tb.tip : tb.tip; hovered: tb.containsMouse && !tb.pressed }
            }
            component Sep: Rectangle { implicitWidth: 1; implicitHeight: 22; color: Theme.border }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                transform: Translate { x: 0.001; y: 0.001 }

                // --- toolbar ---
                RowLayout {
                    id: toolbar
                    Layout.fillWidth: true
                    spacing: 4
                    // Everything at full size (text on the buttons, a 220 px
                    // name box). Buttons that don't fill are fixed at their
                    // width in a layout, so a too-wide row pushed the whole
                    // window's contents past its right edge.
                    readonly property real fullWidth: {
                        let w = 0, n = 0;
                        for (const c of children) {
                            if (!c.visible) continue;
                            w += c === nameBox ? 220 : c.fullWidth !== undefined ? c.fullWidth : c.implicitWidth;
                            n++;
                        }
                        return w + Math.max(0, n - 1) * spacing;
                    }
                    TextBox {
                        id: nameBox
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        Layout.maximumWidth: 220
                        Layout.preferredWidth: 220
                        placeholder: "Layout name"
                    }
                    Item { implicitWidth: 6 }
                    ToolBtn { icon: "list-add"; text: "Add"; tip: "Add a zone in the middle (then drag it into place)"; onClicked: win.addZone() }
                    ToolBtn { icon: "view-split-left-right"; text: "Split"; tip: "Split the selected zone into a left and a right half (or double-click it)"; enabled: win.sel >= 0; onClicked: win.split(false) }
                    ToolBtn { icon: "view-split-top-bottom"; text: "Split"; tip: "Split the selected zone into a top and a bottom half"; enabled: win.sel >= 0; onClicked: win.split(true) }
                    ToolBtn { icon: "edit-copy"; tip: "Duplicate the selected zone (Ctrl+D)"; enabled: win.sel >= 0; onClicked: win.duplicate() }
                    ToolBtn { icon: "edit-delete"; tip: "Delete the selected zone (Delete)"; enabled: win.sel >= 0; onClicked: win.remove() }
                    ToolBtn { icon: "zoom-fit-best"; text: "Fill"; tip: win.sel >= 0 ? "Grow the selected zone into the empty space around it" : "Grow every zone into the empty space around it"; enabled: win.zones.length > 0; onClicked: win.fill() }
                    Sep {}
                    ToolBtn { icon: "edit-undo"; tip: "Undo (Ctrl+Z)"; enabled: win.historyAt > 0; onClicked: win.undo() }
                    ToolBtn { icon: "edit-redo"; tip: "Redo (Ctrl+Shift+Z)"; enabled: win.historyAt < win.history.length - 1; onClicked: win.redo() }
                    Item { Layout.fillWidth: true }
                    ToolBtn { icon: "snap-bounding-box"; text: "Snap to zones"; checked: win.snapEdges; tip: "Moving or resizing sticks to other zones' edges and the screen edges"; onClicked: win.snapEdges = !win.snapEdges }
                    ToolBtn { icon: "grid-rectangular"; text: "Snap to grid"; checked: win.snapGrid; tip: "Moving or resizing goes in steps of 1/" + win.divisions + " of the screen"; onClicked: win.snapGrid = !win.snapGrid }
                }

                // --- grid maker ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: "Start from a grid:"; color: Theme.fgDim }
                    Label { text: "columns" }
                    TextBox { id: colsBox; Layout.preferredWidth: 80; placeholder: "e.g. 1 2 1"; text: "1 2 1"; onAccepted: win.applyGrid(colsBox.text, rowsBox.text) }
                    Label { text: "rows" }
                    TextBox { id: rowsBox; Layout.preferredWidth: 80; placeholder: "e.g. 1 1"; text: "1"; onAccepted: win.applyGrid(colsBox.text, rowsBox.text) }
                    PushButton { text: "Apply"; tooltip: "Replace the zones with this grid. Numbers are relative sizes: \"1 2 1\" makes a wide middle column."; onClicked: win.applyGrid(colsBox.text, rowsBox.text) }
                    Label { text: "or a layout:"; color: Theme.fgDim; Layout.leftMargin: 8 }
                    Dropdown {
                        id: startFrom
                        // Shrinks (down to 140) before the row would overflow a narrow window.
                        Layout.fillWidth: true
                        Layout.minimumWidth: 140
                        Layout.maximumWidth: 240
                        Layout.preferredWidth: 240
                        placeholder: "Choose a layout…"
                        listWidth: 300
                        searchable: true
                        // Every layout (the built-in ones and yours), each
                        // with its picture.
                        options: (ArborZones.layouts.length ? ArborZones.layouts : ArborZones.builtinLayouts())
                            .map(l => ({ value: l.id, label: l.name, note: l.zones.length + (l.zones.length === 1 ? " zone" : " zones"),
                                         icon: Symbols.zones(l.zones, Theme.fg.toString()) }))
                        Tooltip { anchorItem: startFrom; hovered: startFrom.containsMouse; text: "Replace the zones with a copy of another layout's (Undo brings yours back)" }
                        onPicked: v => {
                            const all = ArborZones.layouts.length ? ArborZones.layouts : ArborZones.builtinLayouts();
                            const l = all.find(x => x.id === v);
                            if (!l) return;
                            win.zones = win.copyZones(l.zones.map(z => ({ x: +z.x, y: +z.y, width: +z.width, height: +z.height })));
                            win.sel = -1;
                            win.remember();
                            startFrom.value = undefined;
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // --- canvas ---
                Item {
                    id: canvasArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    focus: true

                    Rectangle {
                        id: canvas
                        anchors.centerIn: parent
                        width: Math.min(canvasArea.width, canvasArea.height * win.aspect)
                        height: width / win.aspect
                        radius: 8
                        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.28 : 0.08)
                        border.color: Theme.border
                        clip: true

                        // Grid lines (when snapping to the grid).
                        Repeater {
                            model: win.snapGrid ? win.divisions - 1 : 0
                            Rectangle { required property int index; x: (index + 1) * canvas.width / win.divisions; width: 1; height: canvas.height; color: Theme.fg; opacity: (index + 1) % 6 === 0 ? 0.10 : 0.04 }
                        }
                        Repeater {
                            model: win.snapGrid ? win.divisions - 1 : 0
                            Rectangle { required property int index; y: (index + 1) * canvas.height / win.divisions; height: 1; width: canvas.width; color: Theme.fg; opacity: (index + 1) % 6 === 0 ? 0.10 : 0.04 }
                        }

                        // Empty canvas space: click to deselect.
                        MouseArea {
                            anchors.fill: parent
                            onPressed: { win.sel = -1; canvasArea.forceActiveFocus(); }
                        }

                        // By count, not by array: replacing the array while
                        // dragging would recreate the delegate under the mouse.
                        Repeater {
                            model: win.zones.length
                            delegate: Rectangle {
                                id: zr
                                required property int index
                                readonly property var modelData: win.zones[index] || ({ x: 0, y: 0, width: 0, height: 0 })
                                readonly property bool selected: index === win.sel
                                x: modelData.x * canvas.width
                                y: modelData.y * canvas.height
                                width: modelData.width * canvas.width
                                height: modelData.height * canvas.height
                                z: selected ? 2 : 1
                                radius: 6
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, selected ? 0.36 : body.containsMouse ? 0.26 : 0.18)
                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, selected ? 1 : 0.6)
                                border.width: selected ? 2 : 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: zr.index + 1
                                        font.pointSize: Math.max(12, Math.min(40, zr.height / 5))
                                        font.bold: true
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: zr.height > 70 && zr.width > 90
                                        text: Math.round(zr.modelData.width * 100) + "% × " + Math.round(zr.modelData.height * 100) + "%"
                                        color: Theme.fgDim
                                        font.pointSize: Theme.smallFontSize
                                    }
                                }

                                // Body: select and move; double-click splits.
                                MouseArea {
                                    id: body
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    hoverEnabled: true
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    property var start: null
                                    onPressed: m => {
                                        win.sel = zr.index;
                                        canvasArea.forceActiveFocus();
                                        const p = mapToItem(canvas, m.x, m.y);
                                        start = { px: p.x, py: p.y, z: Object.assign({}, zr.modelData) };
                                    }
                                    onPositionChanged: m => {
                                        if (!start) return;
                                        const p = mapToItem(canvas, m.x, m.y);
                                        const r = { x: start.z.x + (p.x - start.px) / canvas.width, y: start.z.y + (p.y - start.py) / canvas.height,
                                                    width: start.z.width, height: start.z.height };
                                        win.replaceZone(zr.index, win.snapMove(win.clamp(r), zr.index));
                                    }
                                    onReleased: { if (start) win.remember(); start = null; }
                                    onDoubleClicked: { win.sel = zr.index; win.split(false); }
                                }

                                readonly property int g: 8
                                // Edges and corners: drag to resize.
                                Repeater {
                                    model: [
                                        { l: 1, r: 0, t: 0, b: 0, c: Qt.SizeHorCursor }, { l: 0, r: 1, t: 0, b: 0, c: Qt.SizeHorCursor },
                                        { l: 0, r: 0, t: 1, b: 0, c: Qt.SizeVerCursor }, { l: 0, r: 0, t: 0, b: 1, c: Qt.SizeVerCursor },
                                        { l: 1, r: 0, t: 1, b: 0, c: Qt.SizeFDiagCursor }, { l: 0, r: 1, t: 1, b: 0, c: Qt.SizeBDiagCursor },
                                        { l: 1, r: 0, t: 0, b: 1, c: Qt.SizeBDiagCursor }, { l: 0, r: 1, t: 0, b: 1, c: Qt.SizeFDiagCursor }
                                    ]
                                    delegate: MouseArea {
                                        required property var modelData
                                        readonly property bool corner: (modelData.l || modelData.r) && (modelData.t || modelData.b)
                                        property var start: null
                                        x: modelData.l ? -zr.g / 2 : modelData.r ? zr.width - (corner ? zr.g : zr.g / 2) : zr.g
                                        y: modelData.t ? -zr.g / 2 : modelData.b ? zr.height - (corner ? zr.g : zr.g / 2) : zr.g
                                        width: corner ? zr.g * 1.5 : (modelData.l || modelData.r) ? zr.g : zr.width - zr.g * 2
                                        height: corner ? zr.g * 1.5 : (modelData.t || modelData.b) ? zr.g : zr.height - zr.g * 2
                                        z: corner ? 4 : 3
                                        hoverEnabled: true
                                        cursorShape: modelData.c
                                        onPressed: m => {
                                            win.sel = zr.index;
                                            const p = mapToItem(canvas, m.x, m.y);
                                            start = { px: p.x, py: p.y, z: Object.assign({}, zr.modelData) };
                                        }
                                        onPositionChanged: m => {
                                            if (!start) return;
                                            const p = mapToItem(canvas, m.x, m.y);
                                            const dx = (p.x - start.px) / canvas.width, dy = (p.y - start.py) / canvas.height;
                                            let x1 = start.z.x, y1 = start.z.y, x2 = start.z.x + start.z.width, y2 = start.z.y + start.z.height;
                                            if (modelData.l) x1 = Math.min(x2 - win.minSize, Math.max(0, win.snapValue(x1 + dx, "x", zr.index)));
                                            if (modelData.r) x2 = Math.max(x1 + win.minSize, Math.min(1, win.snapValue(x2 + dx, "x", zr.index)));
                                            if (modelData.t) y1 = Math.min(y2 - win.minSize, Math.max(0, win.snapValue(y1 + dy, "y", zr.index)));
                                            if (modelData.b) y2 = Math.max(y1 + win.minSize, Math.min(1, win.snapValue(y2 + dy, "y", zr.index)));
                                            win.replaceZone(zr.index, { x: x1, y: y1, width: x2 - x1, height: y2 - y1 });
                                        }
                                        onReleased: { if (start) win.remember(); start = null; }
                                    }
                                }

                                // Corner grip on the selected zone (the resize hint).
                                Rectangle {
                                    visible: zr.selected
                                    width: 12; height: 12; radius: 6
                                    x: zr.width - width - 4; y: zr.height - height - 4
                                    color: Theme.accent
                                    border.color: "white"
                                    border.width: 1.5
                                }
                            }
                        }
                    }
                }

                // --- footer ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        text: win.zones.length + (win.zones.length === 1 ? " zone" : " zones")
                            + (win.sel >= 0 ? "  ·  zone " + (win.sel + 1) + " selected: arrows move it, Shift+arrows resize it" : "  ·  click a zone to select it")
                        color: Theme.fgDim
                    }
                    Label {
                        visible: win.overlapping || win.coverage < 0.97
                        text: win.overlapping ? "Zones overlap (that's allowed: a window snaps to the one under the pointer)"
                                              : Math.round((1 - win.coverage) * 100) + "% of the screen isn't in any zone; Fill grows zones into it"
                        color: Theme.warn
                        font.pointSize: Theme.smallFontSize
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillWidth: !(win.overlapping || win.coverage < 0.97) }
                    PushButton { text: "Cancel"; tooltip: "Close without saving (Escape)"; onClicked: ZoneEditor.close() }
                    PushButton {
                        text: "Save Layout"
                        primary: true
                        enabled: win.zones.length > 0
                        tooltip: "Save and use this layout on " + (ZoneEditor.display || "this display") + " (Ctrl+S)"
                        onClicked: win.save()
                    }
                }
            }
        }
    }
}
