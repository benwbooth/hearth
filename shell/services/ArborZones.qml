pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// FanzyZones under arbor. arbor does the snapping itself (Shift while
// dragging, `move-window-to-zone N` binds, the `MoveWindowToZone` action);
// this service gives it the zones from ~/.config/hearth/zones.json (the file
// the tray picker bar/indicators/Zones.qml edits, shared with Hyprland's
// hypr/fanzyzones.lua) over arbor's `SetZones` IPC, and turns arbor's
// `ZoneDragChanged` events into the overlay's commands (popups/ZoneOverlay.qml):
//   show <output> <layout-id> <x> <y> <w> <h> | hover <zone, 1-based> | flash ... | hide
//
//   hearth-ipc call zones snap N | nextLayout | prevLayout | useLayout ID | toggleOverlay
Singleton {
    id: root

    property var cfg: null
    readonly property var layouts: cfg && cfg.layouts ? cfg.layouts : []
    readonly property bool active: Compositor.isArbor

    readonly property string configPath: {
        const env = Quickshell.env("HEARTH_ZONES_CONFIG");
        if (env) return env;
        const xdg = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdg + "/hearth/zones.json";
    }

    // The overlay listens to this (same commands as Hyprland's custom events).
    signal overlayCommand(string data)

    function layoutFor(output) {
        if (!cfg) return null;
        const id = (cfg.display_layouts || {})[output] || cfg.default_layout;
        return layouts.find(l => l.id === id) || layouts[0] || null;
    }
    function fractions(layout) {
        return layout ? layout.zones.map(z => [+z.x, +z.y, +z.width, +z.height]) : [];
    }

    // --- arbor ---
    function push() {
        if (!active || !cfg) return;
        const outputs = {};
        const names = Quickshell.screens.map(s => s.name).concat(Object.keys(cfg.display_layouts || {}));
        for (const n of names) outputs[n] = fractions(layoutFor(n));
        Compositor.arborRequest({ SetZones: {
            outputs: outputs,
            default: fractions(layoutFor("")),
            gap: Math.max(0, +(cfg.gap || 0)),
            padding: Math.max(0, +(cfg.outer_padding || 0)),
            modifier: cfg.snap_mode !== "auto"
        } }, r => { if (r && r.Err !== undefined) console.warn("arbor SetZones:", r.Err); });
    }
    // arbor restarted (the event stream reconnected): it forgot the zones.
    readonly property bool streaming: active && Compositor.backend ? !!Compositor.backend.streaming : false
    onStreamingChanged: if (streaming) push()
    Connections {
        target: Quickshell
        function onScreensChanged() { root.push(); }
    }

    property string dragOutput: ""
    Connections {
        target: root.active ? Compositor : null
        ignoreUnknownSignals: true
        function onZoneDrag(drag) {
            if (!drag) {
                if (root.dragOutput !== "") root.overlayCommand("hide");
                root.dragOutput = "";
                return;
            }
            if (root.cfg && root.cfg.enable_zone_overlay === false) return;
            const l = root.layoutFor(drag.output);
            if (!l) return;
            if (root.dragOutput !== drag.output) {
                root.dragOutput = drag.output;
                root.overlayCommand(["show", drag.output, l.id].concat(drag.area.map(Math.round)).join(" "));
            }
            root.overlayCommand("hover " + (drag.zone === null || drag.zone === undefined ? 0 : drag.zone + 1));
        }
    }

    // Brief preview of an output's zones (layout switched, or asked for).
    function flash(output) {
        const l = layoutFor(output);
        if (!l) return;
        Compositor.arborRequest("WorkingAreas", r => {
            const areas = r && r.Ok ? r.Ok.WorkingAreas : null;
            const a = areas ? areas[output] : null;
            if (!a) return;
            root.overlayCommand(["flash", output, l.id].concat(a.map(Math.round)).join(" "));
        });
    }

    // --- actions ---
    // Moves the focused window into zone n (1-based) of its display.
    function snap(n) { Compositor.arborAction("MoveWindowToZone", { id: null, zone: n }); }

    function focusedOutput() {
        return Compositor.focusedOutput || (Quickshell.screens.length ? Quickshell.screens[0].name : "");
    }
    // which: a layout id, "next" or "prev".
    function setLayout(output, which) {
        if (!cfg || layouts.length === 0) return;
        output = output || focusedOutput();
        const cur = layouts.indexOf(layoutFor(output));
        let l;
        if (which === "next") l = layouts[(cur + 1) % layouts.length];
        else if (which === "prev") l = layouts[(cur - 1 + layouts.length) % layouts.length];
        else l = layouts.find(x => x.id === which);
        if (!l) return;
        const c = Object.assign({}, cfg);
        c.display_layouts = Object.assign({}, c.display_layouts || {});
        c.display_layouts[output] = l.id;
        c.layout_mru = [l.id].concat((c.layout_mru || []).filter(id => id !== l.id));
        cfg = c;
        save();
        push();
        flash(output);
    }
    function toggleOverlay() {
        if (dragOutput !== "") return;
        flash(focusedOutput());
    }

    // --- zones.json ---
    function save() { file.setText(JSON.stringify(cfg, null, 2) + "\n"); }

    // The built-in layouts, in the order the picker and Super+Ctrl+PgUp/PgDn
    // go through them. Ids never change (zones.json and display choices name
    // them); zones are numbered column by column, top to bottom, for the
    // Super+Ctrl+1…9 binds. New ones reach an existing zones.json through
    // mergeBuiltins() below.
    function builtinLayouts() {
        const z = (name, x, y, w, h) => ({ name: name, x: x, y: y, width: w, height: h });
        const t = 1 / 3;
        const cols = (ws, names) => { let x = 0; return ws.map((w, i) => { const r = z(names[i], x, 0, w, 1); x += w; return r; }); };
        const grid = (nc, nr) => {
            const out = [];
            for (let r = 0; r < nr; r++)
                for (let c = 0; c < nc; c++) out.push(z("Zone " + (r * nc + c + 1), c / nc, r / nr, 1 / nc, 1 / nr));
            return out;
        };
        const L = (id, name, zones) => ({ id: "builtin." + id, name: name, is_built_in: true, zones: zones });
        return [
            // Columns.
            L("two-panes", "Two Panes", cols([0.5, 0.5], ["Left", "Right"])),
            L("split-60-40", "60 / 40", cols([0.6, 0.4], ["Main", "Side"])),
            L("split-40-60", "40 / 60", cols([0.4, 0.6], ["Side", "Main"])),
            L("two-panes-wide", "Two Panes (Wide + Side)", cols([0.7, 0.3], ["Main", "Side"])),
            L("two-thirds-left", "Two Thirds + One Third", cols([2 * t, t], ["Main", "Side"])),
            L("two-thirds-right", "One Third + Two Thirds", cols([t, 2 * t], ["Side", "Main"])),
            L("three-panes", "Three Panes", cols([t, t, t], ["Left", "Center", "Right"])),
            L("three-panes-ultrawide", "Three Panes (Ultrawide)", cols([0.25, 0.5, 0.25], ["Left", "Center", "Right"])),
            L("four-columns", "Four Columns", cols([0.25, 0.25, 0.25, 0.25], ["Column 1", "Column 2", "Column 3", "Column 4"])),
            // A big zone with stacked neighbours.
            L("priority-grid", "Priority Grid", [z("Left Top", 0, 0, 0.25, 0.5), z("Left Bottom", 0, 0.5, 0.25, 0.5),
                                                 z("Center", 0.25, 0, 0.5, 1),
                                                 z("Right Top", 0.75, 0, 0.25, 0.5), z("Right Bottom", 0.75, 0.5, 0.25, 0.5)]),
            L("priority-left", "Priority (Left Focus)", [z("Focus", 0, 0, 0.6, 1), z("Top-Right", 0.6, 0, 0.4, 0.5), z("Bottom-Right", 0.6, 0.5, 0.4, 0.5)]),
            L("priority-right", "Priority (Right Focus)", [z("Top-Left", 0, 0, 0.4, 0.5), z("Bottom-Left", 0, 0.5, 0.4, 0.5), z("Focus", 0.4, 0, 0.6, 1)]),
            L("left-and-right-stack", "One Left + Two Right", [z("Left", 0, 0, 0.5, 1), z("Top-Right", 0.5, 0, 0.5, 0.5), z("Bottom-Right", 0.5, 0.5, 0.5, 0.5)]),
            L("left-stack-and-right", "Two Left + One Right", [z("Top-Left", 0, 0, 0.5, 0.5), z("Bottom-Left", 0, 0.5, 0.5, 0.5), z("Right", 0.5, 0, 0.5, 1)]),
            // Rows.
            L("two-rows", "Two Rows", [z("Top", 0, 0, 1, 0.5), z("Bottom", 0, 0.5, 1, 0.5)]),
            L("top-and-two-bottom", "One Top + Two Bottom", [z("Top", 0, 0, 1, 0.5), z("Bottom-Left", 0, 0.5, 0.5, 0.5), z("Bottom-Right", 0.5, 0.5, 0.5, 0.5)]),
            // Grids.
            L("quarters", "Quarters", grid(2, 2).map((q, i) => Object.assign(q, { name: ["Top-Left", "Top-Right", "Bottom-Left", "Bottom-Right"][i] }))),
            L("grid-3x2", "Grid 3x2", grid(3, 2)),
            L("grid-3x3", "Grid 3x3", grid(3, 3)),
            // One window in the middle, room around it.
            L("centered-focus", "Centered Focus", [z("Focus", 0.2, 0.05, 0.6, 0.9)])
        ];
    }
    function isBuiltin(l) { return !!l && (l.is_built_in || String(l.id).startsWith("builtin.")); }
    // zones.json's built-ins brought up to date (new ones added, in their
    // place in the list), custom layouts kept after them. null: nothing to do.
    function mergeBuiltins(c) {
        const want = builtinLayouts().concat((c.layouts || []).filter(l => !isBuiltin(l)));
        if (JSON.stringify(want) === JSON.stringify(c.layouts || [])) return null;
        return Object.assign({}, c, { layouts: want });
    }

    // A fresh config (no zones.json yet).
    function defaultConfig() {
        return {
            version: 1,
            snap_mode: "modifier",
            modifiers: ["shift"],
            default_layout: "builtin.three-panes",
            display_layouts: {},
            layout_mru: ["builtin.three-panes", "builtin.two-panes", "builtin.quarters"],
            gap: 0,
            outer_padding: 0,
            enable_zone_overlay: true,
            show_zone_numbers: true,
            highlight_color: { red: 0.18, green: 0.48, blue: 0.96 },
            overlay_opacity: 0.35,
            keyboard_shortcuts_enabled: true,
            layouts: builtinLayouts()
        };
    }

    FileView {
        id: file
        path: root.active ? root.configPath : ""
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            let c;
            try { c = JSON.parse(text()); } catch (e) { console.warn("zones.json:", e); return; }
            // Layouts added to hearth since the file was written.
            const merged = root.mergeBuiltins(c);
            root.cfg = merged || c;
            if (merged) root.save();
            root.push();
        }
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound) return;
            root.cfg = root.defaultConfig();
            root.save();
            root.push();
        }
    }

    IpcHandler {
        target: "zones"
        enabled: root.active
        function snap(n: int): void { root.snap(n); }
        function nextLayout(): void { root.setLayout("", "next"); }
        function prevLayout(): void { root.setLayout("", "prev"); }
        function useLayout(id: string): void { root.setLayout("", id); }
        function toggleOverlay(): void { root.toggleOverlay(); }
    }
}
