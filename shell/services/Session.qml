pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Session actions (lock, sleep, restart, shut down, log out) and the wlogout
// logout screen, through helpers/hearth-session (lock: services/Lock.qml). Hyprland binds reach
// them with `hearth-ipc call session <function>`.
// HEARTH_SESSION_DRYRUN=1 in hearth's environment makes them log instead.
Singleton {
    id: root

    // Locking is hearth's own lock screen (services/Lock.qml), in process.
    function run(action) {
        if (action === "lock") { Lock.lock("manual"); return; }
        Quickshell.execDetached(["hearth-session", action]);
    }
    function menu() { run("menu"); }

    // Hibernate (save everything to disk and power off; it all comes back
    // on the next start) is offered only where logind says it works: swap
    // big enough on disk, and resume set up.
    property bool canHibernate: false
    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "CanHibernate"]
        stdout: StdioCollector { onStreamFinished: root.canHibernate = text.trim() === 's "yes"' }
    }

    // Restart, Shut Down, Hibernate and Log Out from the menus ask first, like macOS:
    // "Are you sure you want to shut down your computer now?", and go ahead
    // by themselves after 60 s (popups/SessionConfirm.qml). Return confirms,
    // Esc cancels. Scripts and key bindings (the IPC below) don't ask.
    property string asking: ""        // "" | "reboot" | "poweroff" | "logout" | "hibernate"
    property int secondsLeft: 0
    function request(action) {
        if (["reboot", "poweroff", "logout", "hibernate"].indexOf(action) < 0) { run(action); return; }
        asking = action;
        secondsLeft = 60;
        countdown.restart();
    }
    function confirm() {
        const a = asking;
        cancel();
        if (a) run(a);
    }
    function cancel() { countdown.stop(); asking = ""; }
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: { if (--root.secondsLeft <= 0) root.confirm(); }
    }

    IpcHandler {
        target: "session"
        function open(): void { root.menu(); }
        function lock(): void { root.run("lock"); }
        function suspend(): void { root.run("suspend"); }
        function hibernate(): void { root.run("hibernate"); }
        function reboot(): void { root.run("reboot"); }
        function poweroff(): void { root.run("poweroff"); }
        function logout(): void { root.run("logout"); }
        // The same, asking first (`hearth-ipc call session ask poweroff`).
        function ask(action: string): void { root.request(action); }
    }
}
