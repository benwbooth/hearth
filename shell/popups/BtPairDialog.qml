import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Bluetooth pairing prompt for services/BtAgent: confirm a passkey, enter a
// PIN/passkey, show one to type on the device, or authorize a device or
// service. A small centred overlay that takes the keyboard while it's up.
Scope {
    id: root
    readonly property var req: BtAgent.request
    readonly property string kind: req ? req.type : ""
    readonly property bool needsInput: kind === "RequestPinCode" || kind === "RequestPasskey"
    readonly property bool displayOnly: kind === "DisplayPasskey" || kind === "DisplayPinCode"

    function title() {
        switch (kind) {
        case "RequestAuthorization": return "Bluetooth Pairing Request";
        case "AuthorizeService": return "Bluetooth Service Request";
        default: return "Pair Bluetooth Device";
        }
    }
    function message() {
        const n = req ? req.name : "";
        switch (kind) {
        case "RequestConfirmation": return "Confirm that " + n + " shows this passkey:";
        case "RequestPinCode": return "Enter the PIN code for " + n + ":";
        case "RequestPasskey": return "Enter the passkey shown on " + n + ":";
        case "DisplayPasskey": return "Type this passkey on " + n + ", then press Enter:";
        case "DisplayPinCode": return "Enter this PIN code on " + n + ":";
        case "RequestAuthorization": return "Allow " + n + " to pair with this computer?";
        case "AuthorizeService": return "Allow " + n + " to use " + serviceName(req.uuid) + "?";
        default: return "";
        }
    }
    function serviceName(uuid) {
        const u = (uuid || "").toLowerCase();
        const short = u.length >= 8 ? u.substring(4, 8) : u;
        const known = {
            "110a": "audio playback (A2DP source)", "110b": "audio playback (A2DP)",
            "110c": "remote control (AVRCP)", "110e": "remote control (AVRCP)",
            "1108": "headset audio (HSP)", "1112": "headset audio (HSP)",
            "111e": "hands-free audio (HFP)", "111f": "hands-free audio (HFP)",
            "1124": "input (HID)", "1812": "input (HID over GATT)",
            "1105": "file transfer (OPP)", "1106": "file transfer (FTP)",
            "1115": "networking (PANU)", "1116": "networking (NAP)",
            "112f": "phonebook access (PBAP)", "1132": "message access (MAP)"
        };
        return known[short] ? known[short] : "service " + uuid;
    }
    function spaced(code) {
        const s = String(code ?? "");
        return s.length === 6 ? s.substring(0, 3) + " " + s.substring(3) : s;
    }

    PanelWindow {
        id: win
        visible: root.req !== null
        screen: Compositor.focusedScreen
        // No anchors: the layer surface is centred on the screen.
        implicitWidth: dialog.width
        implicitHeight: dialog.height
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "hearth-btpair"
        color: "transparent"

        onVisibleChanged: if (visible) reset()
        Connections {
            target: BtAgent
            function onRequestChanged() { if (win.visible) win.reset(); }
        }
        function reset() {
            code.text = "";
            if (root.needsInput) code.forceActiveFocus();
            else dialog.forceActiveFocus();
        }
        function accept() {
            if (root.needsInput) {
                if (!code.acceptableInput) return;
                BtAgent.reply(true, code.text);
            } else {
                BtAgent.reply(true);
            }
        }
        function reject() { BtAgent.reply(false); }

        Rectangle {
            id: dialog
            width: 440
            height: col.implicitHeight + 40
            radius: Theme.popupRadius
            color: Theme.bgAlt
            border.color: Theme.border
            focus: true
            transform: Translate { x: 0.001; y: 0.001 }

            Keys.onEscapePressed: win.reject()
            Keys.onReturnPressed: win.accept()
            Keys.onEnterPressed: win.accept()

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
                        name: root.req && root.req.icon ? root.req.icon : "preferences-system-bluetooth"
                        fallback: "preferences-system-bluetooth"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            Layout.fillWidth: true
                            text: root.title()
                            font.weight: Font.DemiBold
                            font.pointSize: Theme.fontSize + 2
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.message()
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.req ? root.req.address : ""
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                }

                // Passkey / PIN to compare or type on the device.
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.kind === "RequestConfirmation" || root.displayOnly
                    spacing: 0
                    Repeater {
                        model: root.kind === "DisplayPinCode" ? String(root.req?.pincode ?? "").split("")
                             : root.spaced(root.req?.passkey).split("")
                        delegate: Label {
                            required property string modelData
                            required property int index
                            // Digits already typed on a remote keyboard light up.
                            readonly property int digit: index > 3 ? index - 1 : index
                            text: modelData
                            font.family: Theme.monoFamily
                            font.pointSize: Theme.fontSize + 12
                            font.weight: Font.DemiBold
                            color: root.kind === "DisplayPasskey" && modelData !== " "
                                   && digit < (root.req?.entered ?? 0) ? Theme.accent : Theme.fg
                        }
                    }
                }

                // PIN / passkey entry.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.needsInput
                    implicitHeight: 36
                    radius: Theme.radius
                    color: Theme.bg
                    border.color: code.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: code
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        renderType: Text.NativeRendering
                        color: Theme.fg
                        selectionColor: Theme.accentDim
                        font.family: Theme.monoFamily
                        font.pointSize: Theme.fontSize + 2
                        maximumLength: root.kind === "RequestPasskey" ? 6 : 16
                        validator: RegularExpressionValidator {
                            regularExpression: root.kind === "RequestPasskey" ? /[0-9]{1,6}/ : /.{1,16}/
                        }
                        onAccepted: win.accept()
                        Keys.onEscapePressed: win.reject()
                    }
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: code.text === ""
                        text: root.kind === "RequestPasskey" ? "6-digit passkey" : "PIN (often 0000 or 1234)"
                        color: Theme.fgDim
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        visible: !root.displayOnly
                        text: root.kind === "RequestAuthorization" || root.kind === "AuthorizeService" ? "Deny" : "Cancel"
                        onClicked: win.reject()
                    }
                    DialogButton {
                        text: root.displayOnly ? "Close"
                            : root.kind === "RequestAuthorization" || root.kind === "AuthorizeService" ? "Allow"
                            : "Pair"
                        primary: true
                        enabled: !root.needsInput || code.acceptableInput
                        onClicked: win.accept()
                    }
                }
            }
        }
    }

    component DialogButton: MouseArea {
        id: b
        property string text: ""
        property bool primary: false
        implicitWidth: Math.max(100, lbl.implicitWidth + 28)
        implicitHeight: 34
        hoverEnabled: true
        opacity: enabled ? 1 : 0.5
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: b.primary ? (b.pressed ? Theme.accentDim : b.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                             : (b.pressed ? Theme.pressed : b.containsMouse ? Theme.hover : Theme.bgRaised)
            border.color: b.primary ? "transparent" : Theme.border
        }
        Label {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.primary ? Theme.bg : Theme.fg
            font.weight: b.primary ? Font.DemiBold : Font.Normal
        }
    }
}
