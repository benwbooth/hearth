import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "../widgets"
import "../services"
import ".."

// Notification popups, stacked at the bottom right just above the bar
// (newest nearest the bar) on the focused monitor.
PanelWindow {
    id: win

    screen: {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }
    anchors {
        bottom: true
        right: true
    }
    margins {
        bottom: 8
        right: 8
    }
    // Keep clear of the bar's exclusive zone but claim none ourselves.
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hearth-notifications"
    color: "transparent"
    visible: Notifs.popups.length > 0
    implicitWidth: 420
    implicitHeight: Math.max(1, stack.implicitHeight)
    mask: Region { item: stack }

    Column {
        id: stack
        width: parent.width
        spacing: 8
        transform: Translate { x: 0.001; y: 0.001 }

        Repeater {
            model: ScriptModel { values: Notifs.popups.slice(-5) }
            delegate: Popup {}
        }
    }

    component Popup: Rectangle {
        id: card
        required property var modelData
        readonly property var n: modelData
        readonly property bool critical: n.urgency === NotificationUrgency.Critical
        readonly property var buttons: n.actions.filter(a => a.identifier !== "default")

        width: stack.width
        implicitHeight: content.implicitHeight + 24
        radius: Theme.popupRadius
        color: Theme.bgAlt
        border.width: 1
        border.color: critical ? Theme.bad : Theme.border

        // expireTimeout is in ms; <= 0 means "server decides" (6 s).
        // Critical notifications stay until closed; hovering pauses.
        Timer {
            id: expiry
            interval: card.n.expireTimeout > 0 ? card.n.expireTimeout : 6000
            running: !card.critical && !hoverWatch.hovered
            onTriggered: Notifs.expirePopup(card.n)
        }
        HoverHandler { id: hoverWatch }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) Notifs.dismiss(card.n);
                else Notifs.activate(card.n);
            }
        }

        ColumnLayout {
            id: content
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Icon {
                    implicitSize: 16
                    name: Notifs.appIcon(card.n)
                    fallback: "preferences-desktop-notification"
                }
                Label {
                    Layout.fillWidth: true
                    text: Notifs.appName(card.n)
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
                BarButton {
                    implicitHeight: 24
                    implicitWidth: 24
                    iconSize: 14
                    icon: "window-close"
                    onClicked: Notifs.dismiss(card.n)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Image {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    visible: card.n.image !== "" && status === Image.Ready
                    source: card.n.image
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 112
                    sourceSize.height: 112
                    asynchronous: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        text: card.n.summary
                        textFormat: Text.PlainText
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.n.body
                        textFormat: Text.StyledText
                        color: Theme.fgDim
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        linkColor: Theme.accent
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: card.buttons.length > 0
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: MouseArea {
                        id: btn
                        required property var modelData
                        implicitWidth: btnLabel.implicitWidth + 24
                        implicitHeight: 28
                        hoverEnabled: true
                        onClicked: {
                            btn.modelData.invoke();
                            if (!card.n.resident) Notifs.dismiss(card.n);
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: btn.pressed ? Theme.pressed : btn.containsMouse ? Theme.hover : Theme.bgRaised
                            border.color: Theme.border
                        }
                        Label {
                            id: btnLabel
                            anchors.centerIn: parent
                            text: btn.modelData.text
                        }
                    }
                }
            }
        }
    }
}
