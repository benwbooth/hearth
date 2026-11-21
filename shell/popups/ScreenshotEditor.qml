import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// The result window after a capture (Spectacle's main window, in glass):
// the picture, annotation tools, and what to do with it.
//   Copy        the picture (with your marks) to the clipboard
//   Copy Path   save it, then copy where it was saved
//   Save        into the Screenshots folder, named from the pattern in
//               Settings > Screenshots (Ctrl+S)
//   Save As…    pick the place, name and format (Ctrl+Shift+S)
//   Show        open the folder with the saved file selected
//   New         take another screenshot
// Drag the picture into another app (with the Select tool) to drop it as
// a file. Tools: arrow, rectangle, ellipse, freehand, highlighter, text,
// numbered stamps, blur, pixelate and crop; colour and thickness on the
// second row; Ctrl+Z / Ctrl+Shift+Z undo and redo, Delete removes the
// last mark.
Scope {
    id: root
    readonly property bool open: Screenshots.editorFile !== ""

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: "Screenshot" + (Screenshots.editorTitle ? " — " + Screenshots.editorTitle : "")
            visible: true
            color: Theme.bg
            implicitWidth: Math.max(860, Math.min(1500, fitW + 40))
            implicitHeight: Math.max(560, Math.min(1000, fitH + toolbar.height + toolRow.height + 60))
            minimumSize: Qt.size(720, 460)
            onVisibleChanged: if (!visible) Screenshots.closeEditor()

            readonly property real dpr: devicePixelRatio || 1
            readonly property string source: Screenshots.editorFile
            readonly property real fitW: img.sourceSize.width / dpr
            readonly property real fitH: img.sourceSize.height / dpr

            // --- document state ------------------------------------------
            // marks: [{ type, color, width, pts | x1,y1,x2,y2, text, n, size }]
            // crop: { x, y, w, h } in image pixels.
            property var marks: []
            property var crop: ({ x: 0, y: 0, w: img.sourceSize.width, h: img.sourceSize.height })
            property var history: []
            property int historyAt: -1
            readonly property bool edited: marks.length > 0 || crop.x !== 0 || crop.y !== 0
                || crop.w !== img.sourceSize.width || crop.h !== img.sourceSize.height
            property string tool: "select"
            property color penColor: Screenshots.opt("annotationColor")
            property real penWidth: 4
            property string savedPath: ""
            property string exported: ""        // newest export (PNG) for copy/drag
            property bool exportDirty: true
            property string status: ""

            readonly property real unit: dpr    // image px per logical px
            function snapshot() { return { marks: marks.slice(), crop: Object.assign({}, crop) }; }
            function commit() {
                const h = history.slice(0, historyAt + 1);
                h.push(snapshot());
                history = h;
                historyAt = h.length - 1;
                exportDirty = true;
                savedPath = "";
                exportSoon.restart();
            }
            function restore(s) { marks = s.marks.slice(); crop = Object.assign({}, s.crop); exportDirty = true; savedPath = ""; exportSoon.restart(); }
            function undo() { if (historyAt > 0) { historyAt--; restore(history[historyAt]); } }
            function redo() { if (historyAt < history.length - 1) { historyAt++; restore(history[historyAt]); } }
            function addMark(m) { marks = marks.concat([m]); commit(); }
            function nextNumber() { return marks.filter(m => m.type === "number").length + 1; }

            function reset() {
                marks = []; tool = "select"; savedPath = ""; status = "";
                crop = { x: 0, y: 0, w: img.sourceSize.width, h: img.sourceSize.height };
                history = [snapshot()]; historyAt = 0;
                exported = source; exportDirty = false;
            }
            Connections {
                target: Screenshots
                function onEditorSerialChanged() { if (img.status === Image.Ready) win.reset(); }
            }

            // Renders the picture with its marks to a PNG; cb(path).
            function exportPng(cb) {
                if (!edited) { exported = source; exportDirty = false; cb(source); return; }
                if (!exportDirty && exported) { cb(exported); return; }
                // grabToImage multiplies the size by the window's scale.
                const size = Qt.size(crop.w / dpr, crop.h / dpr);
                page.grabToImage(res => {
                    const f = Screenshots.runDir + "/" + Screenshots.formatName(Screenshots.opt("fileName"), Screenshots.editorTitle) + "-edit.png";
                    if (res.saveToFile(f)) { exported = f; exportDirty = false; cb(f); }
                    else Screenshots.failed("couldn't render the picture");
                }, size);
            }
            Timer { id: exportSoon; interval: 400; onTriggered: win.exportPng(() => {}) }

            function flash(msg) { status = msg; statusTimer.restart(); }
            Timer { id: statusTimer; interval: 3500; onTriggered: win.status = "" }

            function copy() {
                exportPng(f => {
                    Screenshots.copyImage(f);
                    flash("Copied to the clipboard");
                    if (Screenshots.opt("closeAfterCopy")) Screenshots.closeEditor();
                });
            }
            function save(cb) {
                if (savedPath) { if (cb) cb(savedPath); return; }
                exportPng(f => Screenshots.saveFile(f, Screenshots.editorTitle, "", p => {
                    savedPath = p;
                    flash("Saved as " + p.replace(Screenshots.home, "~"));
                    if (cb) cb(p);
                    else if (Screenshots.opt("closeAfterSave")) Screenshots.closeEditor();
                }));
            }
            function copyPath() { save(p => { Screenshots.copyText(p); flash("Copied " + p.replace(Screenshots.home, "~")); }); }
            function showFolder() { save(p => Screenshots.showInFolder(p)); }
            function newShot() { Screenshots.closeEditor(); Screenshots.later(0, () => Screenshots.overlayRequested("")); }

            FileDialog {
                id: saveDialog
                title: "Save Screenshot As"
                fileMode: FileDialog.SaveFile
                nameFilters: ["PNG image (*.png)", "JPEG image (*.jpg *.jpeg)", "WebP image (*.webp)"]
                defaultSuffix: Screenshots.extFor(Screenshots.opt("format"))
                onAccepted: {
                    let path = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""));
                    if (!/\.(png|jpe?g|webp)$/i.test(path)) path += "." + Screenshots.extFor(Screenshots.opt("format"));
                    win.exportPng(f => Screenshots.saveFile(f, Screenshots.editorTitle, path, p => {
                        win.savedPath = p;
                        win.flash("Saved as " + p.replace(Screenshots.home, "~"));
                    }));
                }
            }
            function saveAs() {
                saveDialog.currentFolder = "file://" + Screenshots.expand(Screenshots.opt("folder"));
                saveDialog.selectedFile = "file://" + Screenshots.savePathFor(Screenshots.editorTitle);
                saveDialog.open();
            }

            // Scripting (and tests): hearth-ipc call screenshot-editor addMark '{"type":"arrow",...}' | crop X Y W H | save | copy | undo
            IpcHandler {
                target: "screenshot-editor"
                function addMark(json: string): void { win.addMark(JSON.parse(json)); }
                function crop(x: int, y: int, w: int, h: int): void { win.crop = { x: x, y: y, w: w, h: h }; win.commit(); }
                function save(): void { win.save(); }
                function copy(): void { win.copy(); }
                function undo(): void { win.undo(); }
                function savedPath(): string { return win.savedPath; }
            }

            Shortcut { sequence: StandardKey.Copy; onActivated: win.copy() }
            Shortcut { sequence: "Ctrl+S"; onActivated: win.save() }
            Shortcut { sequence: "Ctrl+Shift+S"; onActivated: win.saveAs() }
            Shortcut { sequence: StandardKey.Undo; onActivated: win.undo() }
            Shortcut { sequences: [StandardKey.Redo]; onActivated: win.redo() }
            Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: win.redo() }
            Shortcut { sequence: "Ctrl+N"; onActivated: win.newShot() }
            Shortcut { sequence: "Delete"; onActivated: if (win.marks.length) { win.marks = win.marks.slice(0, -1); win.commit(); } }
            Shortcut { sequence: "Escape"; enabled: !textEdit.visible; onActivated: { if (win.tool !== "select") win.tool = "select"; else Screenshots.closeEditor(); } }
            Shortcut { sequence: "Return"; enabled: win.tool === "crop"; onActivated: cropTool.apply() }

            Item {
                anchors.fill: parent
                transform: Translate { x: 0.001; y: 0.001 }

                // --- top toolbar ----------------------------------------
                Row {
                    id: toolbar
                    x: 10
                    y: 6
                    width: parent.width - 20
                    height: 44
                    spacing: 2

                    Row {
                        id: leftTools
                        spacing: 2
                        BarButton { icon: "document-new"; text: "New"; tooltip: "Take another screenshot (Ctrl+N)"; onClicked: win.newShot() }
                        Rectangle { width: 1; height: 22; anchors.verticalCenter: parent.verticalCenter; color: Theme.menuSeparator }
                        Repeater {
                            model: [
                                { t: "select", icon: "tool-pointer", tip: "Select: drag the picture into another app" },
                                { t: "arrow", icon: "draw-arrow", tip: "Arrow" },
                                { t: "rect", icon: "draw-rectangle", tip: "Rectangle" },
                                { t: "ellipse", icon: "draw-ellipse", tip: "Ellipse" },
                                { t: "pen", icon: "draw-freehand", tip: "Freehand" },
                                { t: "highlight", icon: "draw-highlight", tip: "Highlighter" },
                                { t: "text", icon: "draw-text", tip: "Text: click where it goes, type, Enter" },
                                { t: "number", icon: "draw-number", tip: "Numbered stamp: click to place 1, 2, 3…" },
                                { t: "blur", icon: "blurfx", tip: "Blur: drag over what to hide" },
                                { t: "pixelate", icon: "pixelate", tip: "Pixelate: drag over what to hide" },
                                { t: "crop", icon: "transform-crop", tip: "Crop: drag the edges, Enter to apply" }
                            ]
                            delegate: BarButton {
                                required property var modelData
                                icon: modelData.icon
                                tooltip: modelData.tip
                                active: win.tool === modelData.t
                                onClicked: { textEdit.finish(); win.tool = modelData.t; if (modelData.t === "crop") cropTool.begin(); }
                            }
                        }
                        Rectangle { width: 1; height: 22; anchors.verticalCenter: parent.verticalCenter; color: Theme.menuSeparator }
                        BarButton { icon: "edit-undo"; tooltip: "Undo (Ctrl+Z)"; enabled: win.historyAt > 0; opacity: enabled ? 1 : 0.4; onClicked: win.undo() }
                        BarButton { icon: "edit-redo"; tooltip: "Redo (Ctrl+Shift+Z)"; enabled: win.historyAt < win.history.length - 1; opacity: enabled ? 1 : 0.4; onClicked: win.redo() }
                    }
                    Item { width: Math.max(0, toolbar.width - leftTools.width - rightTools.width - 4); height: 1 }
                    Row {
                        id: rightTools
                        spacing: 2
                        BarButton { icon: "edit-copy"; text: "Copy"; tooltip: "Copy the picture to the clipboard (Ctrl+C)"; onClicked: win.copy() }
                        BarButton { icon: "edit-paste-in-place"; tooltip: "Copy Path: save, then copy where the file is"; onClicked: win.copyPath() }
                        BarButton { icon: "folder-open"; tooltip: "Show the saved file in its folder"; onClicked: win.showFolder() }
                        BarButton { icon: "document-save-as"; tooltip: "Save As… (Ctrl+Shift+S): pick the place, name and format"; onClicked: win.saveAs() }
                        Item { width: 4; height: 1 }
                        PushButton {
                            anchors.verticalCenter: parent.verticalCenter
                            primary: true
                            text: win.savedPath ? "Saved" : "Save"
                            tooltip: "Save into " + Screenshots.opt("folder") + " (Ctrl+S)"
                            onClicked: win.save()
                        }
                    }
                }

                // --- second row: colour, thickness, status --------------
                Row {
                    id: toolRow
                    x: 14
                    anchors.top: toolbar.bottom
                    height: 30
                    spacing: 8
                    Repeater {
                        model: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#007aff", "#af52de", "#ffffff", "#000000"]
                        MouseArea {
                            required property string modelData
                            width: 20; height: 20
                            anchors.verticalCenter: parent.verticalCenter
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { win.penColor = modelData; Screenshots.setOpt("annotationColor", modelData); }
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: parent.modelData
                                border.color: Qt.colorEqual(win.penColor, parent.modelData) ? Theme.fg : Theme.border
                                border.width: Qt.colorEqual(win.penColor, parent.modelData) ? 3 : 1
                            }
                        }
                    }
                    Item { width: 10; height: 1 }
                    Repeater {
                        model: [{ w: 2, l: "Thin" }, { w: 4, l: "Medium" }, { w: 8, l: "Thick" }]
                        BarButton {
                            required property var modelData
                            implicitHeight: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.l
                            tooltip: "Line thickness"
                            active: win.penWidth === modelData.w
                            onClicked: win.penWidth = modelData.w
                        }
                    }
                    Item { width: 16; height: 1 }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(80, win.width - x - 40)
                        elide: Text.ElideMiddle
                        color: Theme.fgDim
                        text: win.status || (win.crop.w + " × " + win.crop.h + " px"
                              + (win.savedPath ? "  ·  " + win.savedPath.replace(Screenshots.home, "~") : ""))
                    }
                }

                // --- the picture ------------------------------------------
                Item {
                    id: viewport
                    anchors.top: toolRow.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 16
                    clip: true

                    // What's shown: the cropped picture, or all of it while cropping.
                    readonly property var shown: win.tool === "crop"
                        ? { x: 0, y: 0, w: img.sourceSize.width, h: img.sourceSize.height } : win.crop
                    // Image px -> logical px; never larger than 1:1.
                    readonly property real zoom: shown.w > 0
                        ? Math.min(1 / win.unit, width / shown.w, height / shown.h) : 1
                    readonly property real ox: (width - shown.w * zoom) / 2
                    readonly property real oy: (height - shown.h * zoom) / 2
                    function toImage(px, py) { return Qt.point((px - ox) / zoom + shown.x, (py - oy) / zoom + shown.y); }

                    // Checkerboard-free backdrop + shadow.
                    Rectangle {
                        x: viewport.ox - 1; y: viewport.oy - 1
                        width: viewport.shown.w * viewport.zoom + 2
                        height: viewport.shown.h * viewport.zoom + 2
                        color: "transparent"
                        border.color: Theme.border
                    }

                    // `page` is what gets exported: the crop of the picture with
                    // its marks, in image pixels, scaled down for display.
                    Item {
                        id: page
                        x: viewport.ox
                        y: viewport.oy
                        width: viewport.shown.w
                        height: viewport.shown.h
                        transformOrigin: Item.TopLeft
                        scale: viewport.zoom
                        clip: true

                        Item {
                            id: doc
                            x: -viewport.shown.x
                            y: -viewport.shown.y
                            width: img.sourceSize.width
                            height: img.sourceSize.height

                            Image {
                                id: img
                                source: win.source ? "file://" + win.source : ""
                                cache: false
                                smooth: true
                                mipmap: true
                                width: sourceSize.width
                                height: sourceSize.height
                                onStatusChanged: if (status === Image.Ready) win.reset()
                            }

                            Repeater {
                                model: win.marks
                                delegate: Mark { required property var modelData; mark: modelData; base: img }
                            }
                            // The mark being drawn.
                            Mark { mark: draw.current; base: img; visible: !!draw.current }
                        }
                    }

                    // Crop handles (image coordinates mapped to the view).
                    Item {
                        id: cropTool
                        anchors.fill: parent
                        z: 2
                        visible: win.tool === "crop"
                        property var r: ({ x: 0, y: 0, w: 0, h: 0 })
                        function begin() { r = Object.assign({}, win.crop); }
                        function apply() {
                            const c = { x: Math.round(r.x), y: Math.round(r.y), w: Math.max(1, Math.round(r.w)), h: Math.max(1, Math.round(r.h)) };
                            win.tool = "select";
                            if (c.x !== win.crop.x || c.y !== win.crop.y || c.w !== win.crop.w || c.h !== win.crop.h) { win.crop = c; win.commit(); }
                        }
                        readonly property real vx: viewport.ox + r.x * viewport.zoom
                        readonly property real vy: viewport.oy + r.y * viewport.zoom
                        readonly property real vw: r.w * viewport.zoom
                        readonly property real vh: r.h * viewport.zoom
                        readonly property color dim: Qt.rgba(0, 0, 0, 0.5)
                        Rectangle { color: cropTool.dim; x: viewport.ox; y: viewport.oy; width: viewport.shown.w * viewport.zoom; height: cropTool.vy - viewport.oy }
                        Rectangle { color: cropTool.dim; x: viewport.ox; y: cropTool.vy + cropTool.vh; width: viewport.shown.w * viewport.zoom; height: viewport.oy + viewport.shown.h * viewport.zoom - y }
                        Rectangle { color: cropTool.dim; x: viewport.ox; y: cropTool.vy; width: cropTool.vx - viewport.ox; height: cropTool.vh }
                        Rectangle { color: cropTool.dim; x: cropTool.vx + cropTool.vw; y: cropTool.vy; width: viewport.ox + viewport.shown.w * viewport.zoom - x; height: cropTool.vh }
                        Rectangle { x: cropTool.vx; y: cropTool.vy; width: cropTool.vw; height: cropTool.vh; color: "transparent"; border.color: "#ffffff"; border.width: 2 }
                        PushButton {
                            x: Math.min(cropTool.vx + cropTool.vw - width, viewport.width - width - 4)
                            y: Math.min(cropTool.vy + cropTool.vh + 8, viewport.height - height - 4)
                            primary: true
                            text: "Crop"
                            tooltip: "Apply the crop (Enter); undo brings it back"
                            onClicked: cropTool.apply()
                        }
                    }

                    // Drawing and dragging.
                    MouseArea {
                        id: draw
                        anchors.fill: parent
                        z: 1
                        hoverEnabled: true
                        property var current: null
                        property point p0: Qt.point(0, 0)
                        property var cropDrag: null
                        property var cropStart: null
                        cursorShape: win.tool === "select" ? (overPicture ? Qt.OpenHandCursor : Qt.ArrowCursor)
                                   : win.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
                        readonly property bool overPicture: {
                            const p = viewport.toImage(mouseX, mouseY);
                            return p.x >= viewport.shown.x && p.y >= viewport.shown.y
                                && p.x < viewport.shown.x + viewport.shown.w && p.y < viewport.shown.y + viewport.shown.h;
                        }
                        // Select tool: dragging starts a file drag into other apps.
                        drag.target: win.tool === "select" && overPicture ? dragProxy : null
                        drag.threshold: 6

                        function lw() { return win.penWidth * win.unit; }
                        onPressed: m => {
                            const p = viewport.toImage(m.x, m.y);
                            p0 = p;
                            const t = win.tool;
                            if (t === "select") {
                                dragProxy.x = m.x; dragProxy.y = m.y;
                                win.exportPng(() => {});
                                return;
                            }
                            if (t === "crop") {
                                const r = cropTool.r, tol = 12 / viewport.zoom;
                                const edges = { l: Math.abs(p.x - r.x) < tol, r: Math.abs(p.x - (r.x + r.w)) < tol,
                                                t: Math.abs(p.y - r.y) < tol, b: Math.abs(p.y - (r.y + r.h)) < tol };
                                const inside = p.x > r.x && p.x < r.x + r.w && p.y > r.y && p.y < r.y + r.h;
                                cropDrag = (edges.l || edges.r || edges.t || edges.b) ? edges : inside ? "move" : "new";
                                cropStart = Object.assign({}, r);
                                return;
                            }
                            if (t === "text") { textEdit.start(p); return; }
                            if (t === "number") {
                                win.addMark({ type: "number", x1: p.x, y1: p.y, n: win.nextNumber(), color: String(win.penColor), size: 16 * win.unit * (win.penWidth / 4 + 0.5) });
                                return;
                            }
                            const pts = (t === "pen" || t === "highlight") ? [p] : undefined;
                            current = { type: t, color: String(win.penColor), width: t === "highlight" ? lw() * 5 : lw(),
                                        x1: p.x, y1: p.y, x2: p.x, y2: p.y, pts: pts };
                        }
                        onPositionChanged: m => {
                            if (!pressed) return;
                            const p = viewport.toImage(m.x, m.y);
                            const W = img.sourceSize.width, H = img.sourceSize.height;
                            if (win.tool === "crop" && cropDrag) {
                                const s = cropStart, dx = p.x - p0.x, dy = p.y - p0.y;
                                let x1 = s.x, y1 = s.y, x2 = s.x + s.w, y2 = s.y + s.h;
                                if (cropDrag === "new") { x1 = p0.x; y1 = p0.y; x2 = p.x; y2 = p.y; }
                                else if (cropDrag === "move") { x1 += dx; x2 += dx; y1 += dy; y2 += dy;
                                    const fx = Math.min(0, W - x2) + Math.max(0, -x1), fy = Math.min(0, H - y2) + Math.max(0, -y1);
                                    x1 += fx; x2 += fx; y1 += fy; y2 += fy; }
                                else { if (cropDrag.l) x1 += dx; if (cropDrag.r) x2 += dx; if (cropDrag.t) y1 += dy; if (cropDrag.b) y2 += dy; }
                                const cx1 = Math.max(0, Math.min(x1, x2)), cy1 = Math.max(0, Math.min(y1, y2));
                                const cx2 = Math.min(W, Math.max(x1, x2)), cy2 = Math.min(H, Math.max(y1, y2));
                                cropTool.r = { x: cx1, y: cy1, w: cx2 - cx1, h: cy2 - cy1 };
                                return;
                            }
                            if (!current) return;
                            const c = Object.assign({}, current);
                            if (c.pts) c.pts = c.pts.concat([p]);
                            c.x2 = p.x; c.y2 = p.y;
                            current = c;
                        }
                        onReleased: {
                            cropDrag = null;
                            if (!current) return;
                            const c = current;
                            current = null;
                            const big = Math.abs(c.x2 - c.x1) > 3 || Math.abs(c.y2 - c.y1) > 3 || (c.pts && c.pts.length > 2);
                            if (big) win.addMark(c);
                        }
                    }
                    // Carries the file while it's dragged out of the window.
                    Item {
                        id: dragProxy
                        width: 1; height: 1
                        Drag.active: draw.drag.active
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.CopyAction
                        Drag.mimeData: ({ "text/uri-list": "file://" + encodeURI(win.exported || win.source) + "\r\n" })
                        Drag.imageSource: win.exported || win.source ? "file://" + (win.exported || win.source) : ""
                        Drag.hotSpot: Qt.point(0, 0)
                    }

                    // Typing a text mark.
                    Rectangle {
                        id: textEdit
                        z: 3
                        visible: false
                        property point at: Qt.point(0, 0)
                        readonly property real px: 24 * win.unit * (win.penWidth / 4 + 0.5)
                        x: viewport.ox + (at.x - viewport.shown.x) * viewport.zoom - 4
                        y: viewport.oy + (at.y - viewport.shown.y) * viewport.zoom - 4
                        width: Math.max(80, input.contentWidth + 12)
                        height: input.contentHeight + 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Theme.accent
                        radius: 3
                        function start(p) { finish(); at = p; input.text = ""; visible = true; input.forceActiveFocus(); }
                        function finish() {
                            if (!visible) return;
                            visible = false;
                            const t = input.text.trim();
                            if (t) win.addMark({ type: "text", x1: at.x, y1: at.y, text: input.text, color: String(win.penColor), size: px });
                        }
                        TextEdit {
                            id: input
                            x: 4; y: 4
                            renderType: Text.NativeRendering
                            color: win.penColor
                            font.pixelSize: Math.max(8, textEdit.px * viewport.zoom)
                            font.weight: Font.DemiBold
                            Keys.onPressed: e => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { textEdit.finish(); e.accepted = true; }
                                else if (e.key === Qt.Key_Escape) { textEdit.visible = false; e.accepted = true; }
                            }
                        }
                    }
                }
            }
        }
    }

    // One annotation, drawn in image pixels.
    component Mark: Item {
        id: mk
        property var mark: null
        property Item base: null
        readonly property string type: mark ? mark.type : ""
        readonly property real x1: mark && mark.x1 !== undefined ? mark.x1 : 0
        readonly property real y1: mark && mark.y1 !== undefined ? mark.y1 : 0
        readonly property real x2: mark && mark.x2 !== undefined ? mark.x2 : 0
        readonly property real y2: mark && mark.y2 !== undefined ? mark.y2 : 0
        readonly property real l: Math.min(x1, x2)
        readonly property real t: Math.min(y1, y2)
        readonly property real w: Math.abs(x2 - x1)
        readonly property real h: Math.abs(y2 - y1)
        readonly property color col: mark && mark.color ? mark.color : "#ff3b30"
        readonly property real lw: mark && mark.width ? mark.width : 4

        Shape {
            visible: ["arrow", "rect", "ellipse", "pen", "highlight"].includes(mk.type)
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: mk.type === "highlight" ? Qt.rgba(mk.col.r, mk.col.g, mk.col.b, 0.38) : mk.col
                strokeWidth: mk.lw
                fillColor: "transparent"
                capStyle: mk.type === "highlight" ? ShapePath.FlatCap : ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    path: {
                        const m = mk.mark;
                        if (!m) return [];
                        if (m.pts) return m.pts.map(p => Qt.point(p.x, p.y));
                        if (mk.type === "rect")
                            return [Qt.point(mk.l, mk.t), Qt.point(mk.l + mk.w, mk.t), Qt.point(mk.l + mk.w, mk.t + mk.h), Qt.point(mk.l, mk.t + mk.h), Qt.point(mk.l, mk.t)];
                        if (mk.type === "ellipse") {
                            const pts = [], cx = mk.l + mk.w / 2, cy = mk.t + mk.h / 2;
                            for (let i = 0; i <= 96; i++) { const a = i / 96 * 2 * Math.PI; pts.push(Qt.point(cx + Math.cos(a) * mk.w / 2, cy + Math.sin(a) * mk.h / 2)); }
                            return pts;
                        }
                        if (mk.type === "arrow") {
                            // Shaft stops short of the tip so the head stays sharp.
                            const dx = mk.x2 - mk.x1, dy = mk.y2 - mk.y1, len = Math.hypot(dx, dy) || 1;
                            const head = Math.min(len * 0.6, mk.lw * 4.5);
                            return [Qt.point(mk.x1, mk.y1), Qt.point(mk.x2 - dx / len * head * 0.6, mk.y2 - dy / len * head * 0.6)];
                        }
                        return [];
                    }
                }
            }
            // Arrow head.
            ShapePath {
                strokeColor: mk.type === "arrow" ? mk.col : "transparent"
                strokeWidth: mk.lw / 2
                joinStyle: ShapePath.MiterJoin
                fillColor: mk.type === "arrow" ? mk.col : "transparent"
                PathPolyline {
                    path: {
                        if (mk.type !== "arrow") return [];
                        const dx = mk.x2 - mk.x1, dy = mk.y2 - mk.y1, len = Math.hypot(dx, dy) || 1;
                        const ux = dx / len, uy = dy / len, head = Math.min(len * 0.6, mk.lw * 4.5), half = head * 0.55;
                        const bx = mk.x2 - ux * head, by = mk.y2 - uy * head;
                        return [Qt.point(mk.x2, mk.y2), Qt.point(bx - uy * half, by + ux * half), Qt.point(bx + uy * half, by - ux * half), Qt.point(mk.x2, mk.y2)];
                    }
                }
            }
        }

        // Text.
        Label {
            visible: mk.type === "text"
            x: mk.x1; y: mk.y1
            text: mk.mark && mk.mark.text ? mk.mark.text : ""
            color: mk.col
            font.pixelSize: mk.mark && mk.mark.size ? mk.mark.size : 24
            font.weight: Font.DemiBold
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.35)
        }

        // Numbered stamp.
        Rectangle {
            visible: mk.type === "number"
            readonly property real d: (mk.mark && mk.mark.size ? mk.mark.size : 24) * 1.6
            x: mk.x1 - d / 2; y: mk.y1 - d / 2
            width: d; height: d; radius: d / 2
            color: mk.col
            border.color: "#ffffff"
            border.width: Math.max(1, d / 14)
            Label {
                anchors.centerIn: parent
                text: mk.mark && mk.mark.n ? mk.mark.n : ""
                color: Qt.colorEqual(mk.col, "#ffffff") || Qt.colorEqual(mk.col, "#ffcc00") ? "#000000" : "#ffffff"
                font.pixelSize: parent.d * 0.55
                font.weight: Font.Bold
            }
        }

        // Pixelate: the picture under it, sampled down and blown up.
        ShaderEffectSource {
            visible: mk.type === "pixelate" && mk.w > 0 && mk.h > 0
            x: mk.l; y: mk.t; width: mk.w; height: mk.h
            sourceItem: visible ? mk.base : null
            sourceRect: Qt.rect(mk.l, mk.t, mk.w, mk.h)
            textureSize: Qt.size(Math.max(1, Math.round(mk.w / 14)), Math.max(1, Math.round(mk.h / 14)))
            smooth: false
            live: false
        }
        // Blur.
        Item {
            visible: mk.type === "blur" && mk.w > 0 && mk.h > 0
            x: mk.l; y: mk.t; width: mk.w; height: mk.h
            clip: true
            ShaderEffectSource {
                id: blurSrc
                // Sample a margin around it so the edges blur too.
                readonly property real m: 24
                x: -m; y: -m
                width: mk.w + 2 * m; height: mk.h + 2 * m
                sourceItem: parent.visible ? mk.base : null
                sourceRect: Qt.rect(mk.l - m, mk.t - m, mk.w + 2 * m, mk.h + 2 * m)
                textureSize: Qt.size(Math.max(1, Math.round(width / 4)), Math.max(1, Math.round(height / 4)))
                live: false
                visible: false
            }
            MultiEffect {
                anchors.fill: blurSrc
                source: blurSrc
                blurEnabled: true
                blur: 1
                blurMax: 48
                autoPaddingEnabled: false
            }
        }
    }
}
