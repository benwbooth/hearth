pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// Which windows belong to a tray icon, so a left click on it works like a
// dock icon: brings the app's window to the front, and when it already is in
// front, minimizes it (bar/Tray.qml). An icon with no window yet (an app
// that hides to the tray) gets the app's own "activate" instead.
//
// Matched by, in order:
// - the process: the tray icon's D-Bus owner pid (helpers/hearth-tray-pids)
//   is the window's pid (Claude, Almanac, the update checker...);
// - the name: the icon's id or title is the window's app id
//   (com.stremio.Stremio, which a Flatpak proxy registers);
// - what was seen: the window that took focus right after the app's own
//   activate on an earlier click.
Singleton {
    id: root

    property var pids: ({})        // tray icon id -> pid
    property var learned: ({})     // tray icon id -> app id

    readonly property int itemCount: SystemTray.items.values.length
    onItemCountChanged: refreshSoon.restart()
    Component.onCompleted: refresh()

    Timer { id: refreshSoon; interval: 300; onTriggered: root.refresh() }

    property var pending: []
    function refresh(then) {
        if (then) pending.push(then);
        if (!proc.running) proc.running = true;
    }
    Process {
        id: proc
        command: ["hearth-tray-pids"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.pids = JSON.parse(text.trim() || "{}"); } catch (e) {}
                const p = root.pending;
                root.pending = [];
                for (const f of p) f();
            }
        }
    }

    function norm(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]/g, ""); }

    // The icon's windows, most recently used first.
    function windowsFor(item) {
        if (!item) return [];
        const all = Compositor.windowsByRecency();
        const pid = root.pids[item.id];
        let w = pid ? all.filter(x => x.pid === pid) : [];
        if (!w.length) {
            const names = [root.norm(item.id), root.norm(item.title)].filter(n => n.length > 2);
            w = all.filter(x => {
                const a = root.norm(x.appId);
                const last = root.norm(String(x.appId || "").split(".").pop());
                return a && names.some(n => n === a || n === last);
            });
        }
        if (!w.length && root.learned[item.id])
            w = all.filter(x => x.appId === root.learned[item.id]);
        return w;
    }

    // Left click on a tray icon.
    function toggle(item) {
        const go = () => {
            const wins = root.windowsFor(item);
            if (!wins.length) {
                item.activate();
                root.watch(item);
                return;
            }
            if (wins.some(w => w.focused)) {
                for (const w of wins) if (!w.minimized) Compositor.minimize(w.id);
            } else {
                // The most recent one; focusing a minimized window restores it.
                Compositor.focusWindow(wins[0].id);
            }
        };
        if (root.pids[item.id] === undefined) root.refresh(go);
        else go();
    }

    // Asks the menu bar's tray (bar/Tray.qml) to open an icon's menu.
    signal menuRequested(var item)

    // `hearth-ipc call tray click <id>`: a left click on that tray icon
    // (tests, scripts). `tray items` lists the ids.
    IpcHandler {
        target: "tray"
        function click(id: string): string {
            const item = SystemTray.items.values.find(i => i.id === id);
            if (!item) return "no tray icon " + id;
            root.toggle(item);
            return "ok";
        }
        // `tray menu <id>`: open that icon's menu (as a right click).
        function menu(id: string): string {
            const item = SystemTray.items.values.find(i => i.id === id);
            if (!item) return "no tray icon " + id;
            if (!item.hasMenu) return "no menu";
            root.menuRequested(item);
            return "ok";
        }
        function items(): string {
            return SystemTray.items.values.map(i => i.id).join("\n");
        }
    }

    // After the app's own activate: the window that takes focus is its own.
    property var watching: null
    property string focusBefore: ""
    function watch(item) {
        root.watching = item;
        root.focusBefore = Compositor.focusedWindowId;
        watchEnd.restart();
    }
    Timer { id: watchEnd; interval: 3000; onTriggered: root.watching = null }
    Connections {
        target: Compositor
        function onFocusedWindowIdChanged() {
            const item = root.watching;
            const w = Compositor.focusedWindow;
            if (!item || !w || Compositor.focusedWindowId === root.focusBefore) return;
            root.watching = null;
            if (w.pid && w.pid === root.pids[item.id]) return;
            const l = Object.assign({}, root.learned);
            l[item.id] = w.appId;
            root.learned = l;
        }
    }
}
