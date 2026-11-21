import QtQuick
import "../../widgets"
import "../../services"
import "../.."

// Remote desktop (arbor-rdp), replacing KRDP's tray icon. Hidden unless the
// arbor-rdp user unit is installed; highlighted while a client is connected.
Indicator {
    id: root
    shown: Rdp.installed
    icon: "krfb-symbolic"
    iconFallback: "network-server-symbolic"
    active: popup.open || Rdp.connected
    tooltip: "Remote Desktop"
    tooltipSub: Rdp.connected ? "Someone is viewing this screen from " + Rdp.clients.join(", ")
              : Rdp.running ? "On: other computers can connect to " + Rdp.listen
              : Rdp.failed ? "Couldn't start. Click for details"
              : "Off. Click to let another computer see and control this screen"
    onMiddleClicked: Rdp.toggle()

    // Dim when stopped, accent dot while running, green ring while connected.
    opacity: Rdp.running || Rdp.failed ? 1 : 0.55
    Rectangle {
        visible: Rdp.running || Rdp.failed
        width: 8; height: 8; radius: 4
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -1
        color: Rdp.failed ? Theme.bad : Rdp.connected ? Theme.good : Theme.accent
        border.color: Theme.bg
        border.width: 1
    }

    popupContent: Column {
        width: 300
        spacing: 6

        Row {
            spacing: 10
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "krdc"
                fallback: "network-server"
                implicitSize: 32
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label { text: "Remote Desktop"; font.bold: true }
                Label {
                    font.pointSize: Theme.smallFontSize
                    color: Rdp.failed ? Theme.bad : Rdp.connected ? Theme.good : Theme.fgDim
                    text: Rdp.busy ? "Working…"
                        : Rdp.connected ? (Rdp.clients.length === 1 ? "1 client connected" : Rdp.clients.length + " clients connected")
                        : Rdp.running ? "Waiting for connections"
                        : Rdp.activeState === "activating" ? "Starting…"
                        : Rdp.failed ? "Couldn't start"
                        : "Off"
                }
            }
        }

        // What this is, in plain words.
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pointSize: Theme.smallFontSize
            color: Theme.fgDim
            text: "Lets another computer see and control this screen with a Remote Desktop (RDP) app, "
                + "such as Windows' Remote Desktop Connection or FreeRDP. Sign in with your usual password."
        }

        // Why it failed, and where to look.
        Label {
            visible: Rdp.failed
            width: parent.width
            wrapMode: Text.Wrap
            font.pointSize: Theme.smallFontSize
            color: Theme.bad
            text: "The server stopped with an error. Another program may already be using the port, "
                + "or the screen named in its settings doesn't exist. Details: journalctl --user -u arbor-rdp"
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        Grid {
            columns: 2
            columnSpacing: 12
            rowSpacing: 4
            Label { text: "Address"; color: Theme.fgDim }
            Label { text: Rdp.listen.startsWith("127.") ? Rdp.listen + " (this computer only)" : Rdp.listen; font.family: Theme.monoFamily }
        }

        // Connected clients, highlighted.
        Repeater {
            model: Rdp.clients
            delegate: Rectangle {
                required property string modelData
                width: parent.width
                height: 30
                radius: Theme.radius
                color: Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, 0.18)
                border.color: Theme.good
                Row {
                    x: 8
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "computer-symbolic"; fallback: "computer"; implicitSize: 16 }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: modelData; font.family: Theme.monoFamily }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        MenuItem {
            text: Rdp.running ? "Stop server" : "Start server"
            icon: Rdp.running ? "media-playback-stop" : "media-playback-start"
            enabled: !Rdp.busy
            onTriggered: Rdp.toggle()
            Tooltip {
                anchorItem: parent
                hovered: parent.containsMouse
                text: Rdp.running ? "Stop accepting remote connections (anyone connected is disconnected)"
                                  : "Start accepting remote connections until you log out"
            }
        }
        MenuItem {
            text: "Start at login"
            icon: "system-run"
            enabled: !Rdp.busy && Rdp.canSetEnabled
            opacity: enabled ? 1 : 0.6
            onTriggered: Rdp.setEnabled(!Rdp.enabled)
            Tooltip {
                anchorItem: parent
                hovered: parent.containsMouse
                text: Rdp.canSetEnabled ? "Turn the server on automatically every time you log in to arbor"
                                        : "Fixed by the system configuration"
            }
            // On/off switch (systemctl --user enable/disable).
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 16; radius: 8
                color: Rdp.enabled ? Theme.accent : Theme.bgRaised
                border.color: Rdp.enabled ? Theme.accent : Theme.border
                Rectangle {
                    width: 12; height: 12; radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    x: Rdp.enabled ? parent.width - width - 2 : 2
                    color: Theme.fg
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
        }
    }
}
