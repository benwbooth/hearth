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
            border.color: Theme.fgDim
            border.width: 1
        }
        Repeater {
            model: root.activeLayout ? root.activeLayout.zones : []
            delegate: Rectangle {
                required property var modelData
                x: 2 + Math.round(modelData.x * 20)
                y: 2 + Math.round(modelData.y * 12)
                width: Math.max(2, Math.round(modelData.width * 20) - 1)
                height: Math.max(2, Math.round(modelData.height * 12) - 1)
                color: Theme.fg
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
        color: Qt.rgba(1, 1, 1, 0.035)
        border.color: active ? root.accent : Theme.border
        border.width: active ? 2 : 1
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
                color: zm.containsMouse ? Theme.hover : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
                border.color: zm.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                border.width: zm.containsMouse ? 2 : 1
                Label {
                    anchors.centerIn: parent
                    text: zr.index + 1
                    color: Theme.fgDim
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

    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property string placeholder: ""
        implicitHeight: 26
        implicitWidth: 140
        radius: Theme.radius
        color: Theme.bg
        border.color: input.activeFocus ? Theme.accent : Theme.border
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pointSize: Theme.fontSize
            renderType: Text.NativeRendering
            selectByMouse: true
            clip: true
        }
        Label {
            anchors.fill: input
            anchors.leftMargin: 8
            text: fld.placeholder
            color: Theme.fgDim
            visible: input.text === "" && !input.activeFocus
        }
    }

    popupContent: ColumnLayout {
        id: menu
        spacing: 4
        implicitWidth: 440

        // null: list view; otherwise the layout being edited
        // ({ id, name, cols, rows } with weights as text).
        property var editing: null

        function weights(s) {
            const w = String(s).split(/[\s,:\/]+/).map(Number).filter(n => n > 0);
            return w.length ? w : [1];
        }
        function gridZones(cols, rows) {
            const cw = weights(cols), rw = weights(rows);
            const cs = cw.reduce((a, b) => a + b, 0), rs = rw.reduce((a, b) => a + b, 0);
            const zones = [];
            let y = 0;
            for (let r = 0; r < rw.length; r++) {
                let x = 0;
                for (let c = 0; c < cw.length; c++) {
                    zones.push({ name: "Zone " + (zones.length + 1), x: x / cs, y: y / rs,
                                 width: cw[c] / cs, height: rw[r] / rs });
                    x += cw[c];
                }
                y += rw[r];
            }
            return zones;
        }
        function startEdit(l) {
            if (l) editing = { id: l.id, name: l.name, cols: l.grid ? l.grid.cols : "1 1", rows: l.grid ? l.grid.rows : "1" };
            else editing = { id: "", name: "", cols: "1 2 1", rows: "1" };
        }

        // Header: title and the display being configured.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 6
            Label {
                text: menu.editing ? (menu.editing.id ? "Edit layout" : "New layout") : "Zones"
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

        // ---- Layout list ----
        Repeater {
            model: menu.editing ? [] : root.layouts
            delegate: MouseArea {
                id: row
                required property var modelData
                readonly property bool active: root.layoutFor(root.display) && root.layoutFor(root.display).id === modelData.id
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.useLayout(modelData.id)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: row.containsMouse ? Theme.hover : Theme.bgRaised
                    border.color: row.active ? root.accent : "transparent"
                }
                ColumnLayout {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 180
                    spacing: 2
                    Label {
                        text: row.modelData.name
                        font.bold: row.active
                        Layout.maximumWidth: 180
                    }
                    Label {
                        text: row.active ? "Active" : row.modelData.zones.length + " zones"
                        color: row.active ? root.accent : Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                    RowLayout {
                        visible: !row.modelData.is_built_in
                        spacing: 12
                        Repeater {
                            model: [{ t: "Edit", f: () => menu.startEdit(row.modelData) },
                                    { t: "Delete", f: () => root.deleteLayout(row.modelData.id) }]
                            delegate: Label {
                                required property var modelData
                                text: modelData.t
                                font.pointSize: Theme.smallFontSize
                                color: lm.containsMouse ? (modelData.t === "Delete" ? Theme.bad : root.accent) : Theme.fgDim
                                MouseArea {
                                    id: lm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.modelData.f()
                                }
                            }
                        }
                    }
                }
                Diagram {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 70
                    width: Math.min(220, Math.round(70 * root.screenAspect))
                    layout: row.modelData
                    active: row.active
                    onZoneClicked: i => root.snapZone(row.modelData, i)
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

        // ---- Editor: columns x rows with relative sizes ----
        GridLayout {
            visible: menu.editing !== null
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 6
            Label { text: "Name" }
            Field {
                id: nameField
                Layout.fillWidth: true
                placeholder: "My layout"
                text: menu.editing ? menu.editing.name : ""
            }
            Label { text: "Columns" }
            Field {
                id: colsField
                Layout.fillWidth: true
                placeholder: "relative widths, e.g. 1 2 1"
                text: menu.editing ? menu.editing.cols : ""
            }
            Label { text: "Rows" }
            Field {
                id: rowsField
                Layout.fillWidth: true
                placeholder: "relative heights, e.g. 1 1"
                text: menu.editing ? menu.editing.rows : ""
            }
        }
        Diagram {
            visible: menu.editing !== null
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            Layout.preferredHeight: 110
            Layout.preferredWidth: Math.min(420, Math.round(110 * root.screenAspect))
            clickable: false
            layout: menu.editing ? { zones: menu.gridZones(colsField.text, rowsField.text) } : null
        }
        RowLayout {
            visible: menu.editing !== null
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            Pill {
                text: "Cancel"
                onClicked: menu.editing = null
            }
            Pill {
                text: "Save"
                selected: true
                onClicked: {
                    const name = nameField.text.trim() || "Custom layout";
                    const id = menu.editing.id
                        || "user." + name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36);
                    root.saveLayout({ id: id, name: name, is_built_in: false,
                                      grid: { cols: colsField.text, rows: rowsField.text },
                                      zones: menu.gridZones(colsField.text, rowsField.text) });
                    menu.editing = null;
                }
            }
        }
    }
}
