pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history, like KDE's Klipper: everything you copy (text and
// pictures) is kept by cliphist, fed by `wl-paste --watch` (needs the
// compositor's data-control protocol: arbor and Hyprland have it). Pinned
// items live in a second database that is never trimmed. All the work runs
// in helpers/hearth-clipboard through Process, never on the UI thread.
//
// The popover is bar/indicators/Clipboard.qml (Super+V):
//   hearth-ipc call clipboard toggle | open | close | clear
// Settings > Clipboard: settings.json `clipboard`.
Singleton {
    id: root

    readonly property var cfg: Settings.clipboard
    readonly property bool enabled: cfg.enabled !== false
    readonly property int historySize: Math.max(5, Math.min(5000, Number(cfg.historySize) || 100))

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/hearth"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/hearth"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // "Clear on logout": the history lives in the runtime dir, which the
    // system empties when you log out. Pinned items are always kept.
    readonly property string historyDb: cfg.clearOnLogout ? runtimeDir + "/hearth/clipboard.db" : cacheDir + "/clipboard.db"
    readonly property string pinsDb: stateDir + "/clipboard-pins.db"
    readonly property string thumbDir: cacheDir + "/clipboard-thumbs"

    readonly property var helperEnv: ({
        HEARTH_CLIP_DB: root.historyDb,
        HEARTH_CLIP_PINS: root.pinsDb,
        HEARTH_CLIP_THUMBS: root.thumbDir,
        HEARTH_CLIP_MAX: String(root.historySize),
        HEARTH_CLIP_SECRETS: root.cfg.ignoreSecrets === false ? "0" : "1",
        HEARTH_CLIP_IGNORE: [].concat(root.cfg.ignoreApps || []).join("\n")
    })

    // [{ key, kind: "p"|"h", id, pinned, text, image, thumb, fmt, size, dims, url, path }]
    // pinned first, then the history, newest first.
    property var items: []
    property bool loaded: false
    // Why the history isn't being recorded ("" when it is).
    property string error: ""

    signal toggleRequested()
    signal openRequested()
    signal closeRequested()

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = line.split("\t");
            if (f.length < 3) continue;
            const kind = f[0], id = f[1], prev = f[2], thumb = f[3] || "";
            const m = prev.match(/^\[\[ binary data (.+) ([a-z]+) (\d+)x(\d+) \]\]$/);
            const it = { key: kind + id, kind: kind, id: id, pinned: kind === "p", text: prev, image: !!m,
                         thumb: thumb, fmt: m ? m[2] : "", size: m ? m[1] : "", w: m ? Number(m[3]) : 0, h: m ? Number(m[4]) : 0, dims: m ? m[3] + "×" + m[4] : "",
                         url: "", path: "" };
            if (m) it.text = "Image " + it.dims + " (" + it.fmt.toUpperCase() + ", " + it.size + ")";
            else if (/^(https?|ftp):\/\/\S+$/i.test(prev) || /^www\.\S+\.\S+$/i.test(prev)) it.url = /^www\./i.test(prev) ? "https://" + prev : prev;
            else if (/^(file:\/\/|~\/|\/)\S+$/.test(prev) && !/…$/.test(prev)) it.path = prev.replace(/^~\//, root.home + "/");
            out.push(it);
        }
        root.items = out;
        root.loaded = true;
    }

    // --- recording ---
    // wl-paste runs the store hook for every new clipboard (and, if asked,
    // every new selection); it prints "stored" so the list refreshes.
    // (An inline component can't see `root`: everything comes in as
    // properties and goes out as signals.)
    component Watcher: Process {
        id: w
        property bool primary: false
        property bool textOnly: false
        property var env: ({})
        property bool wanted: false
        property int quickFails: 0
        property double startedAt: 0
        signal stored()
        signal failing(string why)
        // setpriv --pdeathsig: wl-paste goes when hearth does (killed or
        // crashed), instead of piling up a second watcher per restart.
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste"].concat(primary ? ["--primary"] : [])
                    .concat(textOnly ? ["--type", "text"] : [])
                    .concat(["--watch", "hearth-clipboard", "store"])
        environment: Object.assign({ HEARTH_CLIP_PRIMARY: primary ? "1" : "0" }, env)
        stdout: SplitParser { onRead: line => { if (line === "stored") w.stored(); } }
        stderr: StdioCollector { id: err }
        onRunningChanged: if (running) startedAt = Date.now()
        onExited: (code, status) => {
            if (!w.wanted) return;
            // Restart if it dies; one that keeps dying at once (no
            // data-control protocol, wl-paste missing) is retried slowly.
            w.quickFails = Date.now() - w.startedAt < 3000 ? w.quickFails + 1 : 0;
            if (w.quickFails >= 3) w.failing(err.text.trim() || "wl-paste stopped (exit " + code + ")");
            restart.interval = w.quickFails >= 3 ? 30000 : 1000;
            restart.restart();
        }
        // A reload (hot reload, settings) must not leave the old one running.
        Component.onDestruction: { wanted = false; running = false; }
        function apply(on) {
            wanted = on;
            quickFails = 0;
            restart.interval = 300;
            if (running) running = false;
            if (on) restart.restart();
        }
        property Timer restart: Timer {
            interval: 300
            onTriggered: if (w.wanted && !w.running) w.running = true
        }
    }
    Watcher {
        id: clipWatch
        textOnly: root.cfg.images === false
        env: root.helperEnv
        onStored: refreshSoon.restart()
        onFailing: why => root.error = why
    }
    Watcher {
        id: primaryWatch
        primary: true
        textOnly: true
        env: root.helperEnv
        onStored: refreshSoon.restart()
    }

    // Any change to what or how we record restarts the watchers.
    readonly property string watchKey: JSON.stringify([enabled, cfg.images, cfg.primary, helperEnv])
    onWatchKeyChanged: applySoon.restart()
    Timer {
        id: applySoon
        interval: 200
        onTriggered: {
            root.error = "";
            clipWatch.apply(root.enabled);
            primaryWatch.apply(root.enabled && !!root.cfg.primary);
            root.refresh();
        }
    }
    Component.onCompleted: applySoon.start()

    // --- listing ---
    Timer { id: refreshSoon; interval: 150; onTriggered: root.refresh() }
    property bool refreshAgain: false
    function refresh() {
        if (lister.running) { refreshAgain = true; return; }
        lister.running = true;
    }
    Process {
        id: lister
        command: ["hearth-clipboard", "list"]
        environment: root.helperEnv
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        onExited: if (root.refreshAgain) { root.refreshAgain = false; root.refresh(); }
    }

    // --- actions, one at a time ---
    property var queue: []
    function run(args, then) {
        queue = queue.concat([{ args: args, then: then || null }]);
        if (!actor.running) next();
    }
    function next() {
        if (!queue.length) { refresh(); return; }
        const job = queue[0];
        queue = queue.slice(1);
        actor.job = job;
        actor.command = ["hearth-clipboard"].concat(job.args);
        actor.running = true;
    }
    Process {
        id: actor
        property var job: null
        environment: root.helperEnv
        stdout: StdioCollector { id: actorOut }
        onExited: (code, status) => {
            const j = actor.job;
            if (j && j.then) j.then(code === 0 ? actorOut.text : null);
            root.next();
        }
    }

    function copy(it) { run(["copy", it.kind, it.id].concat(it.image ? [it.fmt] : [])); }
    function remove(it) {
        items = items.filter(x => x.key !== it.key);   // at once; the list catches up
        run(["delete", it.kind, it.id]);
    }
    function pin(it) { run([it.pinned ? "unpin" : "pin", it.id]); }
    function clear() {
        items = items.filter(x => x.pinned);
        run(["wipe"]);
    }
    // The full text of an item (the list only has a preview); cb(text|null).
    function fullText(it, cb) { run(["decode", it.kind, it.id], cb); }
    function copyText(text) { Quickshell.execDetached(["wl-copy", "--", text]); }
    function open(it) {
        if (it.url || it.path) Launch.open(it.url || it.path);
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggleRequested(); }
        function open(): void { root.openRequested(); }
        function close(): void { root.closeRequested(); }
        function clear(): void { root.clear(); }
        function list(): string { return JSON.stringify(root.items.map(i => [i.key, i.text])); }
    }
}
