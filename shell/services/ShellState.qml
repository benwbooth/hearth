pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell-wide UI state, also reachable from Hyprland binds through
// `hearth-ipc call <target> <function>`.
Singleton {
    id: root
    property bool launcherOpen: false
    property bool doNotDisturb: false
    // The open BarPopup, so opening one closes the others.
    property var activePopup: null

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
    }
}
