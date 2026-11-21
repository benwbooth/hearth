import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Spotlight (services/Spotlight.qml, README "Spotlight"): a liquid-glass
// search field centred near the top of the focused screen, results grouped
// below it (Top Hit, Applications, System Settings, Actions, Documents,
// Folders, Images, Other, the calculator, web suggestions, Ask hearth) with
// a preview of the selected one.
//
// Keys: ↑ ↓ choose, ⌘↑ ⌘↓ (Super or Ctrl) jump between groups, Return opens,
// ⌘Return shows the file in the file manager, ⌘C copies a file's path or a
// result, Esc clears the field, then closes.
//
// Motion after macOS 26's Spotlight: the field springs open from 92% with
// a short overshoot while it fades in (340 ms), the results pane slides
// open under it (220 ms ease-out) and everything fades out quickly (160 ms)
// when it closes.
Scope {
    id: root

    PanelWindow {
        id: win
        // Mapped while open and while the close animation runs.
        visible: Spotlight.open || stage.opacity > 0.01
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-spotlight"
        WlrLayershell.keyboardFocus: Spotlight.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        readonly property real pt: Theme.pt
        // Denser than menus: Spotlight floats over anything, text must read.
        readonly property color tint: Theme.glassColor(Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 1) : Qt.rgba(0.97, 0.97, 0.975, 1), 0.8)
        readonly property int fieldW: Math.round(680 * pt)
        readonly property int fieldH: Math.round(48 * pt)
        readonly property int rowH: Math.round(28 * pt)
        readonly property int headerH: Math.round(24 * pt)

        // --- results ---
        property int sel: 0
        readonly property string q: Spotlight.query
        readonly property var c: Spotlight.cfg.categories
        readonly property var apps: c.apps ? Spotlight.appMatches(q) : []
        readonly property var settingsHits: c.settings ? Spotlight.paneMatches(q) : []
        readonly property var actionHits: c.actions ? Spotlight.actionMatches(q) : []
        readonly property var fileHits: {
            const fs = Spotlight.files.slice().sort((a, b) => b.score - a.score);
            return fs.map(f => ({ kind: "file", file: f, title: f.name, key: "file:" + f.path,
                                  subtitle: win.prettyDir(f.dir), icon: win.fileIcon(f), score: f.score }));
        }
        readonly property var calcHits: c.calculator ? Spotlight.calc.map(x => ({ kind: "calc", title: x.result, result: x.result, expr: x.expr,
                                                                     subtitle: x.kind === "conversion" ? "Conversion" : "Calculator",
                                                                     icon: x.kind === "conversion" ? "accessories-calculator" : "accessories-calculator" })) : []
        readonly property var webHits: Spotlight.cfg.web ? Spotlight.web.map(w => ({ kind: "web", title: w.text, subtitle: "Search the web", icon: "internet-web-browser" })) : []

        // The best match across groups, shown first (like macOS's Top Hit).
        readonly property var topHit: {
            if (calcHits.length) return calcHits[0];
            const cands = [];
            if (apps.length) cands.push({ r: apps[0], s: apps[0].score });
            if (settingsHits.length) cands.push({ r: settingsHits[0], s: settingsHits[0].score - 8 });
            if (fileHits.length) cands.push({ r: fileHits[0], s: Math.min(110, fileHits[0].score * 0.55) });
            if (!cands.length) return null;
            return cands.reduce((a, b) => b.s > a.s ? b : a).r;
        }
        function without(list) { return topHit ? list.filter(r => r !== topHit) : list; }
        function files(kinds, max) {
            return without(fileHits).filter(r => kinds.indexOf(r.file.kind) >= 0).slice(0, max);
        }
        readonly property var groups: {
            if (!q.trim()) return [];
            const g = [];
            const add = (title, items) => { if (items.length) g.push({ title: title, items: items }); };
            if (topHit) add("Top Hit", [topHit]);
            add("Applications", without(apps).slice(0, 5));
            add("System Settings", without(settingsHits));
            const filterOnly = /^(\s*\w+:\S+)+\s*$/.test(q);
            if (!filterOnly) add("Actions", actionHits);
            if (c.documents) add("Documents", files(["document", "pdf"], 6));
            if (c.folders) add("Folders", files(["folder"], 4));
            if (c.images) add("Images", files(["image"], 6));
            if (c.other) add("Other", files(["music", "video", "other"], 4));
            add("Web Suggestions", webHits);
            if (Spotlight.cfg.ask && q.trim().length > 2 && !filterOnly)
                add("Ask", [{ kind: "ask", query: q.trim(), title: "Ask hearth “" + q.trim() + "”", subtitle: "Assistant (" + win.assistantName() + ")", icon: "audio-input-microphone" }]);
            return g;
        }
        readonly property var flat: {
            const out = [];
            for (const g of groups) for (const r of g.items) out.push(r);
            return out;
        }
        readonly property var current: flat.length ? flat[Math.min(sel, flat.length - 1)] : null
        onFlatChanged: if (sel >= flat.length) sel = Math.max(0, flat.length - 1)
        onCurrentChanged: previewTimer.restart()
        Timer {
            id: previewTimer
            interval: 90
            onTriggered: if (win.current && win.current.kind === "file") Spotlight.requestPreview(win.current.file)
        }

        function assistantName() {
            const a = Ai.cfg.assistant;
            return a.model || a.provider;
        }
        function prettyDir(d) {
            const home = Quickshell.env("HOME");
            return d && home && d.startsWith(home) ? "~" + d.slice(home.length) : d;
        }
        function fileIcon(f) {
            if (f.kind === "folder") return "folder";
            return (f.mime || "text/plain").replace("/", "-");
        }
        function groupStart(i) {
            let n = 0;
            for (const g of groups) { if (i < n + g.items.length) return n; n += g.items.length; }
            return 0;
        }
        function jumpGroup(dir) {
            let n = 0;
            const starts = groups.map(g => { const s = n; n += g.items.length; return s; });
            const cur = starts.filter(s => s <= sel).length - 1;
            const next = Math.max(0, Math.min(starts.length - 1, cur + dir));
            if (starts.length) sel = starts[next];
        }
        function copy(r) {
            if (!r) return;
            const t = r.kind === "file" ? r.file.path : r.kind === "calc" ? r.result : r.title;
            Quickshell.execDetached(["wl-copy", t]);
        }

        Connections {
            target: Spotlight
            function onOpenChanged() {
                if (Spotlight.open) {
                    field.text = Spotlight.pendingText;
                    Spotlight.pendingText = "";
                    field.selectAll();
                    field.forceActiveFocus();
                    Spotlight.search(field.text);
                    win.sel = 0;
                    stage.scale = 0.92;
                    openAnim.restart();
                } else {
                    closeAnim.restart();
                }
            }
            function onToggleRequested() {
                if (Spotlight.pendingText) { field.text = Spotlight.pendingText; Spotlight.pendingText = ""; Spotlight.search(field.text); }
            }
        }

        // A click outside the field and results closes Spotlight.
        MouseArea {
            anchors.fill: parent
            onPressed: Spotlight.open = false
        }

        Item {
            id: stage
            width: win.fieldW
            height: col.height
            x: Math.round((win.width - width) / 2)
            y: Math.round(win.height * 0.22)
            opacity: 0
            transformOrigin: Item.Top
            transform: Translate { x: 0.001; y: 0.001 }

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: stage; property: "scale"; from: 0.92; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
            ParallelAnimation {
                id: closeAnim
                NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 160; easing.type: Easing.InCubic }
                NumberAnimation { target: stage; property: "scale"; to: 0.97; duration: 160; easing.type: Easing.InCubic }
            }

            // Swallow clicks inside so they don't close it.
            MouseArea { anchors.fill: parent; onPressed: mouse => mouse.accepted = true }

            Column {
                id: col
                width: parent.width
                spacing: Math.round(10 * win.pt)

                // --- the field ---
                GlassFrame {
                    id: fieldGlass
                    tint: win.tint
                    width: parent.width
                    height: win.fieldH
                    radius: height / 2

                    Icon {
                        id: mag
                        x: Math.round(16 * win.pt)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Math.round(22 * win.pt)
                        name: "search"
                        fallback: "edit-find"
                    }
                    TextInput {
                        id: field
                        anchors.left: mag.right
                        anchors.leftMargin: Math.round(10 * win.pt)
                        anchors.right: hitIcon.left
                        anchors.rightMargin: Math.round(10 * win.pt)
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        color: Theme.fg
                        selectionColor: Theme.accentDim
                        selectedTextColor: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize + 8
                        font.weight: Font.Normal
                        clip: true
                        onTextEdited: { Spotlight.search(text); win.sel = 0; }

                        Label {
                            anchors.fill: parent
                            visible: !field.text
                            text: "Search"
                            color: Theme.fgSecondary
                            font: field.font
                        }

                        Keys.onPressed: e => {
                            const cmd = (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0;
                            if (e.key === Qt.Key_Down) { if (cmd) win.jumpGroup(1); else win.sel = Math.min(win.flat.length - 1, win.sel + 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Up) { if (cmd) win.jumpGroup(-1); else win.sel = Math.max(0, win.sel - 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Tab) { win.jumpGroup(1); e.accepted = true; }
                            else if (e.key === Qt.Key_Backtab) { win.jumpGroup(-1); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                if (cmd) { if (!Spotlight.reveal(win.current)) Spotlight.activate(win.current); }
                                else Spotlight.activate(win.current);
                                e.accepted = true;
                            }
                            else if (e.key === Qt.Key_Escape) {
                                if (field.text) { field.text = ""; Spotlight.search(""); } else Spotlight.open = false;
                                e.accepted = true;
                            }
                            else if (cmd && e.key === Qt.Key_C && !field.selectedText) { win.copy(win.current); e.accepted = true; }
                        }
                    }
                    // The top hit's icon at the end of the field, like macOS.
                    Icon {
                        id: hitIcon
                        anchors.right: parent.right
                        anchors.rightMargin: Math.round(14 * win.pt)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Math.round(26 * win.pt)
                        visible: !!win.topHit && win.topHit.kind !== "calc"
                        opacity: visible ? 1 : 0
                        name: win.topHit ? win.topHit.icon : ""
                        fallback: "text-x-generic"
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                // --- results and preview ---
                GlassFrame {
                    id: pane
                    tint: win.tint
                    width: parent.width
                    // At least tall enough for the preview, at most 440 pt.
                    readonly property real want: win.groups.length
                        ? Math.max(Math.round(300 * win.pt), Math.min(Math.round(440 * win.pt), list.contentHeight + 2 * Math.round(6 * win.pt))) : 0
                    height: want
                    visible: height > 1
                    radius: Math.round(22 * win.pt)
                    opacity: win.groups.length ? 1 : 0
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    clip: true

                    Flickable {
                        id: list
                        x: Math.round(6 * win.pt)
                        y: Math.round(6 * win.pt)
                        width: Math.round(parent.width * 0.5) - x
                        height: parent.height - 2 * y
                        contentHeight: rows.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: rows
                            width: list.width
                            Repeater {
                                model: win.groups
                                Column {
                                    id: grp
                                    required property var modelData
                                    required property int index
                                    width: rows.width
                                    readonly property int base: { let n = 0; for (let i = 0; i < index; i++) n += win.groups[i].items.length; return n; }
                                    Label {
                                        x: Math.round(10 * win.pt)
                                        height: win.headerH
                                        text: grp.modelData.title
                                        color: Theme.fgSecondary
                                        font.pointSize: Theme.smallFontSize
                                        font.weight: Font.DemiBold
                                    }
                                    Repeater {
                                        model: grp.modelData.items
                                        MouseArea {
                                            id: row
                                            required property var modelData
                                            required property int index
                                            readonly property int flatIndex: grp.base + index
                                            readonly property bool on: flatIndex === win.sel
                                            width: rows.width
                                            height: win.rowH
                                            hoverEnabled: true
                                            onPositionChanged: win.sel = flatIndex
                                            onClicked: Spotlight.activate(modelData)
                                            onOnChanged: if (on) {
                                                const y = row.mapToItem(rows, 0, 0).y;
                                                if (y < list.contentY) list.contentY = Math.max(0, y - win.headerH);
                                                else if (y + height > list.contentY + list.height) list.contentY = y + height - list.height;
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Math.round(8 * win.pt)
                                                color: row.on ? Theme.accent : "transparent"
                                            }
                                            Item {
                                                id: rowIcon
                                                x: Math.round(8 * win.pt)
                                                width: Math.round(20 * win.pt)
                                                height: width
                                                anchors.verticalCenter: parent.verticalCenter
                                                Icon {
                                                    anchors.fill: parent
                                                    implicitSize: parent.width
                                                    name: row.modelData.icon
                                                    fallback: row.modelData.kind === "file" ? "text-x-generic" : "application-x-executable"
                                                    visible: !(row.modelData.kind === "file" && row.modelData.file.kind === "image")
                                                }
                                                Image {
                                                    anchors.fill: parent
                                                    visible: row.modelData.kind === "file" && row.modelData.file.kind === "image"
                                                    source: visible ? "file://" + row.modelData.file.path : ""
                                                    sourceSize: Qt.size(64, 64)
                                                    asynchronous: true
                                                    fillMode: Image.PreserveAspectCrop
                                                }
                                            }
                                            Label {
                                                id: rowTitle
                                                anchors.left: rowIcon.right
                                                anchors.leftMargin: Math.round(8 * win.pt)
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.min(implicitWidth, row.width - x - Math.round(12 * win.pt) - Math.min(rowSub.implicitWidth, row.width * 0.35))
                                                text: row.modelData.title
                                                color: row.on ? Theme.accentText : Theme.fg
                                            }
                                            Label {
                                                id: rowSub
                                                anchors.left: rowTitle.right
                                                anchors.leftMargin: Math.round(6 * win.pt)
                                                anchors.right: parent.right
                                                anchors.rightMargin: Math.round(10 * win.pt)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: row.modelData.kind === "file" ? "— " + row.modelData.subtitle : row.modelData.subtitle ? "— " + row.modelData.subtitle : ""
                                                elide: Text.ElideMiddle
                                                color: row.on ? Qt.rgba(1, 1, 1, 0.75) : Theme.fgSecondary
                                            }
                                        }
                                    }
                                }
                            }
                            Label {
                                visible: !Spotlight.filesDone
                                x: Math.round(10 * win.pt)
                                height: win.rowH
                                text: "Searching files…"
                                color: Theme.fgSecondary
                            }
                            Label {
                                visible: Spotlight.filesDone && Spotlight.filesError === "noindex"
                                x: Math.round(10 * win.pt)
                                width: rows.width - 2 * x
                                height: win.rowH
                                text: "Files aren't indexed yet (Settings > Search)."
                                color: Theme.fgSecondary
                            }
                        }
                    }

                    Rectangle {
                        x: list.x + list.width + Math.round(6 * win.pt)
                        y: Math.round(14 * win.pt)
                        width: 1
                        height: parent.height - 2 * y
                        color: Theme.menuSeparator
                    }

                    Label {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.round(10 * win.pt)
                        x: preview.x
                        width: preview.width
                        horizontalAlignment: Text.AlignHCenter
                        text: win.current && win.current.kind === "file" ? "↩ Open   ⌘↩ Show in Folder   ⌘C Copy Path"
                            : win.current && win.current.kind === "calc" ? "↩ Copy Result" : "↩ Open   ↑↓ Choose   Esc Close"
                        color: Theme.fgSecondary
                        font.pointSize: Theme.smallFontSize
                    }

                    // --- preview ---
                    Item {
                        id: preview
                        x: list.x + list.width + Math.round(14 * win.pt)
                        y: Math.round(14 * win.pt)
                        width: parent.width - x - Math.round(14 * win.pt)
                        height: parent.height - 2 * y - Math.round(24 * win.pt)
                        clip: true
                        readonly property var r: win.current
                        readonly property var f: r && r.kind === "file" ? r.file : null
                        readonly property var pv: f && Spotlight.preview.path === f.path ? Spotlight.preview : ({})

                        Column {
                            width: parent.width
                            spacing: Math.round(8 * win.pt)
                            visible: !!preview.r

                            Item {
                                width: parent.width
                                height: Math.min(Math.round(170 * win.pt), preview.height * 0.5)
                                Image {
                                    id: bigImg
                                    anchors.fill: parent
                                    visible: status === Image.Ready
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize: Qt.size(640, 640)
                                    source: !preview.f ? ""
                                          : preview.f.kind === "image" ? "file://" + preview.f.path
                                          : preview.pv.thumb ? "file://" + preview.pv.thumb : ""
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !bigImg.visible && preview.r && preview.r.kind !== "calc"
                                    implicitSize: Math.round(96 * win.pt)
                                    name: preview.r ? preview.r.icon : ""
                                    fallback: "text-x-generic"
                                }
                                Label {
                                    anchors.fill: parent
                                    visible: preview.r && preview.r.kind === "calc"
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideNone
                                    font.pointSize: Theme.fontSize + 14
                                    font.weight: Font.Light
                                    text: preview.r && preview.r.kind === "calc" ? preview.r.result : ""
                                    fontSizeMode: Text.Fit
                                    minimumPointSize: 10
                                }
                            }
                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: preview.r ? (preview.r.kind === "calc" ? preview.r.expr : preview.r.title) : ""
                                font.weight: Font.DemiBold
                                font.pointSize: Theme.fontSize + 1
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                            }
                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.fgSecondary
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                text: {
                                    const r = preview.r;
                                    if (!r) return "";
                                    if (r.kind === "app") return (r.entry.comment || r.entry.genericName || "Application");
                                    if (r.kind === "settings") return "Opens " + r.title + " in hearth Settings";
                                    if (r.kind === "action") return r.item.keys ? "Shortcut: " + r.item.keys : "Runs this action";
                                    if (r.kind === "calc") return "Return copies the result";
                                    if (r.kind === "web") return "Opens a web search in your browser";
                                    if (r.kind === "ask") return "The assistant answers in the voice panel. Change the model in Settings > AI.";
                                    return "";
                                }
                                visible: text !== ""
                            }
                            // File details, Finder-style.
                            Grid {
                                visible: !!preview.f
                                columns: 2
                                columnSpacing: Math.round(8 * win.pt)
                                rowSpacing: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                Repeater {
                                    model: preview.f ? [
                                        ["Kind", preview.f.kind === "folder" ? "Folder" : (preview.f.mime || "")],
                                        ["Size", preview.f.kind === "folder" ? (preview.pv.items !== undefined ? preview.pv.items + (preview.pv.items === 1 ? " item" : " items") : "") : win.size(preview.f.size)],
                                        ["Modified", preview.f.mtime ? new Date(preview.f.mtime * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : ""],
                                        ["Where", win.prettyDir(preview.f.dir)]
                                    ].filter(x => x[1]).reduce((a, x) => a.concat(x), []) : []
                                    Label {
                                        required property var modelData
                                        required property int index
                                        text: modelData
                                        color: index % 2 === 0 ? Theme.fgSecondary : Theme.fg
                                        horizontalAlignment: index % 2 === 0 ? Text.AlignRight : Text.AlignLeft
                                        font.pointSize: Theme.smallFontSize
                                        width: index % 2 === 0 ? Math.round(60 * win.pt) : preview.width - Math.round(76 * win.pt)
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: preview.f ? (preview.f.snippet || preview.pv.text || "") : ""
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 8
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

            }
        }

        function size(b) {
            if (!b) return "";
            const u = ["bytes", "KB", "MB", "GB", "TB"];
            let i = 0;
            while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
            return (i === 0 ? b : b.toFixed(b >= 100 ? 0 : 1)) + " " + u[i];
        }
    }
}
