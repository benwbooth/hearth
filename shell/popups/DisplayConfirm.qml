import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// "Keep these display settings?" after Settings > Displays applies a
// change: shown in the middle of every screen (so it's visible whatever
// the change did), counting down 15 s, then services/Displays.qml puts the
// old settings back. Return keeps, Esc reverts.
Scope {
    Variants {
        model: Displays.pending ? Quickshell.screens : []
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "hearth-display-confirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: 460
            implicitHeight: 150
            color: "transparent"

            Rectangle {
                id: box
                anchors.fill: parent
                transform: Translate { x: 0.001; y: 0.001 }
                radius: Theme.popupRadius
                color: Theme.bgRaised
                border.color: Theme.border
                focus: true
                Keys.onReturnPressed: Displays.keep()
                Keys.onEnterPressed: Displays.keep()
                Keys.onEscapePressed: Displays.revert()

                Column {
                    x: 20
                    y: 18
                    width: parent.width - 40
                    spacing: 6
                    Row {
                        spacing: 10
                        Icon { implicitSize: 32; name: "preferences-desktop-display" }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Keep these display settings?"
                            font.weight: Font.Bold
                            font.pointSize: Theme.fontSize + 2
                        }
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        color: Theme.fgDim
                        text: `If you don't choose, the old settings come back in ${Displays.secondsLeft} second${Displays.secondsLeft === 1 ? "" : "s"}.`
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 18
                    spacing: 10
                    PushButton {
                        text: "Revert"
                        tooltip: "Put the previous display settings back now (Esc)."
                        onClicked: Displays.revert()
                    }
                    PushButton {
                        text: "Keep Changes"
                        primary: true
                        tooltip: "Keep the new display settings (Return)."
                        onClicked: Displays.keep()
                    }
                }
            }
        }
    }
}
