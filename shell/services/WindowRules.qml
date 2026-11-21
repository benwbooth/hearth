pragma Singleton
import QtQuick
import Quickshell

// Per-app window rules (Settings > Window Rules): how an app's windows
// open (docked or floating), on which workspace, at what size, with or
// without a title bar, how see-through, adaptive sync. Saved in
// settings.json `windowRules` (a list) and, under arbor, written to
// ~/.config/hearth/arbor-rules.kdl, which arbor's config includes after its
// own rules (later rules win where they set the same thing).
Singleton {
    id: root

    readonly property var rules: {
        void Settings.data;
        const r = JSON.parse(JSON.stringify(Settings.data.windowRules || []));
        return Array.isArray(r) ? r : [];
    }
    readonly property var blank: ({ appId: "", name: "", icon: "", open: "default", workspace: "",
                                    width: 0, height: 0, titleBar: "default", opacity: 100, vrr: "default" })

    function add(appId, name, icon) {
        if (root.rules.some(r => r.appId === appId)) return root.rules.findIndex(r => r.appId === appId);
        const l = root.rules.slice();
        l.push(Object.assign({}, blank, { appId: appId, name: name || appId, icon: icon || "" }));
        Settings.set("windowRules", l);
        return l.length - 1;
    }
    function update(i, key, value) {
        const l = root.rules.slice();
        if (!l[i]) return;
        l[i] = Object.assign({}, blank, l[i]);
        l[i][key] = value;
        Settings.set("windowRules", l);
    }
    function remove(i) {
        const l = root.rules.slice();
        l.splice(i, 1);
        Settings.set("windowRules", l);
    }

    // Apps to pick from: running ones first, then installed ones.
    readonly property var appChoices: {
        const seen = new Set();
        const out = [];
        const entries = DesktopEntries.applications.values;
        const byId = id => entries.find(e => e.id === id || (e.startupClass && e.startupClass === id)
                                         || e.id.toLowerCase() === id.toLowerCase());
        for (const w of Compositor.windows) {
            if (!w.appId || seen.has(w.appId)) continue;
            seen.add(w.appId);
            const e = byId(w.appId);
            out.push({ value: w.appId, label: e ? e.name : w.appId, note: "Open now · " + w.appId, icon: e ? e.icon : w.appId });
        }
        const rest = [];
        for (const e of entries) {
            if (e.noDisplay) continue;
            const id = e.startupClass || e.id;
            if (seen.has(id)) continue;
            seen.add(id);
            rest.push({ value: id, label: e.name, note: id, icon: e.icon });
        }
        rest.sort((a, b) => a.label.localeCompare(b.label));
        return out.concat(rest);
    }

    readonly property string kdl: {
        const lines = ["// Written by hearth (Settings > Window Rules). Changes here are replaced."];
        const named = [];
        for (const r of root.rules) if (r.workspace && named.indexOf(r.workspace) < 0) named.push(r.workspace);
        for (const n of named) lines.push(`workspace ${ArborConfig.str(n)}`);
        for (const r0 of root.rules) {
            const r = Object.assign({}, blank, r0);
            if (!r.appId) continue;
            const body = [];
            if (r.open === "floating") body.push("open-floating true");
            else if (r.open === "docked") body.push("open-docked true");
            if (r.workspace) body.push(`open-on-workspace ${ArborConfig.str(r.workspace)}`);
            if (r.width > 0) body.push(`default-column-width { fixed ${Math.round(r.width)}; }`);
            if (r.height > 0) body.push(`default-window-height { fixed ${Math.round(r.height)}; }`);
            if (r.titleBar !== "default") body.push(`title-bar ${r.titleBar === "on"}`);
            if (r.opacity < 100) body.push(`opacity ${(r.opacity / 100).toFixed(2)}`);
            if (r.vrr !== "default") body.push(`variable-refresh-rate ${r.vrr === "on"}`);
            if (!body.length) continue;
            lines.push(`// ${r.name || r.appId}`);
            lines.push("window-rule {");
            lines.push(`    match app-id=${ArborConfig.raw("^" + ArborConfig.escapeRegex(r.appId) + "$")}`);
            for (const b of body) lines.push("    " + b);
            lines.push("}");
        }
        return lines.join("\n");
    }
    property string error: ""
    onKdlChanged: if (Compositor.isArbor && Settings.loaded && Settings.data.windowRules !== undefined) writeSoon.restart()
    Timer {
        id: writeSoon
        interval: 400
        onTriggered: ArborConfig.write("arbor-rules.kdl", root.kdl, (ok, err) => root.error = err)
    }
}
