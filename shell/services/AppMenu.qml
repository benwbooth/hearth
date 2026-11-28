pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The focused window's global menu, relayed by helpers/hearth-appmenu
// (dbusmenu, GMenuModel, X11 windows; README "Global menu"). The address
// comes from the compositor (arbor IPC `Window.app_menu` / `gtk_menu`);
// Hyprland has no source for it, so there the menu bar only shows the
// app-name and Window menus.
//
// menu: root item { id, children: [{ id, label, enabled, visible, type,
// toggleType, toggleState, icon, shortcut, submenu, children }] } or null.
Singleton {
    id: root

    // Where the focused window's menu lives, as a helper "watch" command:
    // dbusmenu (arbor app_menu: Qt/KDE, LibreOffice), GMenuModel (arbor
    // gtk_menu: GTK 3/4 apps, appmenu-gtk-module) or, for any other window,
    // "x11": the helper checks whether it's an X11 window (its client is
    // xwayland-satellite) and reads the X window's menu properties or our
    // registrar's RegisterWindow entries (Chromium, Electron, Qt on X11).
    // The focused window, held while one of hearth's own menus or popups
    // has the keyboard: arbor then reports no focused window (the layer
    // surface has focus), and the menu bar must keep showing (and talking
    // to) the app the user was in.
    property string heldId: ""
    readonly property var focused: Compositor.focusedWindow
    onFocusedChanged: if (focused) { heldId = focused.id; holding = false; }
    readonly property var win: focused
        || ((ShellState.activePopup || root.holding) && heldId
            ? (Compositor.windows.find(w => w.id === heldId) || null) : null)
    // When a hearth menu closes, arbor gives the keyboard back to the app a
    // moment later: keep the held window until then (or 400 ms), or the
    // title flashes "Desktop" in between.
    property bool holding: false
    Connections {
        target: ShellState
        function onActivePopupChanged() {
            if (!ShellState.activePopup && root.heldId) { root.holding = true; holdTimer.restart(); }
        }
    }
    Timer { id: holdTimer; interval: 400; onTriggered: root.holding = false }
    // Native menus that turned out empty (emptyTimer): appmenu-gtk-module
    // exports an empty one for Firefox and Thunderbird, whose XUL menus it
    // can't see; those windows go on to AT-SPI below instead.
    property var emptyKeys: ({})
    readonly property var ownRequest: {
        const w = root.win;
        if (!w) return null;
        const a = w.appMenu, g = w.gtkMenu;
        if (a && a.service_name && a.object_path) {
            const r = { key: "d\n" + a.service_name + "\n" + a.object_path, kind: "dbusmenu",
                        service: a.service_name, path: a.object_path };
            if (!root.emptyKeys[r.key]) return r;
        }
        if (g && g.unique_bus_name && (g.menubar_path || g.app_menu_path)) {
            const r = { key: "g\n" + g.unique_bus_name + "\n" + g.menubar_path + "\n" + g.window_object_path,
                        kind: "gtk", bus: g.unique_bus_name, menubar: g.menubar_path || "",
                        appmenu: g.app_menu_path || "", app: g.application_object_path || "",
                        win: g.window_object_path || "" };
            if (!root.emptyKeys[r.key]) return r;
        }
        // gbus/gapp/gwin: a GTK window with actions but no menus (libadwaita;
        // arbor keeps its address): the helper adds its app actions.
        if (Compositor.isArbor && w.pid)
            return { key: "x\n" + w.id, kind: "x11", pid: w.pid, title: w.title, window: Number(w.id),
                     gbus: (g && g.unique_bus_name) || "", gapp: (g && g.application_object_path) || "",
                     gwin: (g && g.window_object_path) || "", appid: w.appId || "" };
        return null;
    }
    // Like macOS, an app's menu bar stays while one of its windows without
    // menus (a dialog, a second X11 window) is in front: the last menu seen
    // for that app id is used when the window itself has none.
    property var lastByApp: ({})
    property var resolved: ({})     // x11 key -> the concrete request it found
    // The app id a window's remembered menu is under: its own, or, for a
    // dialog with an id of its own (LibreOffice's are "soffice" in front of
    // "libreoffice-writer": Tip of the Day, Options), that of another window
    // of the same process that has one.
    function menuApp(w, map) {
        if (!w || map[w.appId] || !w.pid) return w ? w.appId : "";
        const o = Compositor.windows.find(x => x.pid === w.pid && x.id !== w.id && map[x.appId]);
        return o ? o.appId : w.appId;
    }
    property string noneKey: ""
    readonly property var request: {
        const own = root.ownRequest;
        if (own && own.key !== root.noneKey) return own;
        const last = root.win ? root.lastByApp[root.menuApp(root.win, root.lastByApp)] : null;
        return last || own;
    }
    readonly property string key: (request && request.key) || ""
    property var menu: null
    // For tests: follow a given menu regardless of the focused window.
    property string forced: ""
    property string menuKey: ""
    property bool registrarOwned: false
    readonly property string wanted: forced || key
    readonly property bool current: !!menu && wanted !== "" && menuKey === wanted
    // What the menu bar shows: the menu once it's here, and while it's still
    // on its way after a switch (AT-SPI apps, Electron: some hundred ms), the
    // last one this app had, so the bar doesn't flash the app name and
    // Window alone first. `resolving` is that wait (up to 500 ms).
    property var treeByApp: ({})
    // The key the bar has settled on: the menu came, or 500 ms passed.
    // Compared with `wanted` (not a running timer), so a switch counts as
    // resolving from its first frame, whatever order bindings update in.
    property string settledKey: ""
    readonly property bool resolving: wanted !== "" && !current && settledKey !== wanted
    onWantedChanged: { resolveTimer.restart(); extrasAloneTimer.restart() }
    onCurrentChanged: if (current) settledKey = wanted
    onUsableChanged: if (usable) replayClick()
    Timer { id: resolveTimer; interval: 500; onTriggered: root.settledKey = root.wanted }
    // While the app's menu isn't here: the last one it had (a dialog of
    // the app keeps it too, as on macOS).
    // An empty menu (a LibreOffice dialog exports one of its own) counts as
    // none here: the app's last one stays.
    readonly property bool usable: current && (menu.children || []).length > 0
    readonly property var ownTree: usable ? menu
        : (win ? (treeByApp[menuApp(win, treeByApp)] || (current ? menu : null)) : (current ? menu : null))
    // Menus the helper adds to the window's own (MPRIS: a media player's
    // Playback), appended after them.
    property var extraMenus: null
    // Not alone while the window's own menus may still come: Spotify's,
    // read off its ☰ over AT-SPI, take a second or so, and the bar showed
    // just Playback until then. Alone once the helper says the window has
    // none, or after 3 s (a player with no menus of its own).
    property string extrasAloneKey: ""
    Timer { id: extrasAloneTimer; interval: 3000; onTriggered: root.extrasAloneKey = root.wanted }
    readonly property var tree: {
        const extra = extraMenus && extraMenus.key === wanted ? (extraMenus.menus || []) : [];
        if (!extra.length) return ownTree;
        if (!ownTree && extrasAloneKey !== wanted && noneKey !== wanted) return null;
        const base = ownTree || { id: 0, label: "", children: [] };
        // An extra menu the window's own menus already have (a harvested
        // File next to a real File) is left out.
        const have = (base.children || []).map(i => String(i.label || "").toLowerCase());
        const add = extra.filter(m => !have.includes(String(m.label || "").toLowerCase()));
        return Object.assign({}, base, { children: (base.children || []).concat(add) });
    }
    // One menu per title: LibreOffice's GMenuModel menu bar has its menus
    // twice, in two sections.
    readonly property var topLevel: tree
        ? tree.children.filter((i, n, all) => i.visible && i.type !== "separator" && i.label !== ""
                               && all.findIndex(j => j.visible && j.type !== "separator" && j.label === i.label) === n)
        : []
    // A GTK app's GNOME 3 style app menu (helper: root child id -2); the
    // menu bar shows it at the top of the bold app-name menu.
    // Or, for a GTK window without menus, its app actions (Settings…,
    // Keyboard Shortcuts, Help) from the helper's "appactions".
    property var appActions: null
    readonly property var gtkAppMenu: (tree ? (tree.children.find(i => i.id === -2) || null) : null)
        || (appActions && appActions.key === wanted ? appActions.menu : null)
    readonly property bool available: topLevel.length > 0

    // Only where hearth draws the menus: arbor with the mac layout.
    // The helper owns com.canonical.AppMenu.Registrar while it runs, and
    // with that name owned Qt apps hide their in-window menu bars, so it
    // must not run on Hyprland (no address source) or with the classic
    // panel. HEARTH_APPMENU=1 forces it (testing). Singleton touched from
    // shell.qml at startup so apps launched later find the registrar.
    readonly property bool enabled: (Compositor.isArbor && Settings.mac) || Quickshell.env("HEARTH_APPMENU") === "1"

    signal openRequested(string label)

    function send(obj) { if (proc.running) proc.write(JSON.stringify(obj) + "\n"); }
    // The user is in the global menu on some screen (GlobalMenu.engaged):
    // the helper's accessibility reader opens an app's menus only then.
    property var engagedBy: ({})
    readonly property bool engaged: Object.keys(engagedBy).some(k => engagedBy[k])
    function setEngaged(who, on) {
        if (!!engagedBy[who] === on) return;
        const e = Object.assign({}, engagedBy);
        if (on) e[who] = true; else delete e[who];
        engagedBy = e;
    }
    onEngagedChanged: send({ cmd: "engaged", on: engaged })
    // While the bar shows a remembered menu (`current` false: the app's
    // own is still on its way), its ids are from an earlier run: opening a
    // submenu only shows the remembered items, and a click is replayed by
    // its labels once the real menu is here.
    // (The helper's extra menus, MPRIS's Playback, are live either way.)
    function live(id) {
        if (usable) return true;
        const extra = extraMenus && extraMenus.key === wanted ? (extraMenus.menus || []) : [];
        return extra.some(m => !!find(id, m));
    }
    function open(id) { if (live(id)) send({ cmd: "open", id: id }); }
    function close(id) { if (live(id)) send({ cmd: "close", id: id }); }
    property var pendingClick: null   // { key, labels }
    function click(id) {
        if (live(id)) { send({ cmd: "click", id: id }); return; }
        const labels = labelPath(id, root.tree, []);
        if (labels) { root.pendingClick = { key: root.wanted, labels: labels }; pendingTimer.restart(); }
    }
    function labelPath(id, node, acc) {
        if (!node) return null;
        if (node.id === id) return acc;
        for (const c of node.children || []) {
            const f = labelPath(id, c, acc.concat([String(c.label || "")]));
            if (f) return f;
        }
        return null;
    }
    function replayClick() {
        if (!pendingClick) return;
        const pc = pendingClick;
        pendingClick = null;
        if (pc.key !== wanted) return;
        let node = root.tree;
        for (const l of pc.labels) {
            node = node ? ((node.children || []).find(i => String(i.label || "") === l && i.visible !== false) || null) : null;
        }
        if (node && node.enabled !== false) send({ cmd: "click", id: node.id });
    }
    Timer { id: pendingTimer; interval: 5000; onTriggered: root.pendingClick = null }

    function find(id, node) {
        node = node === undefined ? root.tree : node;
        if (!node) return null;
        if (node.id === id) return node;
        for (const c of node.children || []) {
            const f = find(id, c);
            if (f) return f;
        }
        return null;
    }

    function sync() {
        if (root.forced) {
            const [service, path] = root.forced.split("\n");
            send({ cmd: "watch", key: root.forced, kind: "dbusmenu", service: service, path: path });
            return;
        }
        if (!root.request) { send({ cmd: "unwatch" }); return; }
        send(Object.assign({ cmd: "watch" }, root.request));
    }
    onKeyChanged: sync()
    onForcedChanged: sync()

    IpcHandler {
        target: "appmenu"
        // `hearth-ipc call appmenu watch :1.42 /MenuBar/1` (testing).
        function watch(service: string, path: string): void { root.forced = service ? service + "\n" + path : ""; }
        // `hearth-ipc call appmenu openMenu File`: open that menu of the
        // menu bar, as a click on its title would (tests).
        function openMenu(label: string): string {
            // (The app's own app menu too, which the bold title opens.)
            // "app": the bold app-name menu (the app's own, e.g. a tray menu).
            if (label !== "app" && !root.topLevel.some(i => i.label === label)) return "no menu " + label;
            root.openRequested(label);
            return "ok";
        }
        // `hearth-ipc call appmenu engage true`: as if the pointer were on the
        // global menu bar (tests: reads that wait for it run).
        function engage(on: bool): void { root.setEngaged("ipc", on); }
        function dump(): string { return JSON.stringify({ key: root.key, request: root.request, own: root.ownRequest, forced: root.forced, registrar: root.registrarOwned, appMenu: root.gtkAppMenu,
            // The window's menus once, merged with the extra ones (MPRIS,
            // harvested shortcuts). Sending `menu` and the merged tree both
            // doubled big menus (KSystemLog) past what an IPC reply carries.
            menu: root.tree }); }
        // `hearth-ipc call appmenu summary`: the focused window's route and its
        // menus' titles with item counts, small enough for any menu (dump of a
        // big menu, KSystemLog's, outgrows an IPC reply).
        function summary(): string {
            // What the bar shows (deduped titles), not the raw tree.
            return JSON.stringify({ request: root.request,
                menus: root.topLevel.map(i => {
                    const kids = (i.children || []).filter(c => c.type !== "separator");
                    // unread: its one item is the reader's "…" placeholder
                    // (a ☰ or drawer read only when it opens).
                    return { label: i.label, items: kids.length,
                        unread: kids.length === 1 && kids[0].label === "\u2026" && kids[0].enabled === false };
                }),
                appMenu: root.gtkAppMenu ? (root.gtkAppMenu.children || []).length : 0 });
        }
        // `hearth-ipc call appmenu click "File/New Tab"`: activate an item of
        // the focused window's menus (or of its app menu: "app/Settings…") by
        // its labels, as choosing it in the menu bar would (tests, modules).
        function click(path: string): string {
            const parts = path.split("/");
            let node = parts[0] === "app" ? root.gtkAppMenu : root.tree;
            if (parts[0] === "app") parts.shift();
            for (const label of parts) {
                const kids = node ? (node.children || []) : [];
                node = kids.find(i => i.label === label && i.visible !== false) || null;
                if (!node) return "no item " + label;
            }
            if (node.submenu || (node.children && node.children.length)) return "is a menu: " + path;
            if (node.enabled === false) return "disabled: " + path;
            root.click(node.id);
            return "ok";
        }
    }

    Process {
        id: proc
        command: ["hearth-appmenu"]
        running: root.enabled
        stdinEnabled: true
        onStarted: { root.sync(); if (root.engaged) root.send({ cmd: "engaged", on: true }); }
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "menu") {
                    root.menuKey = m.key;
                    root.menu = m.menu;
                    if (m.key === root.wanted && root.win && m.menu.children.length) {
                        const t = Object.assign({}, root.treeByApp);
                        t[root.win.appId] = m.menu;
                        root.treeByApp = t;
                        root.remember(root.win.appId);
                    }
                    if (root.request && m.key === root.request.key && root.win && m.menu.children.length) {
                        const l = Object.assign({}, root.lastByApp);
                        l[root.win.appId] = root.resolved[m.key] || root.request;
                        root.lastByApp = l;
                    }
                    // appmenu-gtk-module exports an empty menu for dialogs:
                    // still empty a moment later counts as no menu.
                    if (!m.menu.children.length) emptyTimer.restart();
                } else if (m.type === "none") {
                    if (m.key === root.wanted) { root.menuKey = ""; root.menu = null; root.noneKey = m.key; }
                } else if (m.type === "appactions") {
                    root.appActions = m;
                } else if (m.type === "extramenus") {
                    root.extraMenus = m;
                } else if (m.type === "resolved") {
                    const r = Object.assign({}, root.resolved);
                    r[m.key] = m.request;
                    root.resolved = r;
                } else if (m.type === "registrar") {
                    root.registrarOwned = m.owned;
                } else if (m.type === "error") {
                    console.log("appmenu:", m.message);
                }
            }
        }
        onExited: if (root.enabled) restart.start()
    }
    Timer {
        id: emptyTimer
        interval: 1500
        onTriggered: {
            if (root.menu && root.menuKey === root.wanted && !root.forced
                    && root.ownRequest && root.menuKey === root.ownRequest.key
                    && !root.menu.children.length
                    // Only appmenu-gtk-module's exports (empty for XUL apps and
                    // dialogs). An app's own menu bar can still be filling
                    // (LibreOffice's): it isn't written off.
                    && (!root.menuKey.startsWith("g\n") || root.menuKey.includes("/org/appmenu/gtk/"))) {
                const k = root.menuKey;
                if (k.startsWith("x\n")) {
                    root.noneKey = k;
                } else {
                    const e = Object.assign({}, root.emptyKeys);
                    e[k] = true;
                    root.emptyKeys = e;
                }
            }
        }
    }
    // treeByApp kept on disk too, so after a restart of the shell (or the
    // app) the bar shows an app's last menus at once instead of its name
    // and Window alone while they're read again (Spotify's ☰ takes about a
    // second over AT-SPI). The newest 40 apps.
    readonly property string cacheFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
        + "/hearth/app-menus.json"
    property var cacheOrder: []
    // Apps whose remembered menu came from the file and hasn't been seen
    // again this run: if the window turns out to have none (the helper's
    // "none"), that menu is stale and goes.
    property var unconfirmed: ({})
    onNoneKeyChanged: {
        const a = root.win ? root.win.appId : "";
        if (noneKey !== wanted || !a || !unconfirmed[a]) return;
        const t = Object.assign({}, treeByApp);
        delete t[a];
        treeByApp = t;
        const u = Object.assign({}, unconfirmed);
        delete u[a];
        unconfirmed = u;
        cacheOrder = cacheOrder.filter(x => x !== a);
        saveTimer.restart();
    }
    function remember(appId) {
        if (!appId) return;
        if (root.unconfirmed[appId]) {
            const u = Object.assign({}, root.unconfirmed);
            delete u[appId];
            root.unconfirmed = u;
        }
        root.cacheOrder = root.cacheOrder.filter(a => a !== appId).concat([appId]).slice(-40);
        saveTimer.restart();
    }
    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: {
            const out = { version: 1, apps: {} };
            for (const a of root.cacheOrder) if (root.treeByApp[a]) out.apps[a] = root.treeByApp[a];
            cacheMkdir.running = true;
            cacheView.setText(JSON.stringify(out));
        }
    }
    Process { id: cacheMkdir; command: ["mkdir", "-p", root.cacheFile.replace(/\/[^/]*$/, "")] }
    FileView {
        id: cacheView
        path: root.cacheFile
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (!d || d.version !== 1 || !d.apps) return;
                // What this run has seen already wins over the file.
                const t = Object.assign({}, d.apps, root.treeByApp);
                const u = {};
                for (const a in d.apps) if (!root.treeByApp[a]) u[a] = true;
                root.unconfirmed = u;
                root.treeByApp = t;
                root.cacheOrder = Object.keys(d.apps).filter(a => !root.cacheOrder.includes(a)).concat(root.cacheOrder);
            } catch (e) { }
        }
    }

    Timer {
        id: restart
        interval: 3000
        onTriggered: proc.running = root.enabled
    }
}
