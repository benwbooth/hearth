import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "../widgets"
import "../services"
import ".."

// hearth's password prompt for system changes (polkit), like macOS's
// "wants to make changes" sheet: replaces KDE's plasma-polkit-agent. Apps
// asking to install, mount, change settings or run as administrator show
// this; it carries the PAM prompts through, so a fingerprint request shows
// its message ("Place your finger…") while the password still works.
//
// Off with HEARTH_POLKIT=0 (test sessions: the agent registers on the
// system bus for the whole login session).
Scope {
    id: root
    readonly property bool enabled: Quickshell.env("HEARTH_POLKIT") !== "0" && !Quickshell.env("HEARTH_GREETER")

    // Only created when enabled: a PolkitAgent registers itself for the
    // whole login session as soon as it exists.
    LazyLoader {
        id: agentLoader
        active: root.enabled
        PolkitAgent { path: "/org/hearth/PolkitAgent" }
    }
    readonly property var flow: agentLoader.item ? agentLoader.item.flow : null
    readonly property bool shown: !!flow && !flow.isCompleted

    // "Use Fingerprint" after the reader gave up (pam_fprintd times out or
    // runs out of tries, and polkit's PAM stack moves on to the password).
    // Starting the sign-in over starts with the reader again: Quickshell
    // sets up a new PAM session when the selected identity changes or an
    // attempt fails. Shown only when the reader took part in this request.
    property bool sawFinger: false
    property bool restarting: false
    onFlowChanged: { sawFinger = false; restarting = false; }
    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onSupplementaryMessageChanged() {
            const m = root.flow ? String(root.flow.supplementaryMessage) : "";
            if (/finger/i.test(m)) { root.sawFinger = true; root.restarting = false; }
        }
    }
    function useFingerprint() {
        const f = root.flow;
        if (!f || !f.isResponseRequired) return;
        root.restarting = true;
        const ids = Array.prototype.slice.call(f.identities || []);
        const cur = f.selectedIdentity;
        const other = ids.find(i => i !== cur) || null;
        if (other && cur) {
            // A new session for another identity, then one for ours again:
            // no failed attempt, no delay.
            f.selectedIdentity = other;
            f.selectedIdentity = cur;
        } else {
            // An empty answer fails the password step (after PAM's usual
            // short delay) and the new attempt starts with the reader.
            f.submit("");
        }
    }

    PanelWindow {
        id: win
        // Made again if a monitor dropout takes its surface (widgets/KeepShown).
        KeepShown { window: win; want: root.shown }
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-polkit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(0, 0, 0, 0.25)

        onVisibleChanged: if (visible) { pass.text = ""; pass.forceActiveFocus(); }
        Connections {
            target: root.flow
            ignoreUnknownSignals: true
            function onIsResponseRequiredChanged() { if (root.flow && root.flow.isResponseRequired) { pass.text = ""; pass.forceActiveFocus(); } }
            function onAuthenticationFailed() { if (!root.restarting) shake.restart(); pass.text = ""; }
        }
        function submit() { if (root.flow && root.flow.isResponseRequired) root.flow.submit(pass.text); }
        function cancel() { if (root.flow) root.flow.cancelAuthenticationRequest(); }

        GlassFrame {
            id: card
            width: 420
            height: col.implicitHeight + 48
            x: Math.round((win.width - width) / 2)
            y: Math.round(win.height * 0.28)
            radius: 22
            tint: Theme.glassColor(Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 1) : Qt.rgba(0.97, 0.97, 0.975, 1), 0.85)
            SequentialAnimation {
                id: shake
                loops: 1
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
                    name: root.flow && root.flow.iconName ? root.flow.iconName : "dialog-password"
                    fallback: "system-lock-screen"
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Authentication Required"
                    font.weight: Font.Bold
                    font.pointSize: Theme.fontSize + 2
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.flow ? root.flow.message : ""
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.fgDim
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.flow ? root.flow.supplementaryMessage : ""
                    color: root.flow && root.flow.supplementaryIsError ? Theme.bad : Theme.fgSecondary
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.pointSize: Theme.smallFontSize
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.flow && root.flow.selectedIdentity ? "As " + String(root.flow.selectedIdentity.displayName || root.flow.selectedIdentity) : ""
                    visible: text !== ""
                    color: Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                }
                TextBox {
                    id: pass
                    Layout.fillWidth: true
                    placeholder: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                    enabled: !!root.flow && root.flow.isResponseRequired
                    input.echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    onAccepted: win.submit()
                    Keys.onEscapePressed: win.cancel()
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    // Just a fingerprint: wakes the reader again.
                    Item {
                        id: fpButton
                        visible: root.sawFinger && !!root.flow && root.flow.isResponseRequired && !root.restarting
                        implicitWidth: 32
                        implicitHeight: 32
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Theme.fg
                            opacity: fpMouse.pressed ? 0.18 : fpMouse.containsMouse ? 0.1 : 0
                        }
                        Icon {
                            anchors.centerIn: parent
                            implicitSize: 22
                            name: "fingerprint-symbolic"
                            fallback: "fingerprint"
                        }
                        MouseArea {
                            id: fpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.useFingerprint()
                        }
                        Tooltip {
                            anchorItem: fpButton
                            hovered: fpMouse.containsMouse
                            text: "Use your fingerprint"
                            subtext: "Turns the fingerprint reader on again, if you missed it"
                        }
                    }
                    Label {
                        visible: root.restarting
                        text: "Starting the fingerprint reader…"
                        color: Theme.fgSecondary
                        font.pointSize: Theme.smallFontSize
                    }
                    PushButton { text: "Cancel"; tooltip: "Don't allow it (Esc)"; onClicked: win.cancel() }
                    PushButton {
                        text: "OK"
                        primary: true
                        enabled: !!root.flow && root.flow.isResponseRequired
                        tooltip: "Allow it with your password (Return)"
                        onClicked: win.submit()
                    }
                }
            }
        }
    }
}
