import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// "Are you sure you want to shut down your computer now?" for Restart,
// Shut Down, Hibernate and Log Out from the menus (services/Session.qml),
// like macOS: centred on the focused screen, going ahead by itself when the
// countdown ends. Return confirms, Esc cancels.
Scope {
    readonly property var texts: ({
        reboot: { icon: "system-reboot-symbolic", title: "Are you sure you want to restart your computer now?",
                  will: "restart", button: "Restart" },
        poweroff: { icon: "system-shutdown-symbolic", title: "Are you sure you want to shut down your computer now?",
                    will: "shut down", button: "Shut Down" },
        hibernate: { icon: "system-suspend-hibernate-symbolic", title: "Are you sure you want to hibernate your computer now?",
                     will: "hibernate", button: "Hibernate",
                     note: "Everything you have open is saved to disk and comes back when you turn the computer on." },
        logout: { icon: "system-log-out-symbolic", title: "Are you sure you want to quit all applications and log out now?",
                  will: "log you out", button: "Log Out" }
    })

    LazyLoader {
        active: Session.asking !== ""
        PanelWindow {
            id: win
            readonly property var t: texts[Session.asking] || texts.poweroff
            screen: Compositor.focusedScreen
            WlrLayershell.namespace: "hearth-session-confirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: Math.round(300 * Theme.pt)
            implicitHeight: box.implicitHeight
            color: "transparent"

            Rectangle {
                id: box
                anchors.fill: parent
                implicitHeight: col.implicitHeight + 2 * col.y
                transform: Translate { x: 0.001; y: 0.001 }
                radius: Theme.popupRadius
                color: Theme.bgRaised
                border.color: Theme.border
                focus: true
                Keys.onReturnPressed: Session.confirm()
                Keys.onEnterPressed: Session.confirm()
                Keys.onEscapePressed: Session.cancel()

                Column {
                    id: col
                    x: Math.round(18 * Theme.pt)
                    y: Math.round(18 * Theme.pt)
                    width: parent.width - 2 * x
                    spacing: Math.round(8 * Theme.pt)
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 48
                        name: win.t.icon
                        fallback: "system-shutdown-symbolic"
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        text: win.t.title
                        font.weight: Font.Bold
                    }
                    Label {
                        width: parent.width
                        visible: !!win.t.note
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        color: Theme.fgDim
                        font.pointSize: Theme.menuSmallFontSize
                        text: win.t.note || ""
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        color: Theme.fgDim
                        font.pointSize: Theme.menuSmallFontSize
                        text: `If you do nothing, the computer will ${win.t.will} automatically in ${Session.secondsLeft} second${Session.secondsLeft === 1 ? "" : "s"}.`
                            .replace("the computer will log you out", "you'll be logged out")
                    }
                    Item { width: 1; height: Math.round(4 * Theme.pt) }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Math.round(10 * Theme.pt)
                        PushButton {
                            width: Math.round((col.width - parent.spacing) / 2)
                            text: "Cancel"
                            tooltip: "Stay where you are (Esc)."
                            onClicked: Session.cancel()
                        }
                        PushButton {
                            width: Math.round((col.width - parent.spacing) / 2)
                            text: win.t.button
                            primary: true
                            tooltip: win.t.button + " now (Return)."
                            onClicked: Session.confirm()
                        }
                    }
                }
            }
        }
    }
}
