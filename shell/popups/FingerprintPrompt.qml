import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// "Touch the fingerprint reader": shown while sudo waits for a finger
// (helpers/hearth-fprint-watch). sudo tries the fingerprint first, for up
// to 30 s, and only then asks for the password; without a terminal (an
// app or an agent running sudo) nothing showed that the reader was
// waiting. A glass card under the menu bar names the command, says when a
// finger wasn't recognized, and closes on a match or when sudo moves on to
// the password dialog. polkit's own dialog and the lock screen show their
// fingerprint state themselves, so they get no card. Takes no input.
//
//   hearth-ipc call fingerprint preview "nixos-rebuild switch"
//   HEARTH_FPRINT_PROMPT=0 turns it off.
Scope {
    id: root

    property bool showing: false
    property string command: ""
    property string message: ""
    property bool matched: false

    function begin(cmd) {
        root.command = cmd || "";
        root.message = "";
        root.matched = false;
        root.showing = true;
        timeout.restart();
    }
    function finish(delay) { closeTimer.interval = delay; closeTimer.restart(); }

    Process {
        id: proc
        command: ["hearth-fprint-watch"]
        running: Quickshell.env("HEARTH_FPRINT_PROMPT") !== "0"
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                root.handle(m);
            }
        }
        stderr: SplitParser { onRead: line => console.warn("hearth-fprint-watch:", line) }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 5000; onTriggered: proc.running = Quickshell.env("HEARTH_FPRINT_PROMPT") !== "0" }

    function handle(m) {
        switch (m.type) {
        case "start":
            // Only sudo-like callers: polkit and the lock screen show it themselves.
            if (m.who === "polkit" || m.who === "other" || Lock.locked) return;
            closeTimer.stop();
            if (!root.showing || root.command !== m.command) root.begin(m.command);
            else timeout.restart();
            break;
        case "status":
            if (!root.showing) return;
            switch (m.result) {
            case "verify-match": root.matched = true; root.message = "Allowed"; root.finish(900); break;
            case "verify-no-match": root.message = "Not recognized. Try again."; break;
            case "verify-retry-scan": root.message = "Try again."; break;
            case "verify-swipe-too-short": root.message = "Too short. Try again."; break;
            case "verify-finger-not-centered": root.message = "Center your finger and try again."; break;
            case "verify-remove-and-retry": root.message = "Lift your finger and try again."; break;
            case "verify-disconnected": root.message = "The reader was disconnected."; root.finish(1500); break;
            default: if (m.done) root.finish(1500);
            }
            break;
        case "end":
            if (root.showing && !root.matched) root.finish(200);
            break;
        }
    }

    // pam_fprintd gives up after 30 s.
    Timer { id: timeout; interval: 32000; onTriggered: root.showing = false }
    Timer { id: closeTimer; interval: 900; onTriggered: root.showing = false }

    IpcHandler {
        target: "fingerprint"
        function preview(command: string): void { root.begin(command); }
        function status(result: string): void { root.handle({ type: "status", result: result, done: true }); }
        function hide(): void { root.showing = false; }
    }

    PanelWindow {
        id: win
        screen: Compositor.focusedScreen
        anchors.top: true
        margins.top: Math.round(6 * Theme.pt) - frame.shadowPad
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-fingerprint"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: frame.width + 2 * frame.shadowPad
        implicitHeight: frame.height + 2 * frame.shadowPad
        visible: frame.opacity > 0
        mask: Region {}

        GlassFrame {
            id: frame
            x: shadowPad
            y: shadowPad
            width: Math.round(360 * Theme.pt)
            height: Math.round(64 * Theme.pt)
            radius: Math.round(18 * Theme.pt)
            opacity: root.showing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.showing ? 140 : 260; easing.type: Easing.OutCubic } }
            transform: Translate { x: 0.001; y: 0.001 }

            Rectangle {
                id: badge
                x: Math.round(12 * Theme.pt)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(40 * Theme.pt)
                height: width
                radius: width / 2
                color: root.matched ? Theme.good : Theme.accent
                Behavior on color { ColorAnimation { duration: 200 } }
                Icon {
                    anchors.centerIn: parent
                    implicitSize: Math.round(22 * Theme.pt)
                    name: root.matched ? "object-select-symbolic" : "auth-fingerprint-symbolic"
                    fallback: root.matched ? "dialog-ok" : "fingerprint-gui"
                }
                // A soft pulse while the reader waits.
                SequentialAnimation on opacity {
                    running: root.showing && !root.matched
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.6; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    onStopped: badge.opacity = 1
                }
            }
            Column {
                anchors.left: badge.right
                anchors.leftMargin: Math.round(12 * Theme.pt)
                anchors.right: parent.right
                anchors.rightMargin: Math.round(14 * Theme.pt)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    width: parent.width
                    text: root.matched ? "Allowed" : "Touch the fingerprint reader"
                    font.weight: Font.DemiBold
                }
                Label {
                    width: parent.width
                    text: root.message && !root.matched ? root.message
                          : root.command ? "To run: " + root.command : "An administrator action is waiting"
                    color: root.message && !root.matched ? Theme.warn : Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                    elide: Text.ElideRight
                }
            }
        }
    }
}
