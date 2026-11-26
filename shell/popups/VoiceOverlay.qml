import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The voice assistant on screen (services/Voice.qml): while it listens, a
// glow of shifting colour runs along the screen's edges and swells with
// your voice (shaders/siri.frag; Settings > Voice > Glowing edge), and a
// glass card under the menu bar's right end shows what it heard, what it's
// doing and its answer, like Siri on macOS. Esc or the × closes it; the
// orb listens again. Clicks go through the glow.
Scope {
    id: root
    readonly property bool active: Voice.phase === "connecting" || Voice.phase === "listening" || Voice.phase === "transcribing" || Voice.phase === "thinking"
    // Smoothed microphone level for the glow.
    property real lvl: 0
    Behavior on lvl { NumberAnimation { duration: 90 } }
    Connections {
        target: Voice
        function onLevelChanged() { root.lvl = Voice.level; }
        function onPhaseChanged() {
            if (Voice.phase === "answer") hideTimer.restart();
            else hideTimer.stop();
        }
    }
    // An answer stays a while, then the card goes (not while the pointer is on it).
    Timer {
        id: hideTimer
        interval: 14000
        onTriggered: if (!cardHover.hovered && !Voice.speaking) Voice.dismiss(); else restart()
    }

    // --- the edge glow ---
    PanelWindow {
        id: glowWin
        visible: Voice.cfg.edgeGlow && (root.active || glow.opacity > 0.01)
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-voice-glow"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {}

        ShaderEffect {
            id: glow
            anchors.fill: parent
            fragmentShader: "../shaders/siri.frag.qsb"
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.active ? 260 : 420; easing.type: Easing.OutCubic } }
            readonly property size itemSize: Qt.size(width, height)
            property real time: 0
            readonly property real level: root.lvl
            readonly property real radius: 12
            readonly property real bandWidth: 26
            readonly property real thinking: Voice.phase === "thinking" || Voice.phase === "transcribing" ? 1 : 0
            NumberAnimation on time { running: glowWin.visible; from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite }
        }
    }

    // --- the card ---
    PanelWindow {
        id: cardWin
        visible: Voice.visible || card.opacity > 0.01
        screen: Compositor.focusedScreen
        anchors { top: true; right: true }
        margins.top: Theme.menuBarHeight + 8
        margins.right: 10
        implicitWidth: Math.round(400 * Theme.pt) + 2 * card.shadowPad
        implicitHeight: Math.round(320 * Theme.pt)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-voice"
        WlrLayershell.keyboardFocus: Voice.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        mask: Region { item: card }

        GlassFrame {
            id: card
            x: shadowPad
            y: 4
            width: parent.width - 2 * shadowPad
            height: Math.min(parent.height - 4 - shadowPad, content.implicitHeight + 2 * pad)
            readonly property int pad: Math.round(14 * Theme.pt)
            radius: Math.round(22 * Theme.pt)
            opacity: Voice.visible ? 1 : 0
            scale: Voice.visible ? 1 : 0.94
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: Voice.visible ? 180 : 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Voice.visible ? 320 : 160; easing.type: Voice.visible ? Easing.OutBack : Easing.InCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            focus: true
            Keys.onEscapePressed: Voice.dismiss()

            HoverHandler { id: cardHover }

            Column {
                id: content
                x: card.pad
                y: card.pad
                width: card.width - 2 * card.pad
                spacing: Math.round(8 * Theme.pt)

                Item {
                    width: parent.width
                    height: Math.round(40 * Theme.pt)

                    // The orb: listens again when clicked.
                    MouseArea {
                        id: orbArea
                        width: height
                        height: parent.height
                        hoverEnabled: true
                        onClicked: Voice.toggle()
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.5)
                        }
                        ShaderEffect {
                            anchors.fill: parent
                            fragmentShader: "../shaders/siri.frag.qsb"
                            readonly property size itemSize: Qt.size(width, height)
                            property real time: 0
                            readonly property real level: root.active ? root.lvl : 0.15
                            readonly property real radius: width / 2
                            readonly property real bandWidth: 5
                            readonly property real thinking: Voice.phase === "thinking" ? 1 : 0
                            NumberAnimation on time { running: cardWin.visible; from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite }
                        }
                        Icon {
                            anchors.centerIn: parent
                            implicitSize: Math.round(18 * Theme.pt)
                            name: "audio-input-microphone-symbolic"
                            fallback: "audio-input-microphone"
                        }
                        Tooltip {
                            anchorItem: orbArea
                            hovered: orbArea.containsMouse
                            text: root.active ? "Stop listening" : "Ask again"
                            subtext: "Shortcut: " + Voice.shortcutText
                        }
                    }
                    Label {
                        anchors.left: orbArea.right
                        anchors.leftMargin: Math.round(10 * Theme.pt)
                        anchors.right: closeBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: ({ connecting: "Starting…", listening: "Listening…", transcribing: "Listening…",
                                 thinking: Voice.thinkingText, answer: Voice.replyError ? "hearth" : "hearth" })[Voice.phase] || ""
                        color: Theme.fgSecondary
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(24 * Theme.pt)
                        height: width
                        hoverEnabled: true
                        onClicked: Voice.dismiss()
                        Rectangle { anchors.fill: parent; radius: width / 2; color: closeBtn.containsMouse ? Theme.hover : "transparent" }
                        Icon { anchors.centerIn: parent; implicitSize: Math.round(14 * Theme.pt); name: "window-close-symbolic"; fallback: "window-close" }
                        Tooltip { anchorItem: closeBtn; hovered: closeBtn.containsMouse; text: "Close"; subtext: "Esc" }
                    }
                }

                // What you said.
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: Voice.heard ? "“" + Voice.heard + "”" : (Voice.phase === "listening" ? "Go ahead, I'm listening." : "")
                    color: Voice.heard ? Theme.fg : Theme.fgSecondary
                    font.pointSize: Theme.fontSize + 3
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                // What it did.
                Repeater {
                    model: Voice.steps
                    Row {
                        required property var modelData
                        spacing: 6
                        Icon { implicitSize: 14; name: "emblem-ok-symbolic"; fallback: "dialog-ok"; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: modelData.text; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize; width: content.width - 24 }
                    }
                }
        ApprovalCard { width: parent.width }
                // The answer.
                Label {
                    width: parent.width
                    visible: Voice.phase === "answer" && text !== ""
                    text: Voice.reply
                    color: Voice.replyError ? Theme.warn : Theme.fg
                    font.pointSize: Theme.fontSize + 1
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
