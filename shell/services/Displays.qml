pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Displays (Settings > Displays): per output resolution and refresh rate,
// scale, arrangement, rotation, on/off, HDR + SDR brightness, colour
// profile and adaptive sync, under arbor.
//
// Applying sends the change to arbor right away over IPC (`Output` requests,
// what `arbor msg output` does) and writes ~/.config/hearth/arbor-displays.kdl,
// which arbor's config includes before its own output blocks (arbor uses the
// first block for an output, so these win) and which also carries what IPC
// can't change (HDR, colour profile). Then a "Keep these settings?" prompt
// counts down 15 s (popups/DisplayConfirm.qml) and puts everything back
// unless you keep them, like macOS and Plasma.
//
// Saved state: settings.json `displays` = { "DP-1": { on, mode, scale, x, y,
// transform, vrr, hdr, sdrBrightness, maxLuminance, colorProfile } }.
Singleton {
    id: root

    property var live: ({})        // name -> arbor IPC Output
    property var parsed: ({})      // name -> what arbor's config.kdl sets (hdr, colour, vrr mode)
    readonly property var saved: { void Settings.data; return Settings.data.displays || null; }
    readonly property var names: Object.keys(live).sort()

    // Current settings of every connected output: saved ones, else from
    // arbor (IPC + its config).
    readonly property var states: {
        const out = {};
        for (const n of root.names) out[n] = root.stateFor(n);
        return out;
    }
    function modeString(m) { return `${m.width}x${m.height}@${(m.refresh_rate / 1000).toFixed(3)}`; }
    function stateFor(n) {
        const o = root.live[n];
        const s = root.saved && root.saved[n];
        if (s) return Object.assign({}, s);
        const p = root.parsed[n] || {};
        const l = o.logical;
        const m = o.current_mode !== null && o.current_mode !== undefined ? o.modes[o.current_mode] : (o.modes.find(x => x.is_preferred) || o.modes[0]);
        return {
            on: !!l,
            mode: m ? modeString(m) : "",
            scale: l ? Math.round(l.scale * 1e6) / 1e6 : 1,
            x: l ? l.x : 0,
            y: l ? l.y : 0,
            transform: l ? ({ Normal: "normal", "90": "90", "180": "180", "270": "270" })[l.transform] || "normal" : "normal",
            vrr: o.vrr_enabled ? (p.vrr === "always" ? "always" : "on-demand") : (p.vrr || "off"),
            hdr: !!p.hdr,
            sdrBrightness: p.sdrBrightness || 400,
            maxLuminance: p.maxLuminance || 800,
            colorProfile: p.colorProfile || "srgb"
        };
    }
    function describe(n) {
        const o = root.live[n];
        if (!o) return n;
        const mk = [o.make, o.model].filter(x => x && x !== "Unknown").join(" ");
        return mk ? `${mk} (${n})` : n;
    }
    // Logical size with a state's mode, rotation and scale.
    function logicalSize(st) {
        const m = (st.mode || "").match(/^(\d+)x(\d+)/);
        let w = m ? +m[1] : 1920, h = m ? +m[2] : 1080;
        if (st.transform === "90" || st.transform === "270") { const t = w; w = h; h = t; }
        const sc = st.scale || 1;
        return { w: Math.round(w / sc), h: Math.round(h / sc) };
    }

    function refresh() {
        Compositor.arborRequest("Outputs", r => { if (r.Ok && r.Ok.Outputs) root.live = r.Ok.Outputs; });
    }
    Component.onCompleted: if (Compositor.isArbor) refresh()
    Timer { interval: 5000; repeat: true; running: Compositor.isArbor && !root.pending; onTriggered: root.refresh() }

    // --- arbor's own output blocks (for HDR, colour profile, VRR mode) ---
    readonly property string arborConfig: ArborConfig.mainConfig
    FileView {
        path: Compositor.isArbor ? root.arborConfig : ""
        blockLoading: false
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parsed = root.parseOutputs(text())
    }
    function parseOutputs(text) {
        const out = {};
        const t = text.replace(/\/\/[^\n]*/g, "");
        const re = /^\s*output\s+"([^"]+)"\s*\{/gm;
        let m;
        while ((m = re.exec(t))) {
            let i = re.lastIndex, depth = 1;
            const start = i;
            for (; i < t.length && depth > 0; i++) { if (t[i] === "{") depth++; else if (t[i] === "}") depth--; }
            const body = t.slice(start, i - 1);
            if (out[m[1]]) continue;          // the first block for an output wins
            const p = {};
            const hdr = body.match(/hdr\s*\{([^}]*)\}/);
            if (hdr && !/\boff\b/.test(hdr[1])) {
                p.hdr = true;
                const sb = hdr[1].match(/sdr-brightness\s+([\d.]+)/);
                const ml = hdr[1].match(/max-luminance\s+([\d.]+)/);
                if (sb) p.sdrBrightness = +sb[1];
                if (ml) p.maxLuminance = +ml[1];
            }
            const cp = body.match(/color-profile\s+"([^"]+)"/);
            if (cp) p.colorProfile = cp[1];
            const vrr = body.match(/variable-refresh-rate([^\n;]*)/);
            if (vrr) p.vrr = /on-demand\s*=\s*true/.test(vrr[1]) ? "on-demand" : "always";
            out[m[1]] = p;
        }
        return out;
    }

    // --- KDL ---
    function kdlFor(all) {
        const lines = ["// Written by hearth (Settings > Displays). Changes here are replaced."];
        for (const n of Object.keys(all).sort()) {
            const s = all[n];
            lines.push(`output ${ArborConfig.str(n)} {`);
            if (!s.on) lines.push("    off");
            if (s.mode) lines.push(`    mode ${ArborConfig.str(s.mode)}`);
            lines.push(`    scale ${Number(s.scale).toFixed(6).replace(/0+$/, "").replace(/\.$/, "")}`);
            lines.push(`    transform ${ArborConfig.str(s.transform || "normal")}`);
            lines.push(`    position x=${Math.round(s.x)} y=${Math.round(s.y)}`);
            if (s.vrr === "on-demand") lines.push("    variable-refresh-rate on-demand=true");
            else if (s.vrr === "always") lines.push("    variable-refresh-rate");
            if (s.colorProfile && s.colorProfile !== "srgb") lines.push(`    color-profile ${ArborConfig.str(s.colorProfile)}`);
            if (s.hdr) {
                lines.push("    hdr {");
                lines.push(`        sdr-brightness ${Math.round(s.sdrBrightness)}`);
                lines.push(`        max-luminance ${Math.round(s.maxLuminance)}`);
                lines.push("    }");
            }
            lines.push("}");
        }
        return lines.join("\n");
    }

    // --- live changes over IPC ---
    function send(name, action) {
        Compositor.arborRequest({ Output: { output: name, action: action } }, r => {
            if (r.Err !== undefined) console.warn("arbor output", name, JSON.stringify(action), r.Err);
        });
    }
    function sendState(name, s, old) {
        if (!s.on) { if (!old || old.on) send(name, "Off"); return; }
        if (old && !old.on) send(name, "On");
        const m = (s.mode || "").match(/^(\d+)x(\d+)(?:@([\d.]+))?$/);
        if (m && (!old || old.mode !== s.mode))
            send(name, { Mode: { mode: { Specific: { width: +m[1], height: +m[2], refresh: m[3] ? +m[3] : null } } } });
        if (!old || old.scale !== s.scale) send(name, { Scale: { scale: { Specific: Number(s.scale) } } });
        if (!old || old.transform !== s.transform)
            send(name, { Transform: { transform: s.transform === "normal" ? "Normal" : s.transform } });
        if (!old || old.x !== s.x || old.y !== s.y) send(name, { Position: { position: { Specific: { x: Math.round(s.x), y: Math.round(s.y) } } } });
        if (!old || old.vrr !== s.vrr) send(name, { Vrr: { vrr: { vrr: s.vrr !== "off", on_demand: s.vrr === "on-demand" } } });
    }

    // --- apply / keep / revert ---
    property bool pending: false       // waiting for "Keep these settings?"
    property int secondsLeft: 0
    property var before: null          // settings.json `displays` before applying (null: none)
    property var beforeStates: ({})
    property string error: ""
    readonly property string fileName: "arbor-displays.kdl"

    function apply(next) {
        if (root.pending) keep();
        const all = Object.assign({}, root.states, next);
        root.error = "";
        root.before = root.saved ? JSON.parse(JSON.stringify(root.saved)) : null;
        root.beforeStates = JSON.parse(JSON.stringify(root.states));
        ArborConfig.write(root.fileName, root.kdlFor(all), (ok, err) => {
            if (!ok) { root.error = err; return; }
            for (const n in next) root.sendState(n, next[n], root.beforeStates[n]);
            Settings.set("displays", all);
            root.secondsLeft = 15;
            root.pending = true;
            countdown.restart();
            Qt.callLater(root.refresh);
        });
    }
    function keep() {
        countdown.stop();
        root.pending = false;
    }
    function revert() {
        countdown.stop();
        root.pending = false;
        const cur = root.states;
        for (const n in root.beforeStates) root.sendState(n, root.beforeStates[n], cur[n]);
        if (root.before) {
            Settings.set("displays", root.before);
            ArborConfig.write(root.fileName, root.kdlFor(root.before));
        } else {
            Settings.reset("displays");
            ArborConfig.remove(root.fileName);
        }
        refreshSoon.restart();
    }
    // Back to arbor's config (forget everything set here).
    function resetAll() {
        if (root.pending) keep();
        root.before = root.saved ? JSON.parse(JSON.stringify(root.saved)) : null;
        Settings.reset("displays");
        ArborConfig.remove(root.fileName, () => refreshSoon.restart());
    }
    Timer { id: refreshSoon; interval: 1200; onTriggered: root.refresh() }
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft--;
            if (root.secondsLeft <= 0) root.revert();
        }
    }

    IpcHandler {
        target: "displays"
        function keep(): void { root.keep(); }
        function revert(): void { root.revert(); }
        function state(): string { return JSON.stringify(root.states, null, 2); }
        // JSON object of { output: { field: value } } changes, as the page applies them.
        function apply(json: string): string {
            const ch = JSON.parse(json);
            const next = {};
            for (const n in ch) next[n] = Object.assign({}, root.states[n], ch[n]);
            root.apply(next);
            return "ok";
        }
    }
}
