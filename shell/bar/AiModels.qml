import QtQuick
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// The AI menu's model manager (services/Ai.qml, helpers/hearth-ai):
//   Loaded     every model in graphics memory, servers' and other apps',
//              with its VRAM, when it was last used and when it unloads by
//              itself; Unload / Stop, and a pin to keep it loaded.
//   Installed  every model on this computer, by category, with Load and
//              Delete (files go to the trash; a server's own models are
//              deleted by it).
//   Get More   models to install, one section per source hearth-ai offers:
//              Magnitude's picks for this computer, hearth's picks, LM
//              Studio's catalog, a running LocalAI's gallery, Hugging Face.
// Category chips filter all three.
ColumnLayout {
    id: root
    spacing: 8
    property string tab: Ai.loaded.length ? "loaded" : "installed"
    property string category: ""
    property string confirmKey: ""      // "Delete?" asked for this key
    property int listHeight: 330

    function dur(s) {
        s = Math.max(0, Math.round(s));
        if (s < 60) return s + " s";
        if (s < 3600) return Math.round(s / 60) + " min";
        return (s / 3600).toFixed(s < 36000 ? 1 : 0) + " h";
    }
    function gb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.round(b / 1048576) + " MB"; }
    function ctxText(n) { return n >= 1048576 ? Math.round(n / 1048576) + "M" : n >= 1024 ? Math.round(n / 1024) + "K" : n; }

    readonly property var list: tab === "loaded" ? Ai.loaded : tab === "installed" ? Ai.installed : []
    readonly property var counts: {
        const c = {};
        for (const m of list) c[m.category] = (c[m.category] || 0) + 1;
        return c;
    }
    readonly property var chips: {
        const out = [{ id: "", label: "All" }];
        for (const c of Ai.categories)
            if (tab === "more" || counts[c.id]) out.push({ id: c.id, label: c.label + (tab === "more" ? "" : " " + counts[c.id]) });
        return out;
    }
    readonly property var shown: category ? list.filter(m => m.category === category) : list
    onTabChanged: { confirmKey = ""; if (tab === "more") Ai.browse(category, search.text); }
    onCategoryChanged: if (tab === "more") Ai.browse(category, search.text)
    Connections {
        target: Ai
        function onTabRequested(t, c) { root.category = c || ""; root.tab = t || "loaded"; }
    }

    Segmented {
        Layout.fillWidth: true
        options: [
            { value: "loaded", label: "Loaded" + (Ai.loaded.length ? " " + Ai.loaded.length : "") },
            { value: "installed", label: "Installed " + Ai.installed.length },
            { value: "more", label: "Get More" }
        ]
        value: root.tab
        onPicked: v => root.tab = v
    }

    // Category chips.
    Flow {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: root.chips
            MouseArea {
                id: chip
                required property var modelData
                readonly property bool on: root.category === modelData.id
                width: cl.implicitWidth + 14
                height: cl.implicitHeight + 6
                hoverEnabled: true
                onClicked: root.category = modelData.id
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: chip.on ? Theme.accent : chip.containsMouse ? Theme.pressed : Theme.hover
                }
                Label {
                    id: cl
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    color: chip.on ? Theme.accentText : Theme.fg
                    font.pointSize: Theme.smallFontSize
                }
            }
        }
    }

    // Search (Get More).
    TextBox {
        id: search
        visible: root.tab === "more"
        Layout.fillWidth: true
        placeholder: "Search Hugging Face" + (root.category ? " for " + (Ai.categories.find(c => c.id === root.category) || { label: "" }).label.toLowerCase() + " models" : "") + "…"
        onAccepted: Ai.browse(root.category, text)
    }

    Flickable {
        id: scroll
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(body.implicitHeight, root.listHeight)
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: body
            width: scroll.width
            spacing: 2

            Label {
                visible: root.tab !== "more" && root.shown.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                text: root.tab === "loaded"
                      ? "No models in graphics memory. They load when something uses them and unload after "
                        + (Ai.cfg.idleMinutes || 5) + " minutes unused."
                      : Ai.ready ? "No models here." : "Looking…"
                color: Theme.fgSecondary
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            // --- loaded ---
            Repeater {
                model: root.tab === "loaded" ? root.shown : []
                ModelRow {
                    id: lr
                    required property var modelData
                    m: modelData
                    title: modelData.name
                    sub: {
                        const m = modelData;
                        const parts = [m.kind === "process" ? m.providerLabel + " (app)" : m.providerLabel];
                        if (m.vram) parts.push(root.gb(m.vram));
                        if (m.gtt >= 268435456) parts.push(root.gb(m.gtt) + " in RAM");
                        if (m.partial) parts.push("partly on the CPU");
                        if (m.context) parts.push(root.ctxText(m.context) + " context");
                        return parts.join(" · ");
                    }
                    sub2: {
                        const m = modelData;
                        const busy = Ai.busyKeys[m.key];
                        if (busy === "unloading" || m.unloading) return "Unloading…";
                        let s = m.active ? "In use now" + (m.gpuPercent ? ` (${m.gpuPercent}% GPU)` : "")
                                         : "Last used " + root.dur(m.idleSec) + " ago";
                        if (m.pinned) s += " · kept loaded";
                        else if (m.unloadIn >= 0 && !m.active) s += " · unloads in " + root.dur(m.unloadIn);
                        else if (m.kind === "process") s += " · managed by the app";
                        s += " · loads in ~" + root.dur(m.loadSec) + (m.loadMeasured ? "" : " (est.)");
                        return s;
                    }
                    PinButton {
                        visible: lr.modelData.auto
                        on: lr.modelData.pinned
                        onToggled: Ai.pin(lr.modelData.key, !lr.modelData.pinned)
                    }
                    PushButton {
                        visible: lr.modelData.canUnload
                        text: lr.modelData.unloadLabel
                        enabled: !Ai.busyKeys[lr.modelData.key] && !lr.modelData.unloading
                        tooltip: lr.modelData.kind === "process" ? "Stops " + lr.modelData.unit + " to free its memory"
                                 : lr.modelData.unloadLabel === "Stop" ? "Stops the server to free its memory; it starts again when something asks it"
                                 : "Frees its memory now; it loads again next time it's used"
                        onClicked: Ai.unloadKey(lr.modelData.key)
                    }
                }
            }
            // Other apps using graphics memory (Loaded tab).
            Label {
                visible: root.tab === "loaded" && !root.category && Ai.apps.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: "Also using graphics memory: " + Ai.apps.slice(0, 6).map(a => `${a.name} ${a.vramText}`).join(", ")
                color: Theme.fgSecondary
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Repeater {
                model: root.tab === "loaded" ? Ai.evicted.slice(0, 3) : []
                Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: (modelData.dryRun ? "Would unload " : "Unloaded ") + modelData.name + " (" + modelData.reason + ")"
                        + (modelData.vramText ? ", freed " + modelData.vramText : "")
                    color: Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                    elide: Text.ElideRight
                }
            }

            // --- installed ---
            Repeater {
                model: root.tab === "installed" ? root.shown : []
                ModelRow {
                    id: ir
                    required property var modelData
                    m: modelData
                    title: modelData.name
                    readonly property var runner: modelData.runners && modelData.runners.length ? modelData.runners[pick.value || 0] : null
                    sub: {
                        const m = modelData;
                        const parts = [m.categoryLabel, m.source];
                        if (m.sizeText) parts.push(m.sizeText);
                        if (m.quant) parts.push(m.quant);
                        if (m.context) parts.push(root.ctxText(m.context) + " context");
                        return parts.join(" · ");
                    }
                    sub2: {
                        const m = modelData;
                        if (Ai.busyKeys[m.key] === "loading") return "Loading… (making room first if needed)";
                        if (Ai.busyKeys[m.key] === "removing") return "Deleting…";
                        if (!m.runners.length) return m.family ? m.family : "";
                        return "Runs in " + m.runners.map(r => r.label + (r.fits === "DoesNotFit" ? " (doesn't fit)" : "")).join(", ");
                    }
                    Label {
                        visible: ir.modelData.loaded
                        text: "Loaded"
                        color: Theme.good
                        font.pointSize: Theme.smallFontSize
                    }
                    // Its context window, for a model hearth runs itself.
                    Dropdown {
                        visible: !!ir.runner && ir.runner.provider === "gguf"
                        // "Default" follows Settings > AI; Auto fits graphics memory.
                        // Takes effect the next time it loads.
                        implicitWidth: 96
                        options: [{ value: -1, label: "Default ctx" }, { value: 0, label: "Auto ctx" }]
                            .concat(Ai.contextOptions.filter(n => n).map(n => ({ value: n, label: Ai.contextLabel(n) + " ctx" })))
                        value: Ai.contextFor(ir.modelData.path)
                        onPicked: v => Ai.setContextFor(ir.modelData.path, v)
                    }
                    Dropdown {
                        id: pick
                        visible: ir.modelData.runners.length > 1 && !ir.modelData.loaded
                        implicitWidth: 110
                        options: ir.modelData.runners.map((r, i) => ({ value: i, label: r.label }))
                        value: 0
                        onPicked: v => value = v
                    }
                    PushButton {
                        visible: ir.modelData.loadable && !ir.modelData.loaded
                        text: ir.runner && ir.runner.provider.startsWith("service:") ? "Start" : "Load"
                        enabled: !Ai.busyKeys[ir.modelData.key]
                        tooltip: "Load it into graphics memory now (idle models are unloaded first if there isn't room)"
                        onClicked: Ai.loadKey(ir.modelData.key, ir.runner ? ir.runner.provider : "")
                    }
                    PushButton {
                        visible: ir.modelData.deletable && root.confirmKey !== ir.modelData.key
                        text: "…"
                        implicitWidth: 28
                        tooltip: "Delete this model"
                        onClicked: root.confirmKey = ir.modelData.key
                    }
                    PushButton {
                        visible: root.confirmKey === ir.modelData.key
                        destructive: true
                        text: "Delete " + ir.modelData.sizeText
                        tooltip: ir.modelData.deleteVia ? "Deletes it from " + ir.modelData.source
                                 : "Moves its files to the trash (restore them from there; empty the trash to get the space back)"
                        onClicked: { root.confirmKey = ""; Ai.removeKey(ir.modelData.key); }
                    }
                }
            }

            // --- get more ---
            Label {
                visible: root.tab === "more" && Ai.catalog.loading
                text: "Loading…"
                color: Theme.fgSecondary
            }
            Repeater {
                // One section per source hearth-ai sends (Magnitude, hearth's
                // picks, LM Studio, each LocalAI's gallery, Hugging Face...).
                model: root.tab === "more" && !Ai.catalog.loading ? (Ai.catalog.sections || []) : []
                ColumnLayout {
                    id: sec
                    required property var modelData
                    Layout.fillWidth: true
                    visible: modelData.items.length > 0
                    spacing: 2
                    Label {
                        text: sec.modelData.title
                        font.weight: Font.DemiBold
                        font.pointSize: Theme.smallFontSize
                        color: Theme.fgSecondary
                        Layout.topMargin: 6
                    }
                    Repeater {
                        model: sec.modelData.items
                        ModelRow {
                            id: cr
                            required property var modelData
                            m: modelData
                            readonly property string pullKey: modelData.provider + "/" + modelData.ref
                            readonly property var pull: Ai.pulls[pullKey] || null
                            readonly property bool have: !!cr.modelData.installed
                            title: modelData.name
                            sub: {
                                const m = modelData;
                                const parts = [m.source || m.provider];
                                if (m.sizeText) parts.push(m.sizeText);
                                if (m.context) parts.push(root.ctxText(m.context) + " context");
                                if (m.downloads) parts.push(m.downloads.toLocaleString(Qt.locale(), "f", 0) + " downloads");
                                if (m.gated) parts.push("needs a Hugging Face login");
                                return parts.join(" · ");
                            }
                            sub2: cr.pull ? (cr.pull.total ? `Downloading ${Math.round(100 * cr.pull.completed / cr.pull.total)}%` : "Downloading…")
                                          : cr.modelData.fits === "DoesNotFit" ? "Too big for this computer" : cr.modelData.desc || ""
                            Label {
                                visible: cr.have
                                text: "Installed"
                                color: Theme.good
                                font.pointSize: Theme.smallFontSize
                            }
                            PushButton {
                                visible: !cr.have && !cr.pull
                                text: "Install"
                                tooltip: "Download " + cr.modelData.ref + (cr.modelData.sizeText ? " (" + cr.modelData.sizeText + ")" : "")
                                onClicked: Ai.install(cr.modelData.provider, cr.modelData.ref)
                            }
                        }
                    }
                }
            }
            Label {
                visible: root.tab === "more" && !Ai.catalog.loading && !!Ai.catalog.error
                text: Ai.catalog.error || ""
                color: Theme.warn
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    // One model: category icon, two lines, buttons on the right.
    component ModelRow: RowLayout {
        id: row
        property var m: ({})
        property string title: ""
        property string sub: ""
        property string sub2: ""
        default property alias buttons: btns.data
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 3
            radius: 6
            color: Qt.rgba(0, 0, 0, 0)
            border.width: 0
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Theme.aiCategoryColor(row.m.category)
                opacity: 0.22
            }
            Icon {
                anchors.centerIn: parent
                implicitSize: 16
                name: Theme.aiCategoryIcon(row.m.category) + "-symbolic"
                fallback: Theme.aiCategoryIcon(row.m.category)
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            spacing: 0
            Label { text: row.title; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Label { text: row.sub; visible: text !== ""; Layout.fillWidth: true; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
            Label { text: row.sub2; visible: text !== ""; Layout.fillWidth: true; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
        }
        RowLayout {
            id: btns
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Keep a model loaded (never unloaded automatically).
    component PinButton: MouseArea {
        id: pb
        property bool on: false
        signal toggled()
        implicitWidth: 24
        implicitHeight: 24
        hoverEnabled: true
        onClicked: toggled()
        Rectangle { anchors.fill: parent; radius: 5; color: pb.on ? Theme.accentDim : pb.containsMouse ? Theme.hover : "transparent" }
        Icon { anchors.centerIn: parent; implicitSize: 14; name: "window-pin-symbolic"; fallback: "window-pin" }
        Tooltip { anchorItem: pb; hovered: pb.containsMouse; text: pb.on ? "Kept loaded" : "Keep loaded"; subtext: pb.on ? "Click to let it unload when unused" : "Never unload it automatically" }
    }
}
