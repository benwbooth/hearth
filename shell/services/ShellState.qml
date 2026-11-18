pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Shell-wide UI state, also reachable from Hyprland binds through
// `hearth-ipc call <target> <function>`.
Singleton {
    id: root
    property bool launcherOpen: false
    property bool doNotDisturb: false
    // The open BarPopup, so opening one closes the others.
    property var activePopup: null

    // Per-screen bar pieces (IPC targets, the launcher) act only on the
    // focused monitor, so a second screen (e.g. hypr-rdp's virtual one)
    // doesn't register duplicate targets or open a second launcher.
    function isActiveScreen(screen) {
        const m = Hyprland.focusedMonitor;
        if (!m || !screen) return true;
        return m.name === screen.name;
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
    }
}
