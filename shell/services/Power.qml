pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sleep & power (Settings > Sleep & Power). Under arbor hearth runs the
// idle daemon itself: swayidle with the values from settings.json `power`
// (display off, lock, sleep after N seconds idle, lock before sleep),
// restarted whenever they change. arbor only reports idle time when no app
// holds an idle inhibitor (a playing video, a game, a presentation), so
// those keep the screen on by themselves.
//
// The power button runs `hearth-ipc call power button`, which does what
// "When I press the power button" says.
Singleton {
    id: root

    readonly property var p: Settings.power
    readonly property bool active: Compositor.isArbor && Settings.loaded

    readonly property var idleArgs: {
        const a = [];
        const lockCmd = "hearth-session lock >/dev/null 2>&1 &";
        if (p.lock > 0) a.push("timeout", String(p.lock), lockCmd);
        if (p.displayOff > 0)
            a.push("timeout", String(p.displayOff), "arbor msg action power-off-monitors",
                   "resume", "arbor msg action power-on-monitors");
        if (p.sleep > 0) a.push("timeout", String(p.sleep), "hearth-session suspend");
        // Lock first, give the locker a moment to cover the screen, then sleep.
        if (p.lockOnSleep) a.push("before-sleep", lockCmd + " sleep 1");
        a.push("after-resume", "arbor msg action power-on-monitors");
        a.push("lock", lockCmd);
        return a;
    }

    // Named after the Wayland display so a test hearth (nested compositor)
    // never kills the real session's daemon.
    readonly property var command: ["bash", "-c",
        'name="hearth-idle-${WAYLAND_DISPLAY:-x}"; pkill -u "$(id -u)" -f "^$name " 2>/dev/null; exec -a "$name" swayidle -w "$@"',
        "hearth-idle"].concat(idleArgs)

    onCommandChanged: restart.restart()
    onActiveChanged: restart.restart()
    Timer {
        id: restart
        interval: 400
        onTriggered: {
            idle.running = false;
            if (root.active) idle.running = true;
        }
    }
    Process {
        id: idle
        command: root.command
        stderr: SplitParser { onRead: l => console.warn("swayidle:", l) }
        onExited: code => { if (root.active && code !== 0 && code !== 143 && code !== 15) retry.start(); }
    }
    Timer { id: retry; interval: 5000; onTriggered: if (root.active && !idle.running) idle.running = true }

    function powerButton() {
        switch (p.powerButton) {
        case "sleep": Session.run("suspend"); break;
        case "lock": Session.run("lock"); break;
        case "poweroff": Session.run("poweroff"); break;
        case "displayoff": Compositor.arborAction("PowerOffMonitors", {}); break;
        case "nothing": break;
        default: Session.menu(); break;
        }
    }

    IpcHandler {
        target: "power"
        function button(): void { root.powerButton(); }
        function running(): bool { return idle.running; }
        function idleCommand(): string { return JSON.stringify(root.idleArgs); }
    }
}
