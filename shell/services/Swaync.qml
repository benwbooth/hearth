pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Runs SwayNotificationCenter (notification popups + history panel) for
// the hearth session. Started here, not as a D-Bus-activated or
// graphical-session service, so it never competes with Plasma's own
// notification server when Ben logs into Plasma.
//
// The config is the repo's swaync/config.json adjusted to the layout and
// Settings > Notifications: with the mac layout popups and the panel sit
// top-right under the menu bar, with the classic panel bottom-right above
// it. Written to the cache dir and passed with -c; changes reload swaync.
Singleton {
    id: root

    readonly property bool wanted: !(Quickshell.env("XDG_CURRENT_DESKTOP") || "").includes("KDE")
    readonly property string basePath: Quickshell.shellDir + "/../swaync/config.json"
    readonly property string configPath: Quickshell.cachePath("swaync-config.json")
    property string base: ""
    property bool written: false

    readonly property string config: {
        if (!base) return "";
        let c;
        try { c = JSON.parse(base); } catch (e) { return ""; }
        const top = Settings.mac;
        c.positionX = "right";
        c.positionY = top ? "top" : "bottom";
        c["control-center-positionX"] = "right";
        c["control-center-positionY"] = top ? "top" : "bottom";
        c["control-center-margin-top"] = top ? Theme.menuBarHeight + 8 : 8;
        c["control-center-margin-bottom"] = top ? 8 : Theme.barHeight + 8;
        c["control-center-margin-right"] = 8;
        c.timeout = Settings.notifications.timeout;
        return JSON.stringify(c, null, 2);
    }
    onConfigChanged: if (config) { out.setText(config); }

    function setDnd(on) { Quickshell.execDetached(["swaync-client", on ? "-dn" : "-df", "-sw"]); }

    FileView {
        path: root.basePath
        printErrors: false
        onLoaded: root.base = text()
        // No repo config (unusual): run swaync with its own.
        onLoadFailed: root.written = true
    }
    FileView {
        id: out
        path: root.configPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            if (root.written && proc.running) Quickshell.execDetached(["swaync-client", "-R", "-sw"]);
            root.written = true;
        }
    }

    Process {
        id: proc
        command: root.base ? ["swaync", "-c", root.configPath] : ["swaync"]
        // Not under Plasma (test sessions inherit its environment), where
        // plasmashell is the notification server.
        running: root.wanted && root.written
        onExited: if (root.wanted) restart.start()
    }
    Timer {
        id: restart
        interval: 3000
        onTriggered: proc.running = true
    }
}
