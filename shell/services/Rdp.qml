pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The hypr-rdp systemd user service (RDP into this Hyprland session).
// State comes from `systemctl --user show`; the listening address and the
// connected clients from `ss`, matched on the service's MainPID (hypr-rdp
// itself has no status IPC).
Singleton {
    id: root

    // HEARTH_RDP_UNIT points it at another unit (headless tests).
    property string unit: Quickshell.env("HEARTH_RDP_UNIT") || "hypr-rdp.service"
    readonly property int defaultPort: 3389

    // LoadState=not-found until the unit is installed: the tray hides then.
    property bool installed: false
    property string activeState: "inactive"   // active, activating, deactivating, failed, inactive
    property string subState: ""
    property bool enabled: false               // starts with the session ("Start at login")
    // enable/disable only work for a unit with an [Install] section that
    // systemd can (un)link itself; a NixOS-wired `wantedBy` is fixed.
    property bool canSetEnabled: false
    property int mainPid: 0
    property string listen: ""                 // "127.0.0.1:3389" while running, else from ExecStart/config
    property var clients: []                   // ["192.168.1.20:51234", ...]
    property bool busy: false                  // a start/stop/enable is in flight

    readonly property bool running: activeState === "active"
    readonly property bool failed: activeState === "failed"
    readonly property bool connected: running && clients.length > 0

    // A poll already in flight may predate the last action: queue another.
    property bool pollAgain: false
    function refresh() {
        if (poll.running) root.pollAgain = true;
        else poll.running = true;
    }

    function systemctl(verb) {
        if (act.running) return;   // one systemctl at a time
        root.busy = true;
        act.command = ["systemctl", "--user", verb, root.unit];
        act.running = true;
    }
    function start() { systemctl("start"); }
    function stop() { systemctl("stop"); }
    function toggle() { systemctl(root.running ? "stop" : "start"); }
    function setEnabled(on) { systemctl(on ? "enable" : "disable"); }

    // "[::ffff:1.2.3.4]:5" / "1.2.3.4:5" -> port number
    function portOf(addr) {
        const i = addr.lastIndexOf(":");
        return i < 0 ? -1 : parseInt(addr.slice(i + 1));
    }
    function cleanAddr(addr) {
        return addr.replace("[::ffff:", "").replace("]:", ":").replace(/^\[/, "").replace(/^\*:/, "0.0.0.0:");
    }

    function parse(text) {
        const parts = text.split("\n--- ");
        const props = {};
        for (const l of parts[0].split("\n")) {
            const i = l.indexOf("=");
            if (i > 0) props[l.slice(0, i)] = l.slice(i + 1);
        }
        root.installed = props.LoadState !== undefined && props.LoadState !== "not-found";
        root.activeState = props.ActiveState || "inactive";
        root.subState = props.SubState || "";
        const ufs = props.UnitFileState || "";
        root.enabled = ufs.startsWith("enabled") || (props.WantedBy || "").includes("graphical-session.target");
        root.canSetEnabled = ufs === "enabled" || ufs === "disabled";
        root.mainPid = parseInt(props.MainPID || "0") || 0;

        let listenAddr = "";
        const peers = [];
        const sockets = parts.find(p => p.startsWith("ss\n")) || "";
        if (root.mainPid > 0) {
            const tag = "pid=" + root.mainPid + ",";
            const rows = sockets.split("\n").filter(l => l.includes(tag))
                                .map(l => l.trim().split(/\s+/));
            const lst = rows.find(r => r[0] === "LISTEN");
            if (lst) listenAddr = cleanAddr(lst[3]);
            const port = lst ? portOf(lst[3]) : -1;
            for (const r of rows)
                if (r[0] === "ESTAB" && portOf(r[3]) === port) peers.push(cleanAddr(r[4]));
        }
        if (!listenAddr) {
            // Not running: what it would listen on. CLI beats config file;
            // hypr-rdp's own default is loopback only.
            const m = (props.ExecStart || "").match(/--bind[= ]([^\s;]+)/);
            const cfg = (parts.find(p => p.startsWith("cfg\n")) || "").match(/bind\s*=\s*["']([^"']+)["']/);
            listenAddr = m ? m[1] : cfg ? cfg[1] : "127.0.0.1:" + root.defaultPort;
        }
        root.listen = listenAddr;
        if (JSON.stringify(peers) !== JSON.stringify(root.clients)) root.clients = peers;
    }

    Process {
        id: poll
        command: ["sh", "-c", `
            systemctl --user show "$1" -p LoadState,ActiveState,SubState,UnitFileState,WantedBy,MainPID,ExecStart 2>/dev/null
            echo '--- ss'
            ss -Htanp 2>/dev/null
            echo '--- cfg'
            grep -sE '^[[:space:]]*bind[[:space:]]*=' "\${XDG_CONFIG_HOME:-$HOME/.config}/hypr-rdp/config.toml"
            true`, "sh", root.unit]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: if (root.pollAgain) { root.pollAgain = false; poll.running = true; }
    }

    Process {
        id: act
        onExited: { root.busy = false; root.refresh(); settle.restart(); }
    }
    // Start is asynchronous (activating -> active, then the socket appears).
    Timer { id: settle; interval: 1200; onTriggered: root.refresh() }

    // `hearth-ipc call rdp toggle|start|stop|enable|disable|status`
    IpcHandler {
        target: "rdp"
        function toggle(): void { root.toggle(); }
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function enable(): void { root.setEnabled(true); }
        function disable(): void { root.setEnabled(false); }
        function status(): string {
            return JSON.stringify({ installed: root.installed, state: root.activeState,
                                    enabled: root.enabled, listen: root.listen, clients: root.clients });
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
