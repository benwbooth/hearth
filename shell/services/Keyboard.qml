pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keyboard settings (Settings > Keyboard): layouts and the key that
// switches between them, key repeat, Num Lock at startup. Saved in
// settings.json `keyboard` and, under arbor, written to
// ~/.config/hearth/arbor-keyboard.kdl (included by arbor's config after its
// own input block, so it wins). Nothing is written until something is
// changed here, so arbor's config keeps its own values until then.
Singleton {
    id: root

    readonly property var defaults: ({ layouts: [], switchKey: "grp:win_space_toggle", repeatDelay: 600, repeatRate: 25, numlock: true })
    readonly property bool customized: { void Settings.data; return Settings.data.keyboard !== undefined; }
    readonly property var cfg: { void Settings.data; return Object.assign({}, defaults, Settings.data.keyboard || {}); }

    // Layouts shown: the saved ones, else what arbor runs now.
    readonly property var layouts: cfg.layouts.length ? cfg.layouts : liveLayouts
    property var liveLayouts: []      // [{ layout, variant }]
    property var liveNames: []        // arbor's descriptions
    property int currentIndex: 0

    function set(key, value) {
        const k = Object.assign({}, cfg);
        if (!k.layouts.length) k.layouts = root.layouts;
        k[key] = value;
        Settings.set("keyboard", k);
    }
    function addLayout(code) {
        const m = code.match(/^([^(]+)(?:\((.*)\))?$/);
        if (!m) return;
        const l = root.layouts.slice();
        if (l.some(x => x.layout === m[1] && (x.variant || "") === (m[2] || ""))) return;
        l.push({ layout: m[1], variant: m[2] || "" });
        set("layouts", l);
    }
    function removeLayout(i) {
        const l = root.layouts.slice();
        if (l.length <= 1) return;
        l.splice(i, 1);
        set("layouts", l);
    }
    function moveLayout(i, d) {
        const l = root.layouts.slice();
        const j = i + d;
        if (j < 0 || j >= l.length) return;
        const t = l[i]; l[i] = l[j]; l[j] = t;
        set("layouts", l);
    }
    function reset() { Settings.reset("keyboard"); ArborConfig.remove("arbor-keyboard.kdl"); }

    // --- xkb's list of layouts (evdev.lst) ---
    property var layoutNames: ({})     // "us" -> "English (US)"
    property var variantNames: ({})    // "us(intl)" -> "English (US, intl., with dead keys)"
    readonly property var choices: {
        const out = [];
        for (const k in layoutNames) out.push({ value: k, label: layoutNames[k], note: k });
        for (const k in variantNames) out.push({ value: k, label: variantNames[k], note: k });
        out.sort((a, b) => a.label.localeCompare(b.label));
        return out;
    }
    function describe(l) {
        const code = l.variant ? `${l.layout}(${l.variant})` : l.layout;
        return (l.variant ? variantNames[code] : layoutNames[code]) || code;
    }
    FileView {
        path: Quickshell.env("HEARTH_XKB_RULES") || "/etc/X11/xkb/rules/evdev.lst"
        blockLoading: false
        printErrors: false
        onLoaded: {
            const ln = {}, vn = {};
            let section = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("! ")) { section = line.slice(2).trim(); continue; }
                const m = line.match(/^\s+(\S+)\s+(.*)$/);
                if (!m) continue;
                if (section === "layout") ln[m[1]] = m[2].trim();
                else if (section === "variant") {
                    const v = m[2].match(/^(\S+):\s*(.*)$/);
                    if (v) vn[`${v[1]}(${m[1]})`] = v[2].trim();
                }
            }
            root.layoutNames = ln;
            root.variantNames = vn;
            root.matchLive();
        }
    }

    // What arbor runs now (descriptions -> codes).
    function refreshLive() {
        Compositor.arborRequest("KeyboardLayouts", r => {
            if (!r.Ok || !r.Ok.KeyboardLayouts) return;
            root.liveNames = r.Ok.KeyboardLayouts.names || [];
            root.currentIndex = r.Ok.KeyboardLayouts.current_idx || 0;
            root.matchLive();
        });
    }
    function matchLive() {
        const out = [];
        for (const n of root.liveNames) {
            let hit = null;
            for (const k in root.layoutNames) if (root.layoutNames[k] === n) { hit = { layout: k, variant: "" }; break; }
            if (!hit) for (const k in root.variantNames) if (root.variantNames[k] === n) {
                const m = k.match(/^(.*)\((.*)\)$/);
                hit = { layout: m[1], variant: m[2] };
                break;
            }
            if (hit) out.push(hit);
        }
        root.liveLayouts = out.length ? out : [{ layout: "us", variant: "" }];
    }
    Component.onCompleted: if (Compositor.isArbor) refreshLive()

    // --- arbor ---
    readonly property string kdl: {
        const c = root.cfg;
        const l = root.layouts;
        const lines = ["// Written by hearth (Settings > Keyboard). Changes here are replaced.",
                       "input {", "    keyboard {", "        xkb {",
                       "            layout " + ArborConfig.str(l.map(x => x.layout).join(","))];
        if (l.some(x => x.variant)) lines.push("            variant " + ArborConfig.str(l.map(x => x.variant || "").join(",")));
        if (c.switchKey && l.length > 1) lines.push("            options " + ArborConfig.str(c.switchKey));
        lines.push("        }",
                   "        repeat-delay " + Math.round(c.repeatDelay),
                   "        repeat-rate " + Math.round(c.repeatRate),
                   c.numlock ? "        numlock" : "        numlock false",
                   "    }", "}");
        return lines.join("\n");
    }
    property string error: ""
    onKdlChanged: if (Compositor.isArbor && root.customized && Settings.loaded) writeSoon.restart()
    Timer {
        id: writeSoon
        interval: 300
        onTriggered: ArborConfig.write("arbor-keyboard.kdl", root.kdl, (ok, err) => {
            root.error = err;
            if (ok) Qt.callLater(root.refreshLive);
        })
    }
}
