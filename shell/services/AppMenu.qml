pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The focused window's global menu (com.canonical.dbusmenu), relayed by
// helpers/hearth-appmenu. The address comes from the compositor (arbor's
// niri IPC `Window.app_menu`); Hyprland has no source for it, so there the
// menu bar only shows the app's fallback menu.
//
// menu: root item { id, children: [{ id, label, enabled, visible, type,
// toggleType, toggleState, icon, shortcut, submenu, children }] } or null.
Singleton {
    id: root

    readonly property var address: Compositor.focusedWindow ? Compositor.focusedWindow.appMenu : null
    readonly property string key: address && address.service_name && address.object_path
        ? address.service_name + "\n" + address.object_path : ""
    property var menu: null
    // For tests: follow a given menu regardless of the focused window.
    property string forced: ""
    property string menuKey: ""
    property bool registrarOwned: false
    readonly property string wanted: forced || key
    readonly property var topLevel: menu && wanted !== "" && menuKey === wanted
        ? menu.children.filter(i => i.visible && i.type !== "separator" && i.label !== "") : []
    readonly property bool available: topLevel.length > 0

    // Off where nothing could ever supply an address (Hyprland), unless
    // HEARTH_APPMENU=1 (testing the helper there).
    readonly property bool enabled: Compositor.isNiri || Quickshell.env("HEARTH_APPMENU") === "1"

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
        const k = root.forced || root.key;
        if (!k) { send({ cmd: "unwatch" }); return; }
        const [service, path] = k.split("\n");
        send({ cmd: "watch", service: service, path: path });
    }
    onKeyChanged: sync()
    onForcedChanged: sync()

    IpcHandler {
        target: "appmenu"
        // `hearth-ipc call appmenu watch :1.42 /MenuBar/1` (testing).
        function watch(service: string, path: string): void { root.forced = service ? service + "\n" + path : ""; }
        function dump(): string { return JSON.stringify({ key: root.key, forced: root.forced, registrar: root.registrarOwned, menu: root.menu }); }
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
                    root.menuKey = m.service + "\n" + m.path;
                    root.menu = m.menu;
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
        id: restart
        interval: 3000
        onTriggered: proc.running = root.enabled
    }
}
