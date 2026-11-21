pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// About This Computer (popups/AboutWindow.qml), hearth's own replacement
// for KDE's Info Center: helpers/hearth-sysinfo gathers everything from
// /proc, /sys and standard tools in the background and prints JSON.
//
//   hearth-ipc call about open | more | get
Singleton {
    id: root

    property var info: null          // the summary, then everything after "More Info…"
    property bool full: false
    property bool loading: false
    signal openRequested()
    signal moreRequested()

    function refresh(wantFull) {
        if (proc.running) return;
        loading = true;
        proc.command = wantFull ? ["hearth-sysinfo", "--full"] : ["hearth-sysinfo"];
        proc.wantFull = !!wantFull;
        proc.running = true;
    }

    Process {
        id: proc
        property bool wantFull: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(text);
                    root.full = proc.wantFull;
                } catch (e) { console.warn("hearth-sysinfo:", e); }
                root.loading = false;
            }
        }
        onExited: root.loading = false
    }

    IpcHandler {
        target: "about"
        function open(): void { root.openRequested(); }
        function more(): void { root.moreRequested(); }
        function get(): string { return JSON.stringify(root.info); }
    }
}
