pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Apps follow hearth's light/dark (Settings > Appearance, including Auto's
// switch at 7:00 and 19:00): helpers/hearth-color-scheme switches Qt/KDE
// apps (kdeglobals), browsers and Electron (the settings portal's
// color-scheme, which follows kdeglobals) and GTK (settings.ini, GSettings).
// Run at startup and on every change; it writes only what differs.
//
// Not in test shells (HEARTH_SESSION_DRYRUN=1): they share the real session
// bus, so their GSettings writes would reach the real desktop.
Singleton {
    id: root
    readonly property bool enabled: Quickshell.env("HEARTH_SESSION_DRYRUN") !== "1"
    readonly property string mode: Theme.dark ? "dark" : "light"
    onModeChanged: debounce.restart()
    Component.onCompleted: debounce.restart()

    Timer {
        id: debounce
        interval: 400
        onTriggered: root.apply()
    }
    function apply() {
        if (!root.enabled) return;
        if (proc.running) { debounce.restart(); return; }
        proc.command = ["hearth-color-scheme", root.mode];
        proc.running = true;
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: if (text.trim()) console.log("color scheme:", text.trim())
        }
    }
}
