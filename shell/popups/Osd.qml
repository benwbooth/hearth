import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "../widgets"
import "../services"
import ".."

// On-screen display for volume and brightness changes: icon, bar and
// percentage, bottom-centre above the bar, gone after 1.5 s. It takes no
// input, and stays quiet while things settle at startup or when the default
// output device changes.
Scope {
    id: root

    property string icon: ""
    property real value: 0      // 0..1 (volume may go above 1)
    property bool muted: false
    property bool showing: false

    // Ignore the initial volume readout (and the one after switching sinks).
    property bool armed: false
    Timer {
        id: armTimer
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    readonly property PwNode sink: Pipewire.defaultAudioSink
    onSinkChanged: { root.armed = false; armTimer.restart(); }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function show(icon, value, muted) {
        root.icon = icon;
        root.value = value;
        root.muted = muted;
        root.showing = true;
        hideTimer.restart();
    }

    function showVolume() {
        if (!root.armed || !root.sink || !root.sink.audio) return;
        const a = root.sink.audio;
        const v = a.volume;
        const icon = a.muted || v <= 0 ? "audio-volume-muted"
                   : v < 0.34 ? "audio-volume-low"
                   : v < 0.67 ? "audio-volume-medium"
                   : "audio-volume-high";
        root.show(icon, v, a.muted);
    }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
    }

    Connections {
        target: Brightness
        function onOsd(percent) {
            root.show(percent >= 50 ? "brightness-high" : "brightness-low", percent / 100, false);
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.showing = false
    }

    PanelWindow {
        id: win
        screen: {
            const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            const s = Quickshell.screens;
            for (let i = 0; i < s.length; i++) if (s[i].name === name) return s[i];
            return s.length > 0 ? s[0] : null;
        }
        anchors.bottom: true
        margins.bottom: 32
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: card.width
        implicitHeight: card.height
        visible: card.opacity > 0
        // Clicks go through to whatever is underneath.
        mask: Region {}

        Rectangle {
            id: card
            width: 320
            height: 56
            radius: Theme.popupRadius
            color: Theme.bgAlt
            border.color: Theme.border
            border.width: 1
            opacity: root.showing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            transform: Translate { x: 0.001; y: 0.001 }

            Icon {
                id: icon
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 28
                name: root.icon
            }
            Rectangle {
                id: track
                anchors.left: icon.right
                anchors.leftMargin: 12
                anchors.right: pct.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Theme.border
                Rectangle {
                    width: parent.width * Math.min(1, Math.max(0, root.value))
                    height: parent.height
                    radius: 3
                    color: root.muted ? Theme.fgDim : Theme.accent
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
                // Past 100% (volume boost) the overflow shows in warn colour.
                Rectangle {
                    visible: root.value > 1
                    anchors.right: parent.right
                    width: parent.width * Math.min(1, root.value - 1) / Math.max(1, root.value)
                    height: parent.height
                    radius: 3
                    color: Theme.warn
                }
            }
            Label {
                id: pct
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "Muted" : Math.round(root.value * 100) + "%"
                color: root.muted ? Theme.fgDim : Theme.fg
            }
        }
    }
}
