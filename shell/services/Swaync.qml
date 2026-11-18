pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Runs SwayNotificationCenter (notification popups + history panel) for
// the Hyprland session. Started here, not as a D-Bus-activated or
// graphical-session service, so it never competes with Plasma's own
// notification server when Ben logs into Plasma.
Singleton {
    Process {
        id: proc
        command: ["swaync"]
        // Not under Plasma (test sessions inherit its environment), where
        // plasmashell is the notification server.
        running: !(Quickshell.env("XDG_CURRENT_DESKTOP") || "").includes("KDE")
        onExited: if (running === false && !(Quickshell.env("XDG_CURRENT_DESKTOP") || "").includes("KDE")) restart.start()
    }
    Timer {
        id: restart
        interval: 3000
        onTriggered: proc.running = true
    }
}
