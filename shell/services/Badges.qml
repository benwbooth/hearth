pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Taskbar badges (unread counts, progress) relayed from the session bus by
// helpers/hearth-badges.
Singleton {
    id: root
    property var byApp: ({})
    readonly property var none: ({ count: 0, countVisible: false, progress: 0, progressVisible: false, urgent: false })

    function forApp(key) {
        const m = root.byApp;
        if (m[key]) return m[key];
        // Desktop ids and LauncherEntry URIs don't always agree on case or
        // reverse-DNS prefixes ("chrome" vs "google-chrome").
        const lk = key.toLowerCase();
        for (const k in m) {
            const kk = k.toLowerCase();
            if (kk === lk || lk.endsWith("." + kk) || kk.endsWith("." + lk)) return m[k];
        }
        return root.none;
    }

    Process {
        id: proc
        command: ["hearth-badges"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const b = JSON.parse(line);
                    const m = Object.assign({}, root.byApp);
                    m[b.app] = b;
                    root.byApp = m;
                } catch (e) {}
            }
        }
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: proc.running = true
    }
}
