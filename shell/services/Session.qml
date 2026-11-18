pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Session actions (lock, sleep, restart, shut down, log out) and the wlogout
// logout screen, all through helpers/hearth-session. Hyprland binds reach
// them with `hearth-ipc call session <function>`.
// HEARTH_SESSION_DRYRUN=1 in hearth's environment makes them log instead.
Singleton {
    id: root

    function run(action) { Quickshell.execDetached(["hearth-session", action]); }
    function menu() { run("menu"); }

    IpcHandler {
        target: "session"
        function open(): void { root.menu(); }
        function lock(): void { root.run("lock"); }
        function suspend(): void { root.run("suspend"); }
        function reboot(): void { root.run("reboot"); }
        function poweroff(): void { root.run("poweroff"); }
        function logout(): void { root.run("logout"); }
    }
}
