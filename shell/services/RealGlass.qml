pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Real liquid glass from arbor: every visible GlassFrame reports its pane
// (in its window's coordinates, after transforms and with its effective
// opacity) and this sends one `SetGlass` per window over arbor's IPC, so
// the compositor draws the backdrop refracted under it (arbor's ARBOR.md,
// "Liquid glass"). Reports arrive at most once per rendered frame and are
// coalesced per window (Qt.callLater), and nothing is sent when nothing
// moved. A window without visible panes sends an empty list (clears).
//
// Only on arbor with the feature (probed by the backend) and with
// Settings > Appearance > Real glass on. Elsewhere (Hyprland) nothing
// changes: GlassFrame keeps its shell-drawn look over compositor blur.
Singleton {
    id: root

    readonly property var backend: Compositor.isArbor ? Compositor.backend : null
    readonly property bool supported: !!backend && backend.glassSupported === true
    readonly property bool enabled: Settings.appearance.realGlass !== false && !Settings.appearance.reduceTransparency
    readonly property bool active: supported && enabled
    readonly property real strength: Math.max(0, Math.min(1, Number(Settings.appearance.realGlassStrength ?? 1)))

    // [{ win, key, frames: [{ frame, shape }], sent: "" }]
    property var wins: []
    property int nextKey: 1

    // arbor reconnected (restarted): send everything again.
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onGlassEpochChanged() {
            for (const e of root.wins) e.sent = "";
            root.schedule();
        }
    }
    onActiveChanged: if (!active) clearAll()

    function entryFor(win, create) {
        for (const e of wins) if (e.win === win) return e;
        if (!create) return null;
        const e = { win: win, key: "w" + (nextKey++), frames: [], sent: "" };
        wins.push(e);
        return e;
    }

    // A pane's shape: { x, y, width, height, radius, params } in `win`'s
    // coordinates. Called every frame the pane's window renders.
    function put(frame, win, shape) {
        if (!active || !win) { remove(frame); return; }
        // Moved to another window (reparented): leave the old one.
        for (const e of wins) if (e.win !== win && e.frames.some(f => f.frame === frame)) remove(frame);
        const e = entryFor(win, true);
        const rec = e.frames.find(f => f.frame === frame);
        if (rec) {
            if (sameShape(rec.shape, shape)) return;
            rec.shape = shape;
        } else {
            e.frames.push({ frame: frame, shape: shape });
        }
        schedule();
    }

    function remove(frame) {
        let changed = false;
        for (const e of wins) {
            const i = e.frames.findIndex(f => f.frame === frame);
            if (i >= 0) { e.frames.splice(i, 1); changed = true; }
        }
        if (changed) schedule();
    }

    function sameShape(a, b) {
        return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
            && a.radius === b.radius && JSON.stringify(a.params) === JSON.stringify(b.params);
    }

    function schedule() { Qt.callLater(root.flush); }

    // The layer surface (namespace, output) a window's panes belong to:
    // a PanelWindow is its own layer surface; a PopupWindow (tooltips,
    // previews) is an xdg pop-up of its parent's layer surface.
    function target(win) {
        let w = win;
        let popup = false;
        for (let i = 0; i < 8 && w && w.exclusiveZone === undefined && w.anchor !== undefined; i++) {
            popup = true;
            const a = w.anchor;
            w = a.item ? a.item.QsWindow.window : a.window;
        }
        if (!w || w.exclusiveZone === undefined) return null;
        const ns = w.WlrLayershell ? w.WlrLayershell.namespace : "";
        if (!ns) return null;
        return { namespace: ns, output: w.screen ? w.screen.name : null, popup: popup };
    }

    function round(v) { return Math.round(v * 1000) / 1000; }

    function flush() {
        if (!backend) return;
        const keep = [];
        for (const e of wins) {
            const t = target(e.win);
            if (!t) { keep.push(e); continue; }
            const req = {
                namespace: t.namespace,
                output: t.output,
                popup: t.popup,
                key: "hearth-" + e.key,
                surface_size: [round(e.win.width), round(e.win.height)],
                shapes: e.frames.map(f => f.shape)
            };
            const json = JSON.stringify(req);
            if (json !== e.sent) {
                if (backend.setGlass(req)) e.sent = json;
            }
            // Forget windows without panes once they're cleared.
            if (e.frames.length > 0 || e.sent !== json) keep.push(e);
        }
        if (keep.length !== wins.length) wins = keep;
    }

    function clearAll() {
        for (const e of wins) e.frames = [];
        flush();
        wins = [];
    }
}
