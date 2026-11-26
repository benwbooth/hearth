import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The keyring's password prompt (services/KeyringPrompter): shown when an
// app wants a saved password and the keyring is locked, or when an app
// creates a keyring or changes its password. Same look as the polkit sheet.
Scope {
    id: root
    readonly property var req: KeyringPrompter.request
    readonly property bool busy: KeyringPrompter.busy
    readonly property bool isPassword: !!req && req.type === "password"
    readonly property bool isNew: !!req && !!req.passwordNew
    // oo7 / gnome-keyring's unlock prompt (the common one) gets friendlier
    // words; anything else shows the keyring's own text.
    readonly property bool isUnlock: !!req && req.title === "Unlock Keyring"
    readonly property string keyringName: {
        const m = req ? /[“"]([^”"]+)[”"]/.exec(req.description || "") : null;
        return m ? m[1] : "";
    }
    readonly property bool mismatch: isNew && confirmText !== "" && passText !== confirmText
    property string passText: ""
    property string confirmText: ""
    readonly property bool canSubmit: !busy && (!isNew || (passText !== "" && passText === confirmText))

    function headline() {
        if (!req) return "";
        if (isUnlock) return "Unlock Your Saved Passwords";
        return req.title || "Keyring";
    }
    // hearth-askpass's prompts: sudo's "Administrator password", an SSH
    // key's passphrase, other SSH questions. Their own words, no keyring talk.
    readonly property string kind: req && req.kind ? req.kind : ""
    function body() {
        if (!req) return "";
        if (kind) return req.message || "";
        if (isUnlock)
            return "An app wants a password it saved in your keyring"
                + (keyringName ? " “" + keyringName + "”" : "")
                + ", but the keyring is locked. Type the keyring's password to unlock it.";
        return req.description || req.message || "";
    }
    function hint() {
        if (!req) return "";
        if (kind) return req.description || "";
        if (isUnlock)
            return "This is usually the password you log in with. If you changed your login password recently, try your old one.";
        if (isNew) return "Pick a password you'll remember: you'll need it to get these saved passwords back. Your login password is a good choice, because then logging in unlocks it too.";
        return req.description && req.message ? req.message : "";
    }
    function warningText() {
        if (!req || !req.warning) return "";
        if (req.warning === "The unlock password was incorrect" || req.warning === "The original password was incorrect")
            return "That password didn't work. Check Caps Lock and try again.";
        return req.warning;
    }

    PanelWindow {
        id: win
        // Made again if a monitor dropout takes its surface (widgets/KeepShown).
        KeepShown { window: win; want: root.req !== null }
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-keyring"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(0, 0, 0, 0.25)

        onVisibleChanged: if (visible) reset()
        Connections {
            target: KeyringPrompter
            // sudo's askpass prompt taking the place of the dialog opened at
            // the fingerprint step keeps what was typed.
            function onRequestChanged() { if (win.visible && !(root.req && root.req.continuesEarly)) win.reset(); }
            function onRetry() { shake.restart(); win.reset(); }
        }
        function reset() {
            pass.text = "";
            confirm.text = "";
            choice.checked = !!root.req && !!root.req.choiceChosen;
            if (root.isPassword) pass.input.forceActiveFocus();
            else card.forceActiveFocus();
        }
        function submit() {
            if (!root.canSubmit) return;
            KeyringPrompter.reply(true, root.isPassword ? pass.text : "", choice.checked);
        }
        function cancel() { if (!root.busy) KeyringPrompter.reply(false, "", choice.checked); }

        GlassFrame {
            id: card
            width: 440
            height: col.implicitHeight + 48
            x: Math.round((win.width - width) / 2)
            y: Math.round(win.height * 0.28)
            radius: 22
            focus: true
            transform: Translate { x: 0.001; y: 0.001 }
            tint: Theme.glassColor(Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 1) : Qt.rgba(0.97, 0.97, 0.975, 1), 0.85)
            Keys.onEscapePressed: win.cancel()
            Keys.onReturnPressed: win.submit()
            Keys.onEnterPressed: win.submit()
            SequentialAnimation {
                id: shake
                NumberAnimation { target: card; property: "x"; to: card.x - 12; duration: 50 }
                NumberAnimation { target: card; property: "x"; to: card.x + 12; duration: 70 }
                NumberAnimation { target: card; property: "x"; to: card.x - 8; duration: 60 }
                NumberAnimation { target: card; property: "x"; to: Math.round((win.width - card.width) / 2); duration: 60 }
            }

            ColumnLayout {
                id: col
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 10

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    implicitSize: 56
                    name: root.kind === "sudo" ? "security-high" : root.kind === "ssh" ? "network-server" : "dialog-password"
                    fallback: "system-lock-screen"
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.headline()
                    font.weight: Font.Bold
                    font.pointSize: Theme.fontSize + 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.body()
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.fgDim
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.hint()
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.mismatch ? "The two passwords don't match yet." : root.warningText()
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.bad
                    font.pointSize: Theme.smallFontSize
                }
                // sudo waiting for a fingerprint (KeyringPrompter.sudoWaiting):
                // the reader works alongside the password.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    visible: !!root.req && !!root.req.early
                    spacing: 8
                    Rectangle {
                        id: fpBadge
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: KeyringPrompter.fingerMatched ? Theme.good : Theme.accent
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Icon {
                            anchors.centerIn: parent
                            implicitSize: 16
                            name: KeyringPrompter.fingerMatched ? "object-select-symbolic" : "auth-fingerprint-symbolic"
                            fallback: KeyringPrompter.fingerMatched ? "dialog-ok" : "fingerprint-gui"
                        }
                        SequentialAnimation on opacity {
                            running: win.visible && !!root.req && !!root.req.early && !KeyringPrompter.fingerMatched
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                            onStopped: fpBadge.opacity = 1
                        }
                    }
                    Label {
                        text: KeyringPrompter.fingerMatched ? "Allowed"
                            : root.busy ? "Checking your password…"
                            : KeyringPrompter.fingerMessage || "Waiting for your fingerprint"
                        color: KeyringPrompter.fingerMessage && !KeyringPrompter.fingerMatched && !root.busy ? Theme.warn : Theme.fgSecondary
                        font.pointSize: Theme.smallFontSize
                    }
                }
                TextBox {
                    id: pass
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: root.isPassword
                    enabled: !root.busy
                    placeholder: root.isNew ? "New password" : root.kind === "ssh-key" ? "Passphrase"
                        : root.kind ? "Password" : "Keyring password"
                    input.echoMode: TextInput.Password
                    onTextChanged: root.passText = text
                    onAccepted: root.isNew && confirm.text === "" ? confirm.input.forceActiveFocus() : win.submit()
                    Keys.onEscapePressed: win.cancel()
                }
                TextBox {
                    id: confirm
                    Layout.fillWidth: true
                    visible: root.isNew
                    enabled: !root.busy
                    placeholder: "Type it again"
                    input.echoMode: TextInput.Password
                    onTextChanged: root.confirmText = text
                    onAccepted: win.submit()
                    Keys.onEscapePressed: win.cancel()
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.req && !!root.req.choiceLabel
                    spacing: 10
                    Toggle {
                        id: choice
                        onToggled: c => checked = c
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.req ? root.req.choiceLabel || "" : ""
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    PushButton {
                        text: "What's this?"
                        visible: !root.kind
                        tooltip: "Help › Saved passwords: what the keyring is and which password it wants"
                        onClicked: Help.guideRequested("passwords", "")
                    }
                    Item { Layout.fillWidth: true }
                    PushButton {
                        text: root.req && root.req.cancelLabel ? root.req.cancelLabel : "Cancel"
                        tooltip: root.kind ? "Don't allow it (Esc)" : "Leave it locked: the app goes without the saved password (Esc)"
                        enabled: !root.busy
                        onClicked: win.cancel()
                    }
                    PushButton {
                        text: root.busy ? "Checking…" : root.req && root.req.continueLabel ? root.req.continueLabel : "OK"
                        primary: true
                        enabled: root.canSubmit
                        tooltip: root.isUnlock ? "Unlock the keyring with this password (Return)" : "Continue (Return)"
                        onClicked: win.submit()
                    }
                }
            }
        }
    }
}
