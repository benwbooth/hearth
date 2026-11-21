import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../widgets"
import "../../services"
import "../.."

// FanzyZones layout picker (the Plasma applet's tray menu). The tray glyph is
// the active layout drawn from its zones; the popup lists every layout with a
// preview: click a row to use it on this display, click a zone in a preview
// to snap the focused window there. Layouts and settings live in
// ~/.config/hearth/zones.json, shared with hypr/fanzyzones.lua, which this
// drives through `FanzyZones.cmd(...)` dispatches under Hyprland; under arbor
// services/ArborZones.qml hands the zones to arbor, which snaps windows itself. Custom layouts are made
// with a simple columns x rows editor (relative widths/heights).
Indicator {
    id: root

    property var cfg: null
    readonly property var layouts: cfg && cfg.layouts ? cfg.layouts : []
    readonly property string screenName: {
        const w = root.QsWindow.window;
        return w && w.screen ? w.screen.name : Compositor.focusedOutput;
    }
    // Display the popup acts on (switchable when there are several).
    property string targetDisplay: ""
    readonly property string display: targetDisplay || screenName
    readonly property var activeLayout: layoutFor(screenName)
    readonly property color accent: cfg && cfg.highlight_color
        ? Qt.rgba(cfg.highlight_color.red, cfg.highlight_color.green, cfg.highlight_color.blue, 1)
        : Theme.accent
    readonly property real screenAspect: {
        const s = root.QsWindow.window ? root.QsWindow.window.screen : null;
        return s && s.height > 0 ? s.width / s.height : 16 / 9;
    }

    shown: (Compositor.isHyprland || Compositor.isArbor) && cfg !== null
    tooltip: activeLayout ? "Zones: " + activeLayout.name : "Zones"
    tooltipSub: "Scroll to change layout. Shift-drag a window or press Super+Ctrl+1…9 to snap it into a zone"

    readonly property string configPath: {
        const env = Quickshell.env("HEARTH_ZONES_CONFIG");
        if (env) return env;
        const xdg = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdg + "/hearth/zones.json";
    }

    function layoutFor(mon) {
        if (!cfg) return null;
        const id = (cfg.display_layouts || {})[mon] || cfg.default_layout;
        return layouts.find(l => l.id === id) || layouts[0] || null;
    }
    readonly property var activeLayoutHere: layoutFor(display)
    // The picker's order: this display's layout first, then most recently used.
    readonly property var orderedLayouts: {
        const mru = (cfg && cfg.layout_mru) || [];
        const rank = l => l === activeLayoutHere ? -1 : (mru.indexOf(l.id) < 0 ? 1000 + layouts.indexOf(l) : mru.indexOf(l.id));
        return layouts.slice().sort((a, b) => rank(a) - rank(b));
    }
    // The editor window saved a layout: store it and use it on that display,
    // in one write of zones.json (ArborZones / the Lua module re-read it).
    Connections {
        target: root.ipcHere ? ZoneEditor : null
        function onSaved(layout, displayName) {
            const out = displayName || root.display;
            const c = Object.assign({}, root.cfg);
            const ls = root.layouts.slice();
            const i = ls.findIndex(l => l.id === layout.id);
            if (i >= 0) ls[i] = layout; else ls.push(layout);
            c.layouts = ls;
            c.display_layouts = Object.assign({}, c.display_layouts || {});
            c.display_layouts[out] = layout.id;
            c.layout_mru = [layout.id].concat((c.layout_mru || []).filter(id => id !== layout.id));
            root.cfg = c;
            root.save();
            if (Compositor.isArbor) flashLater.restart();
        }
    }
    Timer { id: flashLater; interval: 400; onTriggered: ArborZones.flash(root.display) }

    // FanzyZones only exists under the Lua config, so no legacy fallback.
    function lua(expr) { Hyprland.dispatch(expr); }
    function useLayout(id) {
        if (Compositor.isArbor) { ArborZones.setLayout(root.display, id); return; }
        lua(`FanzyZones.cmd("set_layout", ${Hypr.lit(root.display)}, ${Hypr.lit(id)})`);
    }
    function snapZone(layout, index) {
        // Snapping goes by the focused window's own display; make sure that
        // display shows this layout first.
        if (root.layoutFor(root.display) !== layout) useLayout(layout.id);
        if (Compositor.isArbor) ArborZones.snap(index + 1);
        else lua(`FanzyZones.cmd("snap", ${index + 1})`);
    }
    // Write zones.json, then have the Lua side re-read it.
    property bool reloadAfterSave: false
    function save() {
        reloadAfterSave = true;
        file.setText(JSON.stringify(cfg, null, 2) + "\n");
    }
    function setOption(key, value) {
        const c = Object.assign({}, cfg);
        c[key] = value;
        cfg = c;
        save();
    }
    function deleteLayout(id) {
        const c = Object.assign({}, cfg);
        c.layouts = layouts.filter(l => l.id !== id);
        const dl = Object.assign({}, c.display_layouts || {});
        for (const k in dl) if (dl[k] === id) delete dl[k];
        c.display_layouts = dl;
        if (c.default_layout === id) c.default_layout = c.layouts.length ? c.layouts[0].id : "";
        cfg = c;
        save();
    }
    function saveLayout(layout) {
        const c = Object.assign({}, cfg);
        const ls = layouts.slice();
        const i = ls.findIndex(l => l.id === layout.id);
        if (i >= 0) ls[i] = layout; else ls.push(layout);
        c.layouts = ls;
        cfg = c;
        save();
    }

    onScrolled: delta => {
        if (!cfg || layouts.length === 0) return;
        if (Compositor.isArbor) { ArborZones.setLayout(root.screenName, delta < 0 ? "next" : "prev"); return; }
        lua(`FanzyZones.cmd("set_layout", ${Hypr.lit(root.screenName)}, ${Hypr.lit(delta < 0 ? "next" : "prev")})`);
    }
    onRightClicked: Compositor.isArbor ? ArborZones.toggleOverlay() : lua(`FanzyZones.cmd("toggle_overlay")`)

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.cfg = JSON.parse(text()); } catch (e) { console.warn("zones.json:", e); }
        }
        onLoadFailed: root.cfg = null
        onSaved: {
            if (root.reloadAfterSave) {
                root.reloadAfterSave = false;
                // arbor: ArborZones watches the file and resends the zones.
                if (Compositor.isHyprland) root.lua(`FanzyZones.cmd("reload")`);
            }
        }
    }

    // Tray glyph: the active layout's zones.
    property Item glyph: Item {
        parent: root
        anchors.centerIn: parent
        width: 24
        height: 16
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: "transparent"
            // The menu bar's text colour (white or black with the wallpaper,
            // like every status icon), not the window text colour.
            border.color: root.menuBarItem ? Theme.barFg : Theme.fgDim
            border.width: 1
            opacity: root.menuBarItem ? 0.6 : 1
        }
        Repeater {
            model: root.activeLayout ? root.activeLayout.zones : []
            delegate: Rectangle {
                required property var modelData
                x: 2 + Math.round(modelData.x * 20)
                y: 2 + Math.round(modelData.y * 12)
                width: Math.max(2, Math.round(modelData.width * 20) - 1)
                height: Math.max(2, Math.round(modelData.height * 12) - 1)
                color: root.menuBarItem ? Theme.barFg : Theme.fg
                opacity: 0.85
            }
        }
    }

    // A layout's zones drawn into a box; zones can be clicked.
    component Diagram: Rectangle {
        id: dia
        property var layout: null
        property bool active: false
        property bool clickable: true
        signal zoneClicked(int index)
        radius: 3
        color: Qt.rgba(0, 0, 0, 0.18)
        border.color: Theme.border
        border.width: 1
        Repeater {
            model: dia.layout ? dia.layout.zones : []
            delegate: Rectangle {
                id: zr
                required property var modelData
                required property int index
                x: 3 + modelData.x * (dia.width - 6) + 1
                y: 3 + modelData.y * (dia.height - 6) + 1
                width: Math.max(3, modelData.width * (dia.width - 6) - 2)
                height: Math.max(3, modelData.height * (dia.height - 6) - 2)
                radius: 2
                color: zm.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                     : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, dia.active ? 0.38 : 0.22)
                border.color: zm.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                border.width: zm.containsMouse ? 2 : 1
                Label {
                    anchors.centerIn: parent
                    text: zr.index + 1
                    color: zm.containsMouse ? Theme.fg : Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                    visible: zr.height > 14 && zr.width > 12
                }
                MouseArea {
                    id: zm
                    anchors.fill: parent
                    enabled: dia.clickable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dia.zoneClicked(zr.index)
                }
            }
        }
    }

    component Pill: MouseArea {
        id: pill
        property string text: ""
        property bool selected: false
        implicitWidth: pl.implicitWidth + 16
        implicitHeight: 24
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: pill.selected ? Theme.accentDim : pill.containsMouse ? Theme.hover : "transparent"
            border.color: pill.selected ? Theme.accent : Theme.border
        }
        Label {
            id: pl
            anchors.centerIn: parent
            text: pill.text
            font.pointSize: Theme.smallFontSize
        }
    }

    popupContent: ColumnLayout {
        id: menu
        spacing: 4
        implicitWidth: 480

        // Opens the layout editor window (popups/ZoneEditorWindow.qml); a
        // built-in layout is edited as a copy.
        function startEdit(l) {
            ZoneEditor.edit(l, root.display);
            if (root.menuPopup) root.menuPopup.close();
        }
        readonly property bool editing: false

        // Header: title and the display being configured.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 6
            Label {
                text: "Zones"
                font.bold: true
                Layout.fillWidth: true
            }
            Repeater {
                model: menu.editing ? [] : (Quickshell.screens.length > 1 ? Quickshell.screens : [])
                delegate: Pill {
                    required property var modelData
                    text: modelData.name
                    selected: modelData.name === root.display
                    onClicked: root.targetDisplay = modelData.name
                }
            }
        }

        // ---- Layout list: a grid of cards (preview above, name below) ----
        Label {
            visible: !menu.editing
            Layout.fillWidth: true
            // Wrap at the menu's width instead of widening it.
            Layout.preferredWidth: menu.implicitWidth
            Layout.bottomMargin: 2
            text: "Click a layout to use it on this display, or a zone to move the focused window there. "
                + "Shift-drag a window or press Super+Ctrl+1…9 to snap."
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
        }
        GridLayout {
            id: cards
            visible: !menu.editing
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8
            readonly property real cardWidth: (width - columnSpacing * (columns - 1)) / columns

            Repeater {
                model: menu.editing ? [] : root.orderedLayouts
                delegate: MouseArea {
                    id: card
                    required property var modelData
                    readonly property bool active: root.layoutFor(root.display) && root.layoutFor(root.display).id === modelData.id
                    Layout.preferredWidth: cards.cardWidth
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: col.implicitHeight + 16
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.useLayout(modelData.id)

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: card.active ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                             : card.containsMouse ? Theme.hover : Theme.bgRaised
                        border.color: card.active ? root.accent : card.containsMouse ? Theme.border : "transparent"
                        border.width: card.active ? 2 : 1
                    }
                    ColumnLayout {
                        id: col
                        x: 8
                        y: 8
                        width: parent.width - 16
                        height: parent.height - 16
                        spacing: 6
                        Diagram {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round(Math.max(44, Math.min(80, width / root.screenAspect)))
                            layout: card.modelData
                            active: card.active
                            onZoneClicked: i => root.snapZone(card.modelData, i)
                        }
                        Label {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            font.bold: card.active
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: card.active ? "Active" : card.modelData.zones.length + " zones"
                            color: card.active ? root.accent : Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Item { Layout.fillHeight: true }
                    }
                    // Custom layouts: edit / delete on hover.
                    Row {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 2
                        visible: card.containsMouse
                        Repeater {
                            model: card.modelData.is_built_in
                                ? [{ i: "document-edit", t: "Customize a copy of", f: () => menu.startEdit(card.modelData) }]
                                : [{ i: "document-edit", t: "Edit", f: () => menu.startEdit(card.modelData) },
                                   { i: "edit-delete", t: "Delete", f: () => root.deleteLayout(card.modelData.id) }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 22
                                height: 22
                                radius: 11
                                color: bm.containsMouse ? Theme.hover : Theme.bg
                                border.color: Theme.border
                                Icon {
                                    anchors.centerIn: parent
                                    implicitSize: 14
                                    name: parent.modelData.i
                                }
                                MouseArea {
                                    id: bm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.modelData.f()
                                    Tooltip {
                                        anchorItem: bm
                                        hovered: bm.containsMouse
                                        text: bm.parent.modelData.t + " this layout"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Options ----
        Rectangle {
            visible: !menu.editing
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Theme.border
        }
        Repeater {
            model: menu.editing || !root.cfg ? [] : [
                { t: "Snap only while holding Shift", k: "snap_mode", on: root.cfg.snap_mode !== "auto",
                  v: on => on ? "modifier" : "auto" },
                { t: "Show zone overlay while dragging", k: "enable_zone_overlay", on: root.cfg.enable_zone_overlay !== false },
            ].concat(Compositor.isArbor ? [] : [
                // Hyprland only: arbor keeps its own dynamic workspaces.
                { t: "Maximized / fullscreen windows get their own workspace", k: "macsimize_maximized",
                  on: root.cfg.macsimize_maximized !== false && root.cfg.macsimize_fullscreen !== false },
                { t: "Dynamic workspaces", k: "dynamic_workspaces", on: root.cfg.dynamic_workspaces !== false },
            ])
            delegate: MenuItem {
                required property var modelData
                Layout.fillWidth: true
                checkable: true
                checked: modelData.on
                text: modelData.t
                onTriggered: {
                    const on = !modelData.on;
                    if (modelData.k === "macsimize_maximized") {
                        const c = Object.assign({}, root.cfg);
                        c.macsimize_maximized = on;
                        c.macsimize_fullscreen = on;
                        root.cfg = c;
                        root.save();
                    } else {
                        root.setOption(modelData.k, modelData.v ? modelData.v(on) : on);
                    }
                }
            }
        }
        MenuItem {
            visible: !menu.editing
            Layout.fillWidth: true
            icon: "list-add"
            text: "New custom layout…"
            onTriggered: menu.startEdit(null)
        }
        MenuItem {
            visible: !menu.editing && root.activeLayoutHere !== null
            Layout.fillWidth: true
            icon: "document-edit"
            text: root.activeLayoutHere && !root.activeLayoutHere.is_built_in
                ? "Edit “" + root.activeLayoutHere.name + "”…" : "Customize the active layout (as a copy)…"
            onTriggered: menu.startEdit(root.activeLayoutHere)
        }
    }
}
