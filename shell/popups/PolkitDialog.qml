import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import "../widgets"
import ".."

// Polkit authentication agent: a centred dialog over a dimmed screen that
// takes the keyboard while a request is pending.
//
// `hearth-ipc call polkit preview` shows it with made-up data (no request is
// sent anywhere), for screenshots while another agent owns the session.
Scope {
    id: root

    PolkitAgent { id: agent }

    property var preview: null
    readonly property var flow: agent.flow ?? root.preview

    IpcHandler {
        target: "polkit"
        function preview(): void {
            const p = {
                message: "Authentication is required to change the system time zone.",
                iconName: "preferences-system-time",
                actionId: "org.freedesktop.timedate1.set-timezone",
                identities: [{ displayName: "ben", id: 1000, isGroup: false },
                             { displayName: "root", id: 0, isGroup: false }],
                selectedIdentity: null,
                isResponseRequired: true,
                inputPrompt: "Password:",
                responseVisible: false,
                supplementaryMessage: "Authentication failed, please try again.",
                supplementaryIsError: true,
                isCompleted: false,
                submit: v => {},
                cancelAuthenticationRequest: () => { root.preview = null; }
            };
            p.selectedIdentity = p.identities[0];
            root.preview = p;
        }
        function close(): void { root.preview = null; }
    }

    PanelWindow {
        id: win
        visible: root.flow !== null && !root.flow.isCompleted
        screen: {
            const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
        }
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "hearth-polkit"
        color: Qt.rgba(0, 0, 0, 0.45)

        onVisibleChanged: if (visible) { password.text = ""; password.forceActiveFocus(); }

        function submit() {
            if (!root.flow || !root.flow.isResponseRequired) return;
            root.flow.submit(password.text);
            password.text = "";
        }
        function cancel() {
            if (root.flow) root.flow.cancelAuthenticationRequest();
        }

        Connections {
            target: agent.flow
            ignoreUnknownSignals: true
            // A new prompt (first one, or a retry after a wrong password).
            function onIsResponseRequiredChanged() {
                if (agent.flow.isResponseRequired) { password.text = ""; password.forceActiveFocus(); }
            }
        }

        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: 480
            implicitHeight: col.implicitHeight + 40
            height: implicitHeight
            radius: Theme.popupRadius
            color: Theme.bgAlt
            border.color: Theme.border
            transform: Translate { x: 0.001; y: 0.001 }

            Keys.onEscapePressed: win.cancel()

            ColumnLayout {
                id: col
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    Icon {
                        Layout.alignment: Qt.AlignTop
                        implicitSize: 48
                        name: root.flow && root.flow.iconName ? root.flow.iconName : "dialog-password"
                        fallback: "dialog-password"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            Layout.fillWidth: true
                            text: "Authentication Required"
                            font.weight: Font.DemiBold
                            font.pointSize: Theme.fontSize + 2
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.flow ? root.flow.message : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.flow ? root.flow.actionId : ""
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                }

                // Identity choice when more than one user/group may authenticate.
                Flow {
                    Layout.fillWidth: true
                    visible: root.flow !== null && root.flow.identities.length > 1
                    spacing: 6
                    Repeater {
                        model: root.flow ? root.flow.identities : []
                        delegate: DialogButton {
                            required property var modelData
                            text: (modelData.isGroup ? "Group " : "") + modelData.displayName
                            icon: modelData.isGroup ? "system-users" : "user-identity"
                            checked: root.flow !== null && root.flow.selectedIdentity !== null
                                     && root.flow.selectedIdentity.id === modelData.id
                                     && root.flow.selectedIdentity.isGroup === modelData.isGroup
                            onClicked: root.flow.selectedIdentity = modelData
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label {
                        Layout.fillWidth: true
                        text: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt : "Password:"
                        color: Theme.fgDim
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.radius
                        color: Theme.bg
                        border.color: password.activeFocus ? Theme.accent : Theme.border
                        TextInput {
                            id: password
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            enabled: root.flow !== null && root.flow.isResponseRequired
                            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            renderType: Text.NativeRendering
                            color: Theme.fg
                            selectionColor: Theme.accentDim
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.fontSize + 1
                            focus: true
                            onAccepted: win.submit()
                            Keys.onEscapePressed: win.cancel()
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.flow ? root.flow.supplementaryMessage : ""
                    color: root.flow && root.flow.supplementaryIsError ? Theme.bad : Theme.fgDim
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        text: "Cancel"
                        onClicked: win.cancel()
                    }
                    DialogButton {
                        text: "Authenticate"
                        primary: true
                        enabled: root.flow !== null && root.flow.isResponseRequired
                        onClicked: win.submit()
                    }
                }
            }
        }
    }

    component DialogButton: MouseArea {
        id: b
        property string text: ""
        property bool primary: false
        property bool checked: false
        property string icon: ""
        implicitWidth: Math.max(100, btnRow.implicitWidth + 28)
        implicitHeight: 34
        hoverEnabled: true
        opacity: enabled ? 1 : 0.5
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: b.primary ? (b.pressed ? Theme.accentDim : b.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                             : (b.pressed ? Theme.pressed : b.containsMouse ? Theme.hover : Theme.bgRaised)
            border.color: b.primary ? "transparent" : b.checked ? Theme.accent : Theme.border
        }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: b.icon !== ""
                implicitSize: 16
                name: b.icon
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: b.text
                color: b.primary ? Theme.bg : Theme.fg
                font.weight: b.primary || b.checked ? Font.DemiBold : Font.Normal
            }
        }
    }
}
