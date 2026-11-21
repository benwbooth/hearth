pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// "Open at Login" for dock/taskbar apps: a copy of the app's .desktop file
// in ~/.config/autostart (the freedesktop autostart spec; Plasma, hearth's
// session and most desktops start these at login).
Singleton {
    id: root
    property var ids: []
    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/autostart"

    function isOn(id) { return ids.indexOf(id) >= 0; }
    function set(id, on) {
        // Optimistic, then re-read what's really there.
        ids = on ? ids.concat([id]) : ids.filter(x => x !== id);
        const script = on
            ? 'mkdir -p "$1"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/usr/share}" | tr : " "); do '
              + 'f="$d/applications/$2.desktop"; if [ -f "$f" ]; then install -m 644 "$f" "$1/$2.desktop"; exit 0; fi; done; exit 1'
            : 'rm -f "$1/$2.desktop"';
        writer.command = ["sh", "-c", script, "sh", dir, id];
        writer.running = true;
    }
    function refresh() { lister.running = true; }

    Process {
        id: writer
        onExited: root.refresh()
    }
    Process {
        id: lister
        command: ["sh", "-c", 'for f in "$1"/*.desktop; do [ -f "$f" ] && basename "$f" .desktop; done; true', "sh", root.dir]
        stdout: StdioCollector { onStreamFinished: root.ids = text.split("\n").filter(s => s !== "") }
    }
    Component.onCompleted: refresh()
}
