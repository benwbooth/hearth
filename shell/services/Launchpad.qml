pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Launchpad (popups/LaunchpadWindow.qml): every installed app in a
// full-screen grid, like macOS's. The desktop entries come from
// Quickshell's DesktopEntries (scanned off the UI thread; Flatpak apps are
// in because the session's XDG_DATA_DIRS has the Flatpak export dirs);
// NoDisplay ones are left out (Hidden ones are dropped by the scan).
//
// Arranged by kind (the entry's freedesktop main category: Internet,
// Office, Games...), A to Z, most used, or in the person's own groups and
// subgroups (Custom: drag apps around, rename, add and delete groups).
//
//   hearth-ipc call launchpad toggle | open | close
Singleton {
    id: root

    property bool open: false
    // The screen it opens on (the focused one when it opens).
    property string screenName: ""
    property string query: ""
    // Each screen's Dock registers how to drag into it (bar/Dock.qml
    // `externalHost`), keyed by screen name.
    property var dockHosts: ({})
    function show() { query = ""; screenName = Compositor.focusedOutput || ""; open = true; }
    function hide() { open = false; }
    function toggle() { if (open) hide(); else show(); }

    // Sections, first match wins (an app in Game;Network is a game).
    readonly property var sections: [
        { id: "games", title: "Games", cats: ["Game"] },
        { id: "dev", title: "Development", cats: ["Development", "IDE", "Debugger", "RevisionControl"] },
        { id: "graphics", title: "Graphics & Photos", cats: ["Graphics", "Photography", "Viewer"] },
        { id: "media", title: "Music & Video", cats: ["AudioVideo", "Audio", "Video", "Player", "Music"] },
        { id: "office", title: "Office", cats: ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ContactManagement", "Finance"] },
        { id: "internet", title: "Internet & Chat", cats: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "IRCClient", "P2P", "FileTransfer"] },
        { id: "learn", title: "Education & Science", cats: ["Education", "Science", "Math", "Astronomy"] },
        { id: "settings", title: "Settings", cats: ["Settings", "DesktopSettings", "HardwareSettings"] },
        { id: "system", title: "System", cats: ["System", "Monitor", "TerminalEmulator", "PackageManager", "Emulator", "FileManager", "Security"] },
        { id: "utilities", title: "Utilities", cats: ["Utility", "Accessibility", "TextEditor", "Archiving", "Compression", "Core"] },
        { id: "other", title: "Other", cats: [] }
    ]
    function sectionOf(entry) {
        const cats = entry.categories || [];
        for (const s of sections) if (s.cats.some(c => cats.indexOf(c) >= 0)) return s;
        return sections[sections.length - 1];
    }

    // Every app to show: [{ key, entry, name, icon, section }], by name.
    // Rebuilt only when the apps really change: Quickshell reports its
    // application list as changed several times a second with nothing new,
    // and rebuilding this (and the grid, the Dock's groups... after it) each
    // time kept the shell's main thread busy: the Dock stuttered, even at
    // low load. Checked at most every 300 ms, against a signature.
    property var apps: []
    property string appsSig: ""
    function rebuildApps() {
        const seen = new Set();
        const keep = [];
        const sig = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || seen.has(e.id) || !e.name) continue;
            seen.add(e.id);
            keep.push(e);
            sig.push(e.id + "\u0001" + e.name + "\u0001" + (e.icon || "") + "\u0001" + (e.categories || []).join(";"));
        }
        const s = sig.sort().join("\u0002");
        if (s === appsSig) return;
        appsSig = s;
        const out = keep.map(e => ({ key: e.id, entry: e, name: e.name, icon: e.icon || "application-x-executable", section: sectionOf(e).id }));
        apps = out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { if (!appsTimer.running) appsTimer.start(); }
    }
    Timer { id: appsTimer; interval: 300; onTriggered: root.rebuildApps() }
    Component.onCompleted: rebuildApps()

    // Collapse or expand a section (remembered in settings).
    function toggleSection(id) {
        const shut = (Settings.launchpad.collapsed || []).slice();
        const i = shut.indexOf(id);
        if (i >= 0) shut.splice(i, 1); else shut.push(id);
        Settings.set("launchpad.collapsed", shut);
    }
    function sectionTitle(id) { const s = sections.find(x => x.id === id); return s ? s.title : ""; }

    // --- how the apps are arranged (Settings launchpad.sort) ---
    // "kind": sections by category; "name": A to Z; "used": most opened
    // first; "custom": the person's own groups and subgroups, in the order
    // they dragged them into (launchpad.custom).
    readonly property string sort: {
        const s = Settings.launchpad.sort;
        if (["kind", "name", "used", "custom"].indexOf(s) >= 0) return s;
        return Settings.launchpad.group === "name" ? "name" : "kind";   // before sort existed
    }
    readonly property var sortModes: [
        { value: "kind", label: "By Kind", note: "Sections such as Internet & Chat, Games and Development, from each app's category." },
        { value: "name", label: "By Name", note: "Every app, A to Z." },
        { value: "used", label: "Most Used", note: "The apps you open most often first (from Search and the Launchpad)." },
        { value: "custom", label: "Custom", note: "Your own groups and order: drag apps around, right-click a group's title to rename, add or delete groups." }
    ]
    function setSort(v) { Settings.set("launchpad.sort", v); }

    // Custom arrangement: { groups: [{ id, title, parent, apps: [keys] }] },
    // groups in display order (a subgroup's `parent` is its group's id).
    readonly property var custom: {
        const c = Settings.launchpad.custom;
        return c && Array.isArray(c.groups) ? c : { groups: [] };
    }
    function saveCustom(c) { Settings.set("launchpad.custom", c); }
    function cloneCustom() { return JSON.parse(JSON.stringify(custom)); }
    readonly property string unsortedId: "__new"

    // Switch to Custom, starting from what's shown now (so dragging an app
    // in By Kind keeps the sections). Returns the arrangement to edit.
    function ensureCustom() {
        if (sort === "custom" && custom.groups.length) return cloneCustom();
        let c;
        if (custom.groups.length) c = cloneCustom();
        else if (sort === "kind" || sort === "custom")
            c = { groups: sections.map(s => ({ id: s.id, title: s.title, parent: "", apps: apps.filter(a => a.section === s.id).map(a => a.key) }))
                                  .filter(g => g.apps.length) };
        else c = { groups: [{ id: "apps", title: "Apps", parent: "", apps: plainOrder().map(a => a.key) }] };
        saveCustom(c);
        setSort("custom");
        return c;
    }
    function plainOrder() {
        if (sort !== "used") return apps;
        return apps.slice().sort((x, y) => (Spotlight.usage["app:" + y.key] || 0) - (Spotlight.usage["app:" + x.key] || 0)
                                           || x.name.localeCompare(y.name, undefined, { sensitivity: "base" }));
    }

    // Put app `key` into group `gid` before the `index`th app shown there
    // (`shown`: that group's keys as displayed, without `key`). The
    // unsorted group ("New Apps") means: in no group.
    function moveApp(key, gid, index, shown) {
        const c = ensureCustom();
        for (const g of c.groups) g.apps = g.apps.filter(k => k !== key);
        // "" is the one list of By Name / Most Used, now the "Apps" group.
        const g = c.groups.find(x => x.id === gid) || (gid === "" ? c.groups[0] : null);
        if (g) {
            const before = index < shown.length ? shown[index] : null;
            let at = before ? g.apps.indexOf(before) : -1;
            if (at < 0) {
                const last = shown.length ? g.apps.indexOf(shown[shown.length - 1]) : -1;
                at = last >= 0 ? last + 1 : g.apps.length;
            }
            g.apps.splice(at, 0, key);
        }
        saveCustom(c);
    }
    function newId() { return "g" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36); }
    // A new group after `afterId` (or at the end); `parent` makes it a
    // subgroup. Returns its id.
    function addGroup(title, parent, afterId) {
        const c = ensureCustom();
        const id = newId();
        const g = { id: id, title: title || "New Group", parent: parent || "", apps: [] };
        let at = c.groups.length;
        if (afterId) {
            // After that group and all of its subgroups.
            const i = c.groups.findIndex(x => x.id === afterId);
            if (i >= 0) { at = i + 1; while (at < c.groups.length && isUnder(c, c.groups[at].id, afterId)) at++; }
        } else if (parent) {
            const i = c.groups.findIndex(x => x.id === parent);
            if (i >= 0) { at = i + 1; while (at < c.groups.length && isUnder(c, c.groups[at].id, parent)) at++; }
        }
        c.groups.splice(at, 0, g);
        saveCustom(c);
        return id;
    }
    function isUnder(c, id, ancestor) {
        let g = c.groups.find(x => x.id === id);
        while (g && g.parent) { if (g.parent === ancestor) return true; g = c.groups.find(x => x.id === g.parent); }
        return false;
    }
    function renameGroup(id, title) {
        const c = ensureCustom();
        const g = c.groups.find(x => x.id === id);
        if (!g || !title.trim()) return;
        g.title = title.trim();
        saveCustom(c);
    }
    // Delete a group: its apps go to its parent group (or New Apps), its
    // subgroups move up a level. No app is ever removed.
    function deleteGroup(id) {
        const c = ensureCustom();
        const g = c.groups.find(x => x.id === id);
        if (!g) return;
        const parent = c.groups.find(x => x.id === g.parent);
        if (parent) parent.apps = parent.apps.concat(g.apps.filter(k => parent.apps.indexOf(k) < 0));
        for (const x of c.groups) if (x.parent === id) x.parent = g.parent;
        c.groups = c.groups.filter(x => x.id !== id);
        saveCustom(c);
    }
    // Move a group (with its subgroups) before its previous / after its
    // next sibling.
    function moveGroup(id, dir) {
        const c = ensureCustom();
        const g = c.groups.find(x => x.id === id);
        if (!g) return;
        const span = (gid) => {
            const i = c.groups.findIndex(x => x.id === gid);
            let j = i + 1;
            while (j < c.groups.length && isUnder(c, c.groups[j].id, gid)) j++;
            return [i, j];
        };
        const sibs = c.groups.filter(x => x.parent === g.parent).map(x => x.id);
        const k = sibs.indexOf(id), other = sibs[k + dir];
        if (other === undefined) return;
        const [a0, a1] = span(id);
        const moving = c.groups.splice(a0, a1 - a0);
        const [b0, b1] = span(other);
        c.groups.splice(dir < 0 ? b0 : b1, 0, ...moving);
        saveCustom(c);
    }
    function resetCustom() { Settings.set("launchpad.custom", null); }
    function groupTitle(id) {
        const g = custom.groups.find(x => x.id === id);
        return g ? g.title : id === unsortedId ? "New Apps" : sectionTitle(id);
    }

    // What the grid shows: [{ id, title, depth, collapsed, items, custom }].
    // A search is one flat, best-first list.
    readonly property var groups: {
        const q = query.trim().toLowerCase();
        if (q) {
            const hits = [];
            for (const a of apps) {
                const e = a.entry;
                let s = Spotlight.score(a.name, q);
                if (!s) s = Math.max(Spotlight.score(e.genericName, q) * 0.7,
                                     (e.keywords || []).some(k => k.toLowerCase().startsWith(q)) ? 45 : 0,
                                     Spotlight.score(e.id.replace(/\.desktop$/, "").split(".").pop(), q) * 0.8);
                if (s > 0) hits.push({ a: a, s: s + Spotlight.boost("app:" + e.id) });
            }
            hits.sort((x, y) => y.s - x.s);
            return [{ id: "", title: "", depth: 0, collapsed: false, items: hits.map(h => h.a), custom: false }];
        }
        const shut = Settings.launchpad.collapsed || [];
        if (sort === "name" || sort === "used") {
            void Spotlight.usage;
            return [{ id: "", title: "", depth: 0, collapsed: false, items: plainOrder(), custom: false }];
        }
        if (sort === "custom" && custom.groups.length) {
            const byKey = {};
            for (const a of apps) byKey[a.key] = a;
            const placed = new Set();
            const out = [];
            const depthOf = g => { let d = 0, p = g.parent; while (p) { const pg = custom.groups.find(x => x.id === p); if (!pg) break; d++; p = pg.parent; } return d; };
            const hiddenBy = g => { let p = g.parent; while (p) { if (shut.indexOf(p) >= 0) return true; const pg = custom.groups.find(x => x.id === p); p = pg ? pg.parent : ""; } return false; };
            for (const g of custom.groups) {
                const items = (g.apps || []).map(k => byKey[k]).filter(a => a && !placed.has(a.key));
                for (const a of items) placed.add(a.key);
                if (hiddenBy(g)) continue;
                out.push({ id: g.id, title: g.title, depth: depthOf(g), collapsed: shut.indexOf(g.id) >= 0, items: items, custom: true });
            }
            const rest = apps.filter(a => !placed.has(a.key));
            if (rest.length) out.push({ id: unsortedId, title: "New Apps", depth: 0, collapsed: shut.indexOf(unsortedId) >= 0, items: rest, custom: true, unsorted: true });
            return out;
        }
        return sections.map(s => ({ id: s.id, title: s.title, depth: 0, collapsed: shut.indexOf(s.id) >= 0,
                                    items: apps.filter(a => a.section === s.id), custom: false }))
                       .filter(g => g.items.length > 0);
    }

    function launch(a) {
        if (!a || !a.entry) return;
        Launch.app(a.entry);
        Spotlight.used("app:" + a.entry.id);
        hide();
    }

    // Show the app's .desktop file in the file manager (grove, through
    // FileManager1), found off the UI thread by a small shell lookup over
    // the data dirs.
    function showInFiles(id) {
        Quickshell.execDetached(["sh", "-c",
            'id="$1"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/run/current-system/sw/share}" | tr : " "); do '
            + 'f="$d/applications/$id.desktop"; [ -f "$f" ] || f="$d/applications/$(echo "$id" | tr - /).desktop"; '
            + 'if [ -f "$f" ]; then f=$(readlink -f "$f"); busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 '
            + 'org.freedesktop.FileManager1 ShowItems ass 1 "file://$f" "" >/dev/null 2>&1 || xdg-open "$(dirname "$f")"; exit 0; fi; done', "sh", id]);
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        function search(text: string): void { if (!root.open) root.show(); root.query = text; }
        function toggleSection(id: string): void { root.toggleSection(id); }
        function setSort(mode: string): void { root.setSort(mode); }
        function addGroup(title: string, parent: string): string { return root.addGroup(title, parent, ""); }
        function renameGroup(id: string, title: string): void { root.renameGroup(id, title); }
        function deleteGroup(id: string): void { root.deleteGroup(id); }
        function moveGroup(id: string, dir: int): void { root.moveGroup(id, dir); }
        function state(): string { return JSON.stringify({ open: root.open, sort: root.sort, apps: root.apps.length, groups: root.groups.map(g => "  ".repeat(g.depth) + g.id + "=" + g.title + ":" + g.items.length) }); }
    }
}
