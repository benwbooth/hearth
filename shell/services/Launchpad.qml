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
// Grouped logically: by the entry's freedesktop main category into
// sections (Internet, Office, Games...), or A to Z
// (Settings > Desktop & Dock > Launchpad).
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
    readonly property var apps: {
        const seen = new Set();
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || seen.has(e.id) || !e.name) continue;
            seen.add(e.id);
            out.push({ key: e.id, entry: e, name: e.name, icon: e.icon || "application-x-executable", section: sectionOf(e).id });
        }
        return out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
    }

    // Collapse or expand a section (remembered in settings).
    function toggleSection(id) {
        const shut = (Settings.launchpad.collapsed || []).slice();
        const i = shut.indexOf(id);
        if (i >= 0) shut.splice(i, 1); else shut.push(id);
        Settings.set("launchpad.collapsed", shut);
    }
    function sectionTitle(id) { const s = sections.find(x => x.id === id); return s ? s.title : ""; }

    // What the grid shows: [{ id, title, collapsed, items }]. A search is one flat,
    // best-first list ("Results").
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
            return [{ id: "", title: "", collapsed: false, items: hits.map(h => h.a) }];
        }
        if (Settings.launchpad.group !== "category") return [{ id: "", title: "", collapsed: false, items: apps }];
        const shut = Settings.launchpad.collapsed || [];
        return sections.map(s => ({ id: s.id, title: s.title, collapsed: shut.indexOf(s.id) >= 0,
                                    items: apps.filter(a => a.section === s.id) }))
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
        function state(): string { return JSON.stringify({ open: root.open, apps: root.apps.length, groups: root.groups.map(g => g.title + ":" + g.items.length) }); }
    }
}
