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

    // A fresh config (no zones.json yet): the same built-in layouts as the
    // Lua module.
    function defaultConfig() {
        const z = (name, x, y, w, h) => ({ name: name, x: x, y: y, width: w, height: h });
        const t = 1 / 3;
        const grid = [];
        for (let r = 0; r < 3; r++)
            for (let c = 0; c < 3; c++) grid.push(z("Zone " + (r * 3 + c + 1), c * t, r * t, t, t));
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
            layouts: [
                { id: "builtin.two-panes", name: "Two Panes", is_built_in: true, zones: [z("Left", 0, 0, 0.5, 1), z("Right", 0.5, 0, 0.5, 1)] },
                { id: "builtin.two-panes-wide", name: "Two Panes (Wide + Side)", is_built_in: true, zones: [z("Main", 0, 0, 0.7, 1), z("Side", 0.7, 0, 0.3, 1)] },
                { id: "builtin.three-panes", name: "Three Panes", is_built_in: true, zones: [z("Left", 0, 0, t, 1), z("Center", t, 0, t, 1), z("Right", 2 * t, 0, t, 1)] },
                { id: "builtin.three-panes-ultrawide", name: "Three Panes (Ultrawide)", is_built_in: true, zones: [z("Left", 0, 0, 0.25, 1), z("Center", 0.25, 0, 0.5, 1), z("Right", 0.75, 0, 0.25, 1)] },
                { id: "builtin.quarters", name: "Quarters", is_built_in: true, zones: [z("Top-Left", 0, 0, 0.5, 0.5), z("Top-Right", 0.5, 0, 0.5, 0.5), z("Bottom-Left", 0, 0.5, 0.5, 0.5), z("Bottom-Right", 0.5, 0.5, 0.5, 0.5)] },
                { id: "builtin.priority-left", name: "Priority (Left Focus)", is_built_in: true, zones: [z("Focus", 0, 0, 0.6, 1), z("Top-Right", 0.6, 0, 0.4, 0.5), z("Bottom-Right", 0.6, 0.5, 0.4, 0.5)] },
                { id: "builtin.grid-3x3", name: "Grid 3x3", is_built_in: true, zones: grid }
            ]
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
            try { root.cfg = JSON.parse(text()); } catch (e) { console.warn("zones.json:", e); return; }
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
