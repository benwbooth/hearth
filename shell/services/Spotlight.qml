pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// Spotlight (README "Spotlight"): search apps, files, folders, pictures,
// settings and actions, calculate and convert, from one field. Super+Space
// or the magnifier in the menu bar opens popups/Spotlight.qml.
//
// Apps, settings panes and actions are matched here (in memory); files,
// the calculator and web suggestions come from helpers/hearth-search as
// JSON lines, so typing never waits on the index. Each keystroke sends a
// new query id; older answers are dropped.
//
//   hearth-ipc call spotlight toggle | open | close | search "TEXT"
Singleton {
    id: root

    readonly property var defaults: ({
        folders: ["~/Desktop", "~/Documents", "~/Downloads", "~/Pictures", "~/Music", "~/Videos"],
        excludeNames: ["node_modules", ".git", "target", "__pycache__", ".venv", "result", ".direnv", ".cache"],
        excludePaths: [],
        contents: true,                 // index what's inside documents, not just names
        hidden: false,                  // include hidden files and folders
        web: false,                     // web suggestions (asks DuckDuckGo as you type)
        ask: true,                      // "Ask hearth" row: the assistant answers (Settings > AI)
        onlyWhenIdle: true,             // index only while nobody uses the computer
        idleMinutes: 3,                 // ...after this long without input
        indexOnBattery: false,
        categories: { apps: true, documents: true, folders: true, images: true, settings: true, actions: true, calculator: true, other: true }
    })
    readonly property var cfg: {
        void Settings.data;
        const d = Settings.data.spotlight || {};
        return Object.assign({}, defaults, d, { categories: Object.assign({}, defaults.categories, d.categories || {}) });
    }

    property bool open: false
    property string query: ""
    property int qid: 0
    property var files: []
    property bool filesDone: true
    property string filesError: ""
    property var calc: []
    property var web: []
    property var preview: ({})          // last preview answer
    property var status: ({})

    readonly property string shortcutText: {
        const e = Binds.effective.find(b => !b.off && /"spotlight" "toggle"/.test(b.action));
        return e ? Binds.pretty(e.key) : "Super+Space";
    }

    signal toggleRequested()
    function toggle() { open = !open; }

    function send(obj) {
        if (!proc.running) proc.running = true;
        proc.write(JSON.stringify(obj) + "\n");
    }

    function search(text) {
        query = text;
        qid++;
        files = [];
        calc = [];
        web = [];
        filesError = "";
        if (!text.trim()) { filesDone = true; return; }
        filesDone = false;
        send({ id: qid, q: text, web: !!cfg.web });
    }
    function requestPreview(item) {
        if (!item || !item.path) return;
        send({ cmd: "preview", id: qid, path: item.path, mime: item.mime || "" });
    }
    function requestStatus() { send({ cmd: "status" }); }
    function reindex() { send({ cmd: "reindex" }); }

    Process {
        id: proc
        command: ["hearth-search"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                root.handle(m);
            }
        }
        stderr: SplitParser { onRead: line => { if (!/rclinit|^:\d:/.test(line)) console.warn(line); } }
    }

    function handle(m) {
        if (m.type === "status") { root.status = m; return; }
        if (m.id !== root.qid) return;
        if (m.type === "files") {
            if (m.items && m.items.length) root.files = root.files.concat(m.items);
            if (m.done) { root.filesDone = true; root.filesError = m.error || ""; }
        } else if (m.type === "calc") {
            root.calc = m.items;
        } else if (m.type === "web") {
            root.web = m.items;
        } else if (m.type === "preview") {
            root.preview = m;
        }
    }

    // Settings > Spotlight changed: rewrite recoll's config (the indexer
    // picks it up by itself).
    readonly property string indexKey: JSON.stringify([cfg.folders, cfg.excludeNames, cfg.excludePaths, cfg.contents, cfg.hidden])
    onIndexKeyChanged: if (Settings.loaded) configureSoon.restart()
    Timer { id: configureSoon; interval: 800; onTriggered: root.send({ cmd: "configure" }) }

    // --- indexing only while idle ---
    // The indexer (hearth-indexer.service) is frozen through systemd's cgroup
    // freezer while you use the computer: no CPU, no disk, and its memory
    // stays as it is. It thaws after `idleMinutes` without input, unless an
    // app holds an idle inhibitor (a video, a game), something is full
    // screen or the laptop is on battery. "Index now" in Settings thaws it
    // until you close the pane.
    IdleMonitor {
        id: idleMon
        enabled: root.cfg.onlyWhenIdle !== false
        timeout: Math.max(30, Number(root.cfg.idleMinutes || 3) * 60)
        respectInhibitors: true
    }
    property bool forceIndex: false
    readonly property bool onBattery: UPower.onBattery
    readonly property bool indexAllowed: forceIndex || (cfg.onlyWhenIdle === false
        ? !(onBattery && !cfg.indexOnBattery)
        : idleMon.isIdle && !Wallpaper.fullscreenAny && !(onBattery && !cfg.indexOnBattery))
    readonly property string indexPausedWhy: indexAllowed ? ""
        : onBattery && !cfg.indexOnBattery ? "on battery"
        : Wallpaper.fullscreenAny ? "something is full screen"
        : "you're using the computer"
    onIndexAllowedChanged: gate.restart()
    Timer { id: gate; interval: 1500; running: true; onTriggered: root.applyGate() }
    function applyGate() {
        if (Quickshell.env("HEARTH_SEARCH_NO_SYSTEMD")) return;
        Quickshell.execDetached(["systemctl", "--user", indexAllowed ? "thaw" : "freeze", "hearth-indexer.service"]);
    }
    Component.onDestruction: Quickshell.execDetached(["systemctl", "--user", "thaw", "hearth-indexer.service"])

    // --- in-memory matches ---

    // 0 = no match; higher is better. Start of the name > start of a word >
    // anywhere; initials ("vsc" -> Visual Studio Code) count too.
    function score(text, q) {
        if (!text) return 0;
        const t = text.toLowerCase();
        if (t === q) return 100;
        if (t.startsWith(q)) return 90;
        const words = t.split(/[\s\-_.]+/);
        if (words.some(w => w.startsWith(q))) return 75;
        const initials = words.map(w => w[0] || "").join("");
        if (q.length >= 2 && initials.startsWith(q)) return 70;
        if (t.includes(q)) return 50;
        return 0;
    }

    // Launch counts (state dir), so apps you open often come first.
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("spotlight-usage.json")
        printErrors: false
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) {} }
    }
    function used(key) {
        const u = Object.assign({}, usage);
        u[key] = (u[key] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }
    function boost(key) { return Math.min(25, Math.log2(1 + (usage[key] || 0)) * 6); }

    function appMatches(text) {
        const q = text.trim().toLowerCase();
        if (!q) return [];
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            let s = score(e.name, q);
            if (!s) s = Math.max(score(e.genericName, q) * 0.7, (e.keywords || []).some(k => k.toLowerCase().startsWith(q)) ? 45 : 0,
                                 score(e.id.replace(/\.desktop$/, "").split(".").pop(), q) * 0.8);
            if (s > 0) out.push({ kind: "app", entry: e, title: e.name, subtitle: e.genericName || e.comment || "", icon: e.icon || "application-x-executable",
                                  score: s + boost("app:" + e.id), key: "app:" + e.id });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 8);
    }

    // Settings panes (popups/SettingsWindow.qml) with words people search for.
    readonly property var panes: [
        { id: "users", label: "Users & Accounts", icon: "system-users", words: "account picture avatar name password" },
        { id: "appearance", label: "Appearance", icon: "preferences-desktop-theme-global", words: "dark light mode accent colour color theme transparency glass font cursor pointer" },
        { id: "menubar", label: "Menu Bar", icon: "preferences-desktop", words: "clock date top bar icons" },
        { id: "dock", label: "Desktop & Dock", icon: "preferences-system-windows", words: "dock magnification hide size launchpad apps grid" },
        { id: "layout", label: "Layout", icon: "view-split-top-bottom", words: "panel mac classic" },
        { id: "wallpaper", label: "Wallpaper", icon: "preferences-desktop-wallpaper", words: "background desktop picture slideshow" },
        { id: "lockscreen", label: "Lock Screen", icon: "system-lock-screen", words: "password lock fingerprint" },
        { id: "hotcorners", label: "Hot Corners", icon: "preferences-desktop-screensaver", words: "corner" },
        { id: "bluetooth", label: "Bluetooth", icon: "preferences-system-bluetooth", words: "headphones keyboard mouse pair airpods speaker wireless" },
        { id: "printers", label: "Printers", icon: "printer", words: "printer printers scanner print queue add printer airprint ipp everywhere cups driver test page paper size duplex two-sided default printer" },
        { id: "displays", label: "Displays", icon: "preferences-desktop-display", words: "monitor screen resolution scale refresh hdr arrange" },
        { id: "keyboard", label: "Keyboard", icon: "preferences-desktop-keyboard", words: "layout repeat input language" },
        { id: "shortcuts", label: "Keyboard Shortcuts", icon: "preferences-desktop-keyboard-shortcut", words: "keys binds hotkeys" },
        { id: "mouse", label: "Mouse & Touchpad", icon: "preferences-desktop-mouse", words: "trackpad scroll pointer speed" },
        { id: "windowrules", label: "Window Rules", icon: "preferences-system-windows-actions", words: "app window float" },
        { id: "power", label: "Sleep & Power", icon: "preferences-system-power-management", words: "battery idle suspend energy" },
        { id: "night", label: "Night Light", icon: "redshift-status-on", words: "blue light warm" },
        { id: "sound", label: "Sound", icon: "audio-volume-high", words: "volume chime feedback pop beep" },
        { id: "notifications", label: "Notifications", icon: "preferences-desktop-notification", words: "do not disturb alerts" },
        { id: "clipboard", label: "Clipboard", icon: "klipper-symbolic", words: "copy paste history" },
        { id: "screenshots", label: "Screenshots", icon: "camera-photo", words: "screen capture record" },
        { id: "spotlight", label: "Search", icon: "search", words: "search index files folders" },
        { id: "ai", label: "AI", icon: Quickshell.shellDir + "/assets/ai.svg", words: "models ollama llama vram gpu claude codex gemini" },
        { id: "voice", label: "Voice Assistant", icon: "audio-input-microphone", words: "siri speech microphone whisper voice piper" }
    ]
    function paneMatches(text) {
        const q = text.trim().toLowerCase();
        if (q.length < 2) return [];
        const out = [];
        for (const p of panes) {
            const s = Math.max(score(p.label, q), p.words.split(" ").some(w => w.startsWith(q)) ? 55 : 0);
            if (s > 0) out.push({ kind: "settings", pane: p.id, title: p.label, subtitle: "Settings", icon: p.icon, score: s, key: "pane:" + p.id });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 4);
    }
    function actionMatches(text) {
        if (text.trim().length < 3) return [];
        return Help.search(text).filter(r => r.kind === "action" && (r.item.run || r.item.guide))
            .slice(0, 4).map(r => ({ kind: "action", item: r, title: r.title, subtitle: r.keys || "Action", icon: "system-run", score: 40, key: "action:" + r.title }));
    }

    // --- running a result ---
    function activate(r) {
        if (!r) return;
        if (r.key) used(r.key);
        switch (r.kind) {
        case "app": Launch.app(r.entry); break;
        case "settings": Settings.openRequested(r.pane); break;
        case "action": Help.activate(r.item); break;
        case "file": Quickshell.execDetached(["xdg-open", r.file.path]); break;
        case "calc": Quickshell.execDetached(["wl-copy", r.result]); break;
        case "web": Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(r.title)]); break;
        case "ask": Voice.ask(r.query); break;
        }
        root.open = false;
    }
    // Cmd+Return / Ctrl+Return: show the file in grove (FileManager1).
    function reveal(r) {
        let path = "";
        if (r && r.kind === "file") path = r.file.path;
        else if (r && r.kind === "app" && r.entry) path = "";
        if (!path) return false;
        Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                 "org.freedesktop.FileManager1", "ShowItems", "ass", "1", "file://" + path, ""]);
        root.open = false;
        return true;
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open = true; }
        function close(): void { root.open = false; }
        function search(text: string): void {
            root.pendingText = text;
            if (root.open) root.toggleRequested(); else root.open = true;
        }
        function results(): string {
            return JSON.stringify({ query: root.query, files: root.files.map(f => f.name), calc: root.calc, web: root.web.map(w => w.text),
                                    apps: root.appMatches(root.query).map(a => a.title) });
        }
    }
    // Text an IPC `search` asked for; the window types it in when it opens.
    property string pendingText: ""
}
