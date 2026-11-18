pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Shell-wide UI state, also reachable from Hyprland binds through
// `hearth-ipc call <target> <function>`.
Singleton {
    id: root
    // The open BarPopup, so opening one closes the others.
    property var activePopup: null

    // Per-screen bar pieces (IPC targets) act only on the
    // focused monitor, so a second screen (e.g. hypr-rdp's virtual one)
    // doesn't register duplicate targets.
    function isActiveScreen(screen) {
        const m = Hyprland.focusedMonitor;
        if (!m || !screen) return true;
        return m.name === screen.name;
    }

    // The launcher is Vicinae; kept so `hearth-ipc call launcher toggle`
    // still works.
    IpcHandler {
        target: "launcher"
        function toggle(): void { Quickshell.execDetached(["vicinae", "toggle"]); }
        function open(): void { Quickshell.execDetached(["vicinae", "open"]); }
        function close(): void { Quickshell.execDetached(["vicinae", "close"]); }
    }
}
