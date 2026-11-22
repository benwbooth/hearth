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
    onFocusedChanged: if (focused) heldId = focused.id
    readonly property var win: focused
        || (ShellState.activePopup && heldId ? (Compositor.windows.find(w => w.id === heldId) || null) : null)
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
        if (Compositor.isArbor && w.pid)
            return { key: "x\n" + w.id, kind: "x11", pid: w.pid, title: w.title, window: Number(w.id) };
        return null;
    }
    // Like macOS, an app's menu bar stays while one of its windows without
    // menus (a dialog, a second X11 window) is in front: the last menu seen
    // for that app id is used when the window itself has none.
    property var lastByApp: ({})
    property var resolved: ({})     // x11 key -> the concrete request it found
    property string noneKey: ""
    readonly property var request: {
        const own = root.ownRequest;
        if (own && own.key !== root.noneKey) return own;
        const last = root.win ? root.lastByApp[root.win.appId] : null;
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
    readonly property var topLevel: current
        ? menu.children.filter(i => i.visible && i.type !== "separator" && i.label !== "") : []
    // A GTK app's GNOME 3 style app menu (helper: root child id -2); the
    // menu bar shows it at the top of the bold app-name menu.
    readonly property var gtkAppMenu: current ? (menu.children.find(i => i.id === -2) || null) : null
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
    function open(id) { send({ cmd: "open", id: id }); }
    function close(id) { send({ cmd: "close", id: id }); }
    function click(id) { send({ cmd: "click", id: id }); }

    function find(id, node) {
        node = node === undefined ? root.menu : node;
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
            if (!root.topLevel.some(i => i.label === label)) return "no menu " + label;
            root.openRequested(label);
            return "ok";
        }
        function dump(): string { return JSON.stringify({ key: root.key, request: root.request, own: root.ownRequest, forced: root.forced, registrar: root.registrarOwned, menu: root.menu }); }
    }

    Process {
        id: proc
        command: ["hearth-appmenu"]
        running: root.enabled
        stdinEnabled: true
        onStarted: root.sync()
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "menu") {
                    root.menuKey = m.key;
                    root.menu = m.menu;
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
                    && !root.menu.children.length) {
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
    Timer {
        id: restart
        interval: 3000
        onTriggered: proc.running = root.enabled
    }
}
